import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 온디바이스 자동완성 추론 엔진 (M2/M3, PLAN §4).
///
/// - 모델은 **1회 lazy 로드** 후 상주(PLAN §9-2). 모델 id가 바뀌면 교체 로드.
/// - `complete(prefix:parameters:)`는 **취소 가능**: 호출 태스크가 취소되면
///   토큰 스트림 소비가 끝나고, 스트림 종료가 내부 생성 태스크까지 취소한다.
/// - 토큰 상한(기본 12) + **문장 경계 조기 종료**로 단어/구 단위 제안을 보장.
/// - 프롬프트 방식은 두 가지(PLAN §9-4): 순수 이어쓰기(챗 템플릿 우회) vs
///   instruct — 어느 쪽이 나은지는 M2 벤치(MINTBench)로 측정해 확정한다.
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
    }

    private var container: ModelContainer?
    private var loadedModelID: String?
    private var loadTask: Task<ModelContainer, Error>?
    private var loadingModelID: String?

    public init() {}

    /// 모델을 미리 로드한다(앱 시작 시 호출 — 첫 제안 지연 방지).
    /// 이미 같은 모델이 로드돼 있으면 즉시 반환.
    public func preload(
        parameters: CompletionParameters,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        _ = try await loadedContainer(modelID: parameters.modelID, onProgress: onProgress)
    }

    /// `prefix`(커서 앞 문맥)에 이어질 다음 단어/구를 생성한다.
    ///
    /// 호출 태스크 취소에 즉시 협조한다 — 새 키 입력 시 컨트롤러가 태스크를
    /// 취소하면 진행 중 생성도 함께 멈춘다 (PLAN §5).
    public func complete(
        prefix: String,
        parameters: CompletionParameters,
        onLoadProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Completion {
        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Completion(
                text: "",
                timeToFirstChunk: nil,
                totalTime: 0,
                promptTokensPerSecond: nil,
                generationTokensPerSecond: nil,
                stoppedAtSentenceBoundary: false
            )
        }
        let container = try await loadedContainer(
            modelID: parameters.modelID, onProgress: onLoadProgress)
        try Task.checkCancellation()
        return try await Self.runGeneration(
            in: container, prefix: prefix, parameters: parameters)
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
        // 다른 모델로 교체 — 기존 로드/컨테이너를 버린다.
        loadTask?.cancel()
        container = nil
        loadedModelID = nil

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
        prefix: String,
        parameters: CompletionParameters
    ) async throws -> Completion {
        let start = Date()
        return try await container.perform { context in
            let input: LMInput
            switch parameters.promptStyle {
            case .continuation:
                // 챗 템플릿을 거치지 않고 커서 앞 텍스트를 그대로 이어쓴다.
                // 어절 중간("나는 오…")에서도 이어짐 + 선행 공백이 보존된다.
                let tokens = context.tokenizer.encode(text: prefix)
                input = LMInput(tokens: MLXArray(tokens))
            case .instruct:
                let chat: [Chat.Message] = [
                    .system(Prompting.instructSystem),
                    .user(Prompting.instructUser(prefix: prefix)),
                ]
                // Qwen3 계열의 사고(thinking) 모드는 자동완성에 불필요 — 끈다.
                let userInput = UserInput(
                    chat: chat, additionalContext: ["enable_thinking": false])
                input = try await context.processor.prepare(input: userInput)
            }
            try Task.checkCancellation()

            let generateParameters = GenerateParameters(
                maxTokens: parameters.maxTokens,
                temperature: Float(parameters.temperature),
                topP: 0.9
            )

            var text = ""
            var timeToFirstChunk: TimeInterval?
            var info: GenerateCompletionInfo?
            var stoppedAtBoundary = false

            let stream = try MLXLMCommon.generate(
                input: input, parameters: generateParameters, context: context)
            for await generation in stream {
                if Task.isCancelled { break }
                switch generation {
                case .chunk(let chunk):
                    if timeToFirstChunk == nil {
                        timeToFirstChunk = Date().timeIntervalSince(start)
                    }
                    text += chunk
                    if let cut = cutAtSentenceBoundary(text) {
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
            try Task.checkCancellation()

            return Completion(
                text: postProcess(text, style: parameters.promptStyle),
                timeToFirstChunk: timeToFirstChunk,
                totalTime: Date().timeIntervalSince(start),
                promptTokensPerSecond: info?.promptTokensPerSecond,
                generationTokensPerSecond: info?.tokensPerSecond,
                stoppedAtSentenceBoundary: stoppedAtBoundary
            )
        }
    }

    // MARK: - 프롬프트 (instruct)

    private enum Prompting {
        static let instructSystem = """
            너는 글쓰기 자동완성 엔진이다. 사용자가 쓰던 글의 마지막 부분을 받아, \
            그 마지막 글자 바로 뒤에 자연스럽게 이어질 짧은 다음 구절(최대 한 문장)을 \
            출력한다. 설명·인사·따옴표·머리말 없이 이어질 본문만 출력한다.
            """

        static func instructUser(prefix: String) -> String {
            """
            다음 글에 바로 이어질 내용을 짧게 이어써라.

            \(prefix)
            """
        }
    }

    // MARK: - 후처리

    /// 문장 경계 문자(포함)까지 자른다. 없으면 nil.
    /// 단어/구 단위 제안 원칙 — 최대 한 문장에서 멈춘다 (PLAN §9-2).
    private static let sentenceBoundaries: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", "\n",
    ]

    private static func cutAtSentenceBoundary(_ text: String) -> String? {
        guard let index = text.firstIndex(where: { sentenceBoundaries.contains($0) })
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
