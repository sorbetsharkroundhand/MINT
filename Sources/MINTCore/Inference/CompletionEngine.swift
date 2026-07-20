import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 온디바이스 자동완성 추론 엔진 (M2/M3·M5, PLAN §4·§10·§12).
///
/// - 모델은 **1회 lazy 로드** 후 상주. 모델 id가 바뀌면 교체 로드.
/// - 프롬프트는 조립기(`ContextAssembler`)가 만든 `AssembledPrompt`만 받는다 —
///   엔진은 조립에 관여하지 않는다 (PLAN §10).
/// - `complete(prompt:parameters:)`는 **취소 가능**: 호출 태스크가 취소되면
///   토큰 스트림 소비가 끝나고, 스트림 종료가 내부 생성 태스크까지 취소한다.
/// - 이어쓰기(continuation) 경로는 직전 요청과의 공통 접두 KV를 재사용해
///   새 토큰만 증분 프리필한다 (PLAN §12 — `PromptCacheBox`).
/// - 토큰 상한(기본 12) + **문장 경계 조기 종료**로 단어/구 단위 제안을 보장.
public actor CompletionEngine {

    /// 한 번의 자동완성 결과 + 지연 측정치(M2 로그·상태 바 표시용).
    public struct Completion: Sendable {
        /// 고스트로 띄울 제안 텍스트(후처리 완료). 비어 있으면 "제안 없음".
        public let text: String
        /// 생성 시작 → 첫 텍스트 청크까지 (모델 로드 시간 제외).
        public let timeToFirstChunk: TimeInterval?
        /// 생성 시작 → 종료(문장 경계 조기 종료 포함).
        public let totalTime: TimeInterval
        /// 자연 종료(EOS·토큰 상한)일 때만 채워지는 처리량 정보.
        public let promptTokensPerSecond: Double?
        public let generationTokensPerSecond: Double?
        /// 문장 경계에서 조기 종료했는지.
        public let stoppedAtSentenceBoundary: Bool
        /// 프롬프트 전체 토큰 수 (클램프 후) — 벤치·예산 튜닝용 (PLAN §13).
        public let promptTokenCount: Int
        /// KV 재사용으로 프리필을 건너뛴 토큰 수 (PLAN §12 효과 측정).
        public let reusedPromptTokens: Int

        static let empty = Completion(
            text: "",
            timeToFirstChunk: nil,
            totalTime: 0,
            promptTokensPerSecond: nil,
            generationTokensPerSecond: nil,
            stoppedAtSentenceBoundary: false,
            promptTokenCount: 0,
            reusedPromptTokens: 0
        )
    }

    private var container: ModelContainer?
    private var loadedModelID: String?
    private var loadTask: Task<ModelContainer, Error>?
    private var loadingModelID: String?
    /// 이어쓰기 프리필 KV 재사용 (PLAN §12). 모델 교체 시 폐기.
    private let promptCache = PromptCacheBox()

    public init() {}

    /// 모델을 미리 로드한다(앱 시작 시 호출 — 첫 제안 지연 방지).
    /// 이미 같은 모델이 로드돼 있으면 즉시 반환.
    public func preload(
        parameters: CompletionParameters,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        _ = try await loadedContainer(modelID: parameters.modelID, onProgress: onProgress)
    }

    /// 조립된 프롬프트로 다음 단어/구를 생성한다 (PLAN §10).
    ///
    /// 호출 태스크 취소에 즉시 협조한다 — 새 키 입력 시 컨트롤러가 태스크를
    /// 취소하면 진행 중 생성도 함께 멈춘다.
    public func complete(
        prompt: AssembledPrompt,
        parameters: CompletionParameters,
        onLoadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Completion {
        if case .continuation(let text) = prompt,
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .empty
        }
        let container = try await loadedContainer(
            modelID: parameters.modelID, onProgress: onLoadProgress)
        try Task.checkCancellation()
        return try await Self.runGeneration(
            in: container, prompt: prompt, parameters: parameters,
            promptCache: promptCache)
    }

    /// 구 API 호환(MINTBench 단발 측정 등) — 조립기 없이 prefix만으로 생성.
    /// 앱 경로는 컨트롤러가 조립기를 거쳐 `complete(prompt:)`를 쓴다.
    public func complete(
        prefix: String,
        parameters: CompletionParameters,
        onLoadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Completion {
        try await complete(
            prompt: ContextAssembler.assemble(
                prefix: prefix, document: nil, style: parameters.promptStyle),
            parameters: parameters,
            onLoadProgress: onLoadProgress
        )
    }

    /// 폴더 멤버 문서들의 내용에서 짧은 폴더 이름을 생성한다 (사이드바 DnD 1.4).
    ///
    /// promptStyle 설정과 무관하게 항상 instruct 챗으로 실행 — 이어쓰기는 이름
    /// 짓기에 맞지 않는다. 자동완성과 같은 컨테이너를 공유한다(모델 이중 로드 없음).
    /// 프롬프트 캐시에는 손대지 않는다 — 예측의 프리픽스가 식지 않는다.
    /// 빈 문자열을 반환하면 호출부가 기본 이름("새 폴더")을 유지한다.
    public func generateFolderName(
        content: String,
        parameters: CompletionParameters
    ) async throws -> String {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let container = try await loadedContainer(
            modelID: parameters.modelID, onProgress: nil)
        try Task.checkCancellation()
        return try await container.perform { context in
            let chat: [Chat.Message] = [
                .system(Prompting.folderNameSystem),
                .user(Prompting.folderNameUser(content: content)),
            ]
            let userInput = UserInput(
                chat: chat, additionalContext: ["enable_thinking": false])
            let input = try await context.processor.prepare(input: userInput)
            try Task.checkCancellation()

            let generateParameters = GenerateParameters(
                maxTokens: 16,
                temperature: Float(parameters.temperature),
                topP: Float(parameters.topP)
            )

            var text = ""
            let stream = try MLXLMCommon.generate(
                input: input, parameters: generateParameters, context: context)
            for await generation in stream {
                if Task.isCancelled { break }
                if case .chunk(let chunk) = generation {
                    text += chunk
                    // 이름은 한 줄 — 내용이 생긴 뒤 줄바꿈이 나오면 그만 받는다
                    // (문장 경계 로직은 이름의 마침표 오검출 위험이 있어 안 쓴다).
                    if text.contains("\n"),
                        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        break
                    }
                }
            }
            try Task.checkCancellation()
            return Self.cleanFolderName(text)
        }
    }

    /// 백그라운드 이해 파이프라인의 일회성 instruct 호출 (M6, PLAN §9) —
    /// 씬 요약·장 요약·인물 프로파일링이 이 하나로 통한다.
    ///
    /// `generateFolderName`과 같은 규율: 항상 instruct 챗, 프롬프트 캐시 불가침
    /// (예측의 프리픽스가 식지 않는다), 협조 취소(타이핑 재개 → 인덱서가 태스크를
    /// 취소하면 다음 청크에서 멈춘다). 실패·빈 결과는 호출부가 무시한다 —
    /// 백그라운드 실패는 다음 패스가 다시 시도하면 그만이다.
    /// `stopAtBlankLine`: 기본 true — 요약처럼 한 문단만 받을 때 빈 줄(문단
    /// 경계)에서 조기 종료한다. 씬 분석·심화 추출처럼 **여러 줄** 형식을 받는
    /// 호출은 false로 넘긴다 — 모델이 항목 사이에 빈 줄을 넣어도 출력이 중간에
    /// 끊기지 않는다 (이해 타임라인 텍스트 잘림의 원인 중 하나였다).
    public func generateOneShot(
        system: String,
        user: String,
        maxTokens: Int,
        parameters: CompletionParameters,
        stopAtBlankLine: Bool = true
    ) async throws -> String {
        guard !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let container = try await loadedContainer(
            modelID: parameters.modelID, onProgress: nil)
        try Task.checkCancellation()
        return try await container.perform { context in
            let chat: [Chat.Message] = [.system(system), .user(user)]
            let userInput = UserInput(
                chat: chat, additionalContext: ["enable_thinking": false])
            let input = try await context.processor.prepare(input: userInput)
            try Task.checkCancellation()

            let generateParameters = GenerateParameters(
                maxTokens: maxTokens,
                temperature: Float(parameters.temperature),
                topP: Float(parameters.topP)
            )

            var text = ""
            let stream = try MLXLMCommon.generate(
                input: input, parameters: generateParameters, context: context)
            for await generation in stream {
                if Task.isCancelled { break }
                if case .chunk(let chunk) = generation {
                    text += chunk
                    // 요약은 한 문단 — 내용이 생긴 뒤 빈 줄(문단 경계)이 나오면
                    // 그만 받는다 (설명·부연이 이어지는 걸 끊는다).
                    if stopAtBlankLine,
                        text.contains("\n\n"),
                        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        break
                    }
                }
            }
            try Task.checkCancellation()
            let cleaned = Self.stripThinking(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.stripSurroundingQuotes(cleaned)
        }
    }

    /// 읽기 전용 Writing Agent의 한 모델 턴 (PLAN §14 M10, ADR-1).
    /// 자동완성·백그라운드와 같은 컨테이너를 공유하며, 도구 스키마를 챗 템플릿과
    /// 생성 스트림 양쪽에 전달해야 `.toolCall`이 실제로 발행된다.
    public func generateAgentTurn(
        messages: [AgentChatMessage],
        tools: [ToolSpec],
        parameters: CompletionParameters,
        onChunk: @Sendable @escaping (String) -> Void
    ) async throws -> AgentModelTurn {
        let container = try await loadedContainer(
            modelID: parameters.modelID, onProgress: nil)
        try Task.checkCancellation()
        return try await container.perform { context in
            let chat: [Chat.Message] = messages.map { message in
                switch message.role {
                case .system: .system(message.content)
                case .user: .user(message.content)
                case .assistant: .assistant(message.content)
                case .tool: .tool(message.content)
                }
            }
            let toolSpecs: [ToolSpec]? = tools.isEmpty ? nil : tools
            let userInput = UserInput(
                chat: chat, tools: toolSpecs,
                additionalContext: ["enable_thinking": false])
            let input = try await context.processor.prepare(input: userInput)
            try Task.checkCancellation()

            let generateParameters = GenerateParameters(
                maxTokens: min(1_024, max(64, parameters.maxTokens)),
                temperature: Float(parameters.temperature),
                topP: Float(parameters.topP))
            let stream = try MLXLMCommon.generate(
                input: input, parameters: generateParameters, context: context,
                tools: toolSpecs)
            var text = ""
            var calls: [AgentToolCall] = []
            for await generation in stream {
                if Task.isCancelled { break }
                switch generation {
                case .chunk(let chunk):
                    text += chunk
                    onChunk(chunk)
                case .toolCall(let call):
                    calls.append(
                        AgentToolCall(
                            name: call.function.name,
                            arguments: call.function.arguments))
                case .info:
                    break
                }
            }
            try Task.checkCancellation()
            return AgentModelTurn(
                text: Self.stripThinking(text)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                toolCalls: calls)
        }
    }

    // MARK: - 모델 로드 (1회, 교체 가능)

    private func loadedContainer(
        modelID: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> ModelContainer {
        if let container, loadedModelID == modelID {
            return container
        }
        // 같은 모델을 이미 로드 중이면 그 결과를 공유한다(중복 로드 방지).
        if let loadTask, loadingModelID == modelID {
            let loaded = try await loadTask.value
            try Task.checkCancellation()
            return loaded
        }
        // 다른 모델로 교체 — 기존 로드/컨테이너와 함께 프롬프트 KV도 버린다
        // (다른 모델의 캐시는 쓰레기가 아니라 독이다).
        loadTask?.cancel()
        container = nil
        loadedModelID = nil
        promptCache.invalidate()

        let task = Task { try await Self.load(modelID: modelID, onProgress: onProgress) }
        loadTask = task
        loadingModelID = modelID
        do {
            let loaded = try await task.value
            // 로드 중 또 다른 모델로 교체됐을 수 있다 — 내 로드가 최신일 때만 채택.
            if loadingModelID == modelID {
                container = loaded
                loadedModelID = modelID
                loadTask = nil
                loadingModelID = nil
            }
            try Task.checkCancellation()
            return loaded
        } catch {
            if loadingModelID == modelID {
                loadTask = nil
                loadingModelID = nil
            }
            throw error
        }
    }

    private static func load(
        modelID: String,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> ModelContainer {
        _ = Self.mlxConfigured
        let configuration = ModelConfiguration(id: modelID)
        // 허브 다운로드(캐시됨) + 토크나이저 로드 + 가중치 로드.
        return try await #huggingFaceLoadModelContainer(
            configuration: configuration,
            progressHandler: { progress in
                onProgress?(progress.fractionCompleted)
            })
    }

    /// MLX GPU 캐시 상한 — 타이핑마다 생성이 반복되므로 캐시가 무한히
    /// 자라지 않게 1회 설정한다.
    private static let mlxConfigured: Void = {
        Memory.cacheLimit = 256 * 1024 * 1024
    }()

    // MARK: - 생성

    private static func runGeneration(
        in container: ModelContainer,
        prompt: AssembledPrompt,
        parameters: CompletionParameters,
        promptCache: PromptCacheBox
    ) async throws -> Completion {
        let start = Date()
        return try await container.perform { context in
            let generateParameters = GenerateParameters(
                maxTokens: parameters.maxTokens,
                temperature: Float(parameters.temperature),
                topP: Float(parameters.topP)
            )

            let input: LMInput
            let style: PromptStyle
            var kvCache: [KVCache]?
            var promptTokens: [Int] = []
            var promptTokenCount = 0
            var reusedPromptTokens = 0
            var cacheInUse = false

            switch prompt {
            case .continuation(let text):
                style = .continuation
                // 챗 템플릿을 거치지 않고 조립된 텍스트를 그대로 이어쓴다.
                // 어절 중간("나는 오…")에서도 이어짐 + 선행 공백이 보존된다.
                var tokens = context.tokenizer.encode(text: text)
                // 토큰 안전 예산 (PLAN §11) — 문자 창이 과할 때만 발동. 잘라낼 때도
                // 512 격자 단위로 잘라, 다음 요청과의 공통 접두가 유지되게 한다.
                if tokens.count > parameters.maxPromptTokens {
                    let overflow = tokens.count - parameters.maxPromptTokens
                    let drop = min(((overflow + 511) / 512) * 512, tokens.count - 1)
                    tokens = Array(tokens.dropFirst(drop))
                }
                promptTokens = tokens
                promptTokenCount = tokens.count
                if parameters.kvCacheEnabled,
                    let reuse = promptCache.begin(
                        modelID: parameters.modelID, tokens: tokens,
                        model: context.model, parameters: generateParameters)
                {
                    kvCache = reuse.cache
                    reusedPromptTokens = reuse.reusedTokens
                    cacheInUse = true
                    input = LMInput(tokens: MLXArray(reuse.suffix))
                } else {
                    input = LMInput(tokens: MLXArray(tokens))
                }
            case .instruct(let system, let user):
                style = .instruct
                let chat: [Chat.Message] = [.system(system), .user(user)]
                // Qwen3 계열의 사고(thinking) 모드는 자동완성에 불필요 — 끈다.
                let userInput = UserInput(
                    chat: chat, additionalContext: ["enable_thinking": false])
                input = try await context.processor.prepare(input: userInput)
                promptTokenCount = input.text.tokens.size
                // instruct는 챗 템플릿이 본문 뒤에도 토큰을 붙여 LCP 이득이 작다 —
                // KV 재사용은 이어쓰기 경로만 (PLAN §12, M5 범위).
            }

            do {
                try Task.checkCancellation()

                var text = ""
                var timeToFirstChunk: TimeInterval?
                var info: GenerateCompletionInfo?
                var stoppedAtBoundary = false

                let stream = try MLXLMCommon.generate(
                    input: input, cache: kvCache, parameters: generateParameters,
                    context: context)
                for await generation in stream {
                    if Task.isCancelled { break }
                    switch generation {
                    case .chunk(let chunk):
                        if timeToFirstChunk == nil {
                            timeToFirstChunk = Date().timeIntervalSince(start)
                        }
                        text += chunk
                        // 정지 사다리 (PLAN §10): 기본 = 문장 경계, 대화 모드 =
                        // 발화 끝(닫는 따옴표) — 대사 중간의 마침표에서 끊지 않는다.
                        let cut =
                            parameters.stopAtUtteranceEnd
                            ? cutAtUtteranceEnd(text) : cutAtSentenceBoundary(text)
                        if let cut {
                            text = cut
                            stoppedAtBoundary = true
                        }
                    case .info(let generationInfo):
                        info = generationInfo
                    case .toolCall:
                        break
                    }
                    // 루프 이탈 → 스트림 종료 → 내부 생성 태스크 취소.
                    if stoppedAtBoundary { break }
                }
                // 조기 종료·협조 취소여도 캐시엔 "프롬프트 + α"가 앞에서부터 순서대로
                // 들어가 있다 — 기록해 두면 다음 요청이 LCP까지 재사용한다.
                if cacheInUse { promptCache.commit(tokens: promptTokens) }
                try Task.checkCancellation()

                return Completion(
                    text: postProcess(text, style: style),
                    timeToFirstChunk: timeToFirstChunk,
                    totalTime: Date().timeIntervalSince(start),
                    promptTokensPerSecond: info?.promptTokensPerSecond,
                    generationTokensPerSecond: info?.tokensPerSecond,
                    stoppedAtSentenceBoundary: stoppedAtBoundary,
                    promptTokenCount: promptTokenCount,
                    reusedPromptTokens: reusedPromptTokens
                )
            } catch {
                // 생성이 던졌다 — 캐시 상태를 신뢰할 수 없으니 버린다.
                if cacheInUse { promptCache.abandon() }
                throw error
            }
        }
    }

    // MARK: - 프롬프트 (폴더 명명 전용 — 자동완성 프롬프트는 ContextAssembler 소유)

    private enum Prompting {
        static let folderNameSystem = """
            너는 문서 묶음에 어울리는 폴더 이름을 짓는 도우미다. \
            문서들의 공통 주제를 담은 짧은 한국어 폴더 이름(2~5단어, 명사형)을 \
            하나만 출력한다. 설명·번호·따옴표·마침표 없이 이름만 출력한다.
            """

        static func folderNameUser(content: String) -> String {
            """
            다음 문서들을 담을 폴더의 이름을 지어라.

            \(content)
            """
        }
    }

    // MARK: - 후처리

    /// 문장 경계 문자(포함)까지 자른다. 없으면 nil.
    /// 단어/구 단위 제안 원칙 — 최대 한 문장에서 멈춘다 (PLAN §10 정지 사다리).
    private static let sentenceBoundaries: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", "\n",
    ]

    private static func cutAtSentenceBoundary(_ text: String) -> String? {
        guard let index = text.firstIndex(where: { sentenceBoundaries.contains($0) })
        else { return nil }
        return String(text[...index])
    }

    /// 발화 끝 문자 — 대화 모드의 정지 조건 (PLAN §10). 닫는 따옴표(포함)까지
    /// 자른다. 개행은 안전 바닥 — 모델이 따옴표를 안 닫고 문단을 넘어가면 끊는다.
    private static let utteranceBoundaries: Set<Character> = [
        "”", "\"", "」", "』", "\n",
    ]

    private static func cutAtUtteranceEnd(_ text: String) -> String? {
        guard let index = text.firstIndex(where: { utteranceBoundaries.contains($0) })
        else { return nil }
        return String(text[...index])
    }

    private static func postProcess(_ raw: String, style: PromptStyle) -> String {
        var text = raw
        if style == .instruct {
            text = stripThinking(text)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            text = stripSurroundingQuotes(text)
        }
        // 고스트는 한 줄만 그린다 — 첫 줄바꿈 이전까지만.
        if let newline = text.firstIndex(of: "\n") {
            text = String(text[..<newline])
        }
        // 끝쪽 공백 정리. 선행 공백은 continuation에서 어절 경계 정보라 보존한다.
        while let last = text.last, last.isWhitespace {
            text.removeLast()
        }
        return text
    }

    /// 폴더 이름 후처리 — 모델 출력에서 깨끗한 한 줄 이름만 남긴다.
    /// 빈 결과를 반환하면 호출부가 기본 이름("새 폴더")을 유지한다.
    private static func cleanFolderName(_ raw: String) -> String {
        var text = stripThinking(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let newline = text.firstIndex(of: "\n") {
            text = String(text[..<newline])
        }
        text = stripSurroundingQuotes(text.trimmingCharacters(in: .whitespaces))
        // 앞머리 마크다운·불릿·번호 마커만 벗긴다 — 마커 뒤 공백을 요구해
        // "2024.03 회고"처럼 숫자·점으로 시작하는 정상 이름은 건드리지 않는다.
        text = text.replacingOccurrences(
            of: #"^(?:#{1,6}\s+|[-*•]\s+|\d+[.)]\s+|>\s+)+"#,
            with: "", options: .regularExpression)
        // 끝쪽 문장부호·공백 정리 — "이름만" 규칙을 모델이 어겨도 복구.
        let trailing: Set<Character> = [
            ".", "。", "!", "！", "?", "？", "…", ",", "，", ":", "：",
        ]
        while let last = text.last, trailing.contains(last) || last.isWhitespace {
            text.removeLast()
        }
        // 내부 공백 뭉치는 하나로.
        text = text.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression)
        return String(text.prefix(20)).trimmingCharacters(in: .whitespaces)
    }

    /// Qwen3 계열이 `<think>…</think>`를 앞에 붙이는 경우 제거.
    /// 닫히지 않은 사고 출력은 본문이 아니므로 통째로 버린다.
    private static func stripThinking(_ text: String) -> String {
        let trimmed = text.drop(while: { $0.isWhitespace || $0.isNewline })
        guard trimmed.hasPrefix("<think>") else { return text }
        guard let end = trimmed.range(of: "</think>") else { return "" }
        return String(trimmed[end.upperBound...])
    }

    /// 양끝이 모두 따옴표로 감싸졌을 때만 벗긴다(instruct 응답 정리).
    private static func stripSurroundingQuotes(_ text: String) -> String {
        let quotes: Set<Character> = ["\"", "“", "”", "'", "‘", "’"]
        guard text.count >= 2,
            let first = text.first, let last = text.last,
            quotes.contains(first), quotes.contains(last)
        else { return text }
        return String(text.dropFirst().dropLast())
    }
}

extension CompletionEngine: AgentTurnGenerating {}
