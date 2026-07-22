import Foundation

/// Qwen tool calling 위의 제한된 읽기 전용 루프 (PLAN §14 M10, ADR-1).
/// step·반복 상한, 취소, 도구 오류의 모델 반환을 한곳에서 보장한다.
public actor AgentRuntime {
    public static let defaultMaxSteps = 6

    private let generator: any AgentTurnGenerating
    private let registry: ToolRegistry
    private let maxSteps: Int
    private var resultCache: [String: AgentToolResult] = [:]

    public init(
        generator: any AgentTurnGenerating,
        registry: ToolRegistry = DefaultWritingTools.readOnlyMVP,
        maxSteps: Int = AgentRuntime.defaultMaxSteps
    ) {
        self.generator = generator
        self.registry = registry
        self.maxSteps = max(1, maxSteps)
    }

    public func run(
        request: String,
        history: [AgentChatMessage],
        source: AgentSourceSnapshot,
        parameters: CompletionParameters,
        onEvent: @Sendable @escaping (AgentRuntimeEvent) -> Void
    ) async throws -> AgentRunResult {
        if let answer = AgentEvidencePack.directAnswer(request: request, source: source) {
            return AgentRunResult(text: answer, steps: 0, toolTrace: [])
        }
        let context = AgentContext(source: source)
        let evidencePack = AgentEvidencePack.make(request: request, source: source)
        var messages = [AgentChatMessage(
            role: .system,
            content: Self.systemPrompt + "\n\n[결정적으로 준비된 문서 근거]\n" + evidencePack
        )]
        messages.append(contentsOf: Self.boundedHistory(history))
        messages.append(AgentChatMessage(role: .user, content: request))

        var previousSignature: String?
        var consecutiveRepeats = 0
        var repairedOnce = false
        var completedSteps = 0
        var toolTrace: [AgentToolTrace] = []

        for step in 1 ... maxSteps {
            try Task.checkCancellation()
            completedSteps = step
            onEvent(.stepStarted(step))
            let turn = try await generator.generateAgentTurn(
                messages: messages,
                tools: registry.specs,
                parameters: parameters,
                onChunk: { onEvent(.textChunk($0)) }
            )
            try Task.checkCancellation()

            let fallback = AgentToolCallParser.parse(turn.text)
            let calls = turn.toolCalls.isEmpty ? fallback.calls : turn.toolCalls
            let cleanText = fallback.remainingText
            if calls.isEmpty {
                if Self.looksLikeBrokenToolCall(turn.text) {
                    if !repairedOnce {
                        repairedOnce = true
                        onEvent(.repairingToolCall)
                        messages.append(AgentChatMessage(role: .assistant, content: turn.text))
                        messages.append(
                            AgentChatMessage(
                                role: .user,
                                content: "방금 도구 호출 형식이 깨졌습니다. 제공된 도구 스키마에 맞는 호출을 한 번만 다시 출력하세요."
                            )
                        )
                        continue
                    }
                    // 두 번째 형식 실패를 최종 답변으로 노출하지 않는다. 도구를
                    // 닫은 별도 턴에서 지금까지의 근거만 문장으로 회수한다.
                    messages.append(AgentChatMessage(role: .assistant, content: turn.text))
                    return try await finalize(
                        messages: messages, parameters: parameters,
                        completedSteps: completedSteps, toolTrace: toolTrace,
                        request: request, source: source, onEvent: onEvent
                    )
                }
                let final = cleanText.isEmpty ? turn.text : cleanText
                if let instruction = AgentEvidencePack.verificationInstruction(
                    for: request
                ) {
                    return try await verifyFinal(
                        draft: Self.cleanedFinal(final), instruction: instruction,
                        messages: messages, parameters: parameters,
                        completedSteps: completedSteps, toolTrace: toolTrace,
                        request: request, source: source, onEvent: onEvent
                    )
                }
                return AgentRunResult(
                    text: AgentEvidencePack.correctedAnswer(
                        Self.cleanedFinal(final), request: request, source: source
                    ), steps: completedSteps,
                    toolTrace: toolTrace
                )
            }

            // 다음 턴이 tool 역할을 해석하려면 assistant의 호출도 이력에 남아야 한다.
            let callMarkup = calls.map(AgentToolCallParser.tagged).joined(separator: "\n")
            let assistantContent = cleanText.isEmpty ? callMarkup : cleanText + "\n" + callMarkup
            messages.append(AgentChatMessage(role: .assistant, content: assistantContent))

            var forceFinish = false
            for call in calls {
                try Task.checkCancellation()
                let signature = AgentJSON.signature(name: call.name, arguments: call.arguments)
                if signature == previousSignature {
                    consecutiveRepeats += 1
                } else {
                    previousSignature = signature
                    consecutiveRepeats = 1
                }
                if consecutiveRepeats >= 3 {
                    let result = AgentToolResult.error(
                        "같은 도구와 인자를 세 번 반복해 루프를 중단했어요."
                    )
                    messages.append(AgentChatMessage(role: .tool, content: result.content))
                    toolTrace.append(
                        AgentToolTrace(
                            step: step, toolName: call.name,
                            label: registry.label(for: call.name),
                            arguments: call.arguments, resultSummary: result.summary
                        )
                    )
                    onEvent(.toolFinished(name: call.name, summary: result.summary))
                    forceFinish = true
                    break
                }

                let label = registry.label(for: call.name)
                onEvent(
                    .toolStarted(
                        name: call.name, label: label, arguments: call.arguments
                    )
                )
                let cacheKey = "\(context.generationKey)|\(signature)"
                let result: AgentToolResult
                if let cached = resultCache[cacheKey] {
                    result = AgentToolResult(
                        content: cached.content, summary: cached.summary + " (캐시)"
                    )
                } else {
                    result = await registry.execute(call, context: context)
                    resultCache[cacheKey] = result
                    trimCacheIfNeeded()
                }
                onEvent(.toolFinished(name: call.name, summary: result.summary))
                toolTrace.append(
                    AgentToolTrace(
                        step: step, toolName: call.name, label: label,
                        arguments: call.arguments, resultSummary: result.summary
                    )
                )
                messages.append(AgentChatMessage(role: .tool, content: result.content))
            }

            if forceFinish {
                return try await finalize(
                    messages: messages, parameters: parameters,
                    completedSteps: completedSteps, toolTrace: toolTrace,
                    request: request, source: source, onEvent: onEvent
                )
            }
        }

        return try await finalize(
            messages: messages, parameters: parameters,
            completedSteps: completedSteps, toolTrace: toolTrace,
            request: request, source: source, onEvent: onEvent
        )
    }

    private func finalize(
        messages: [AgentChatMessage],
        parameters: CompletionParameters,
        completedSteps: Int,
        toolTrace: [AgentToolTrace],
        request: String,
        source: AgentSourceSnapshot,
        onEvent: @Sendable @escaping (AgentRuntimeEvent) -> Void
    ) async throws -> AgentRunResult {
        var messages = messages
        messages.append(
            AgentChatMessage(
                role: .user,
                content: "도구 단계 예산이 끝났습니다. 지금까지 확인한 결과만으로 한국어 최종 답변을 작성하세요. 추가 도구 호출은 하지 마세요."
            )
        )
        onEvent(.stepStarted(completedSteps + 1))
        let turn = try await generator.generateAgentTurn(
            messages: messages, tools: [], parameters: parameters,
            onChunk: { onEvent(.textChunk($0)) }
        )
        let text = AgentEvidencePack.correctedAnswer(
            Self.cleanedFinal(turn.text), request: request, source: source
        )
        return AgentRunResult(
            text: text.isEmpty ? "확인한 정보만으로는 답을 확정하기 어려워요." : text,
            steps: completedSteps, toolTrace: toolTrace
        )
    }

    private func verifyFinal(
        draft: String, instruction: String,
        messages: [AgentChatMessage], parameters: CompletionParameters,
        completedSteps: Int, toolTrace: [AgentToolTrace],
        request: String, source: AgentSourceSnapshot,
        onEvent: @Sendable @escaping (AgentRuntimeEvent) -> Void
    ) async throws -> AgentRunResult {
        var messages = messages
        messages.append(AgentChatMessage(role: .assistant, content: draft))
        messages.append(AgentChatMessage(role: .user, content: instruction))
        onEvent(.stepStarted(completedSteps + 1))
        var verificationParameters = parameters
        // 검증 턴은 도구 없이 500자 이내의 정정만 한다. 본 생성의 512토큰을
        // 그대로 열어 두면 드물게 반복 생성으로 수 분까지 늘어나는 꼬리가 생긴다.
        verificationParameters.maxTokens = min(384, parameters.maxTokens)
        let turn = try await generator.generateAgentTurn(
            messages: messages, tools: [], parameters: verificationParameters,
            onChunk: { onEvent(.textChunk($0)) }
        )
        let verified = Self.cleanedFinal(turn.text)
        let selected = verified.isEmpty || Self.looksLikeBrokenToolCall(verified)
            ? draft : verified
        let answer = AgentEvidencePack.correctedAnswer(
            selected, request: request, source: source
        )
        return AgentRunResult(
            text: answer, steps: completedSteps + 1, toolTrace: toolTrace
        )
    }

    private func trimCacheIfNeeded() {
        // 세션 재조회만 가속하는 작은 메모. 원문·지식 키가 달라진 낡은 결과를 오래
        // 쌓지 않는다. 순서는 중요하지 않아 임의 절반을 버려도 정확성에 영향 없다.
        if resultCache.count > 128 {
            for key in resultCache.keys.prefix(64) {
                resultCache[key] = nil
            }
        }
    }

    private static func boundedHistory(_ history: [AgentChatMessage]) -> [AgentChatMessage] {
        history.suffix(12).map { message in
            let content = String(message.content.prefix(2000))
            return AgentChatMessage(role: message.role, content: content)
        }
    }

    private static func looksLikeBrokenToolCall(_ text: String) -> Bool {
        text.contains("<tool_call>") || text.uppercased().contains("TOOL:")
    }

    private static func cleanedFinal(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = result.range(of: "<think>"),
           let end = result.range(of: "</think>", range: start.upperBound ..< result.endIndex) {
            result.removeSubrange(start.lowerBound ..< end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let systemPrompt = """
    당신은 MINT의 읽기 전용 집필 Agent입니다. 현재 작품을 조회하고 근거 있는 조언을 한국어로 제공합니다.

    규칙:
    - 원고 전체를 추측하지 말고 필요한 사실은 제공된 도구로 확인합니다.
    - 아래의 "결정적으로 준비된 문서 근거"는 원문과 규칙 기반 분석이다. 질문에
      답할 근거가 이미 충분하면 도구를 호출하지 말고 바로 답합니다.
    - 도구 결과와 원문에 없는 사실은 단정하지 않습니다. 불확실하면 불확실하다고 밝힙니다.
    - 근거 우선순위는 원문 quote/`read_scene` > 작가 확정 핵심 장면 > 추론 요약입니다. `evidence=추론`인 사건만으로 누가 무엇을 했는지 단정하지 말고 chapter_ref와 chapter_offset으로 원문을 읽습니다.
    - `narrator=null`이나 "이름 미상"은 다른 등록 인물이 화자라는 뜻이 아닙니다. `role=화자` 카드는 이름이 아니라 익명 서술자를 가리키는 구조 역할입니다.
    - 준비된 큰따옴표 대사 인덱스는 원문 순서의 전수 목록입니다. `미상`도 누락된 대사가 아니며, 화자를 임의로 지어내지 않습니다.
    - "화자" 역할 카드가 없으면 인물 도구를 반복하지 말고 타임라인·검색·원문 읽기로 확인합니다.
    - 전체 플롯이나 실제 시간 순서를 묻는 질문은 타임라인 요약만 믿지 말고,
      `read_scene`의 `limit=8000`으로 원문 전체를 한 번에 확인합니다.
    - 행동의 숨은 동기를 묻는 질문은 말 자체만 문자적으로 해석하지 말고, 제안
      전후의 반응과 이후 행동을 함께 읽되 해석임을 밝힙니다.
    - 작품 전체 질문에는 원고 전체를 탐색합니다. 특정 장면 시점의 질문일 때만 before 범위를 지정합니다.
    - 현재 커서는 "여기서"라고 물은 경우의 기준일 뿐, 전체 작품 조회의 상한이 아닙니다.
    - 원문을 수정하거나 수정했다고 말하지 않습니다. 사용자가 편집을 부탁하면 구체적인 제안만 답합니다.
    - 같은 도구를 필요 없이 반복하지 말고, 충분한 근거가 모이면 짧고 직접적으로 답합니다. 사용자가 요구하지 않으면 장황한 항목 나열을 피합니다.
    - 최종 답변은 사용자가 긴 형식을 요구하지 않는 한 5문장·500자 이내로 완결합니다.
    - "직전/직후"는 원문 위치 순서를 대조해 뒤집지 않습니다.
    - 인용은 도구 결과에 실제 quote나 원문이 있을 때만 사용합니다.
    """
}
