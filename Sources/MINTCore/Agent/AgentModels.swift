import Foundation
import MLXLMCommon

/// Agent가 모델과 주고받는 최소 메시지 표현 (PLAN §14 M10).
/// MLX의 Chat.Message를 런타임 경계 밖으로 흘리지 않아 세션·테스트가 모델 구현에
/// 결합되지 않게 한다.
public struct AgentChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// 모델이 요청한 도구 호출. 인자는 MLXLMCommon의 타입 안전 JSON 값으로 보존한다.
public struct AgentToolCall: Sendable, Equatable, Hashable {
    public var name: String
    public var arguments: [String: JSONValue]

    public init(name: String, arguments: [String: JSONValue] = [:]) {
        self.name = name
        self.arguments = arguments
    }
}

/// 한 번의 모델 생성 결과. 네이티브 tool call은 `toolCalls`, 일반 출력과 폴백
/// 프로토콜은 `text`에 들어온다.
public struct AgentModelTurn: Sendable, Equatable {
    public var text: String
    public var toolCalls: [AgentToolCall]

    public init(text: String, toolCalls: [AgentToolCall] = []) {
        self.text = text
        self.toolCalls = toolCalls
    }
}

/// AgentRuntime이 의존하는 생성 경계. 실제 앱은 CompletionEngine, 테스트는 가짜
/// 생성기를 주입한다. 모델은 하나만 상주한다는 규율은 CompletionEngine이 지킨다.
public protocol AgentTurnGenerating: Sendable {
    func generateAgentTurn(
        messages: [AgentChatMessage],
        tools: [ToolSpec],
        parameters: CompletionParameters,
        onChunk: @Sendable @escaping (String) -> Void
    ) async throws -> AgentModelTurn
}

/// MainActor에서 값만 복사해 Agent actor로 넘기는 입력. 원문을 읽을 뿐이며
/// EntryStore나 에디터 객체를 잡지 않는다.
public struct AgentSourceSnapshot: Sendable {
    public var activeEntry: JournalEntry
    public var entries: [JournalEntry]
    public var folders: [JournalFolder]
    public var knowledge: KnowledgeSnapshot?
    public var caretUTF16: Int

    public init(
        activeEntry: JournalEntry,
        entries: [JournalEntry],
        folders: [JournalFolder],
        knowledge: KnowledgeSnapshot?,
        caretUTF16: Int
    ) {
        self.activeEntry = activeEntry
        self.entries = entries
        self.folders = folders
        self.knowledge = knowledge?.entryID == activeEntry.id ? knowledge : nil
        self.caretUTF16 = min(max(0, caretUTF16), (activeEntry.body as NSString).length)
    }
}

/// 한 Agent 요청 동안 고정되는 읽기 전용 문맥. 아웃라인 파싱은 MainActor가 아닌
/// AgentRuntime actor에서 한 번만 수행한다.
public struct AgentContext: Sendable {
    public let activeEntry: JournalEntry
    public let entries: [JournalEntry]
    public let folders: [JournalFolder]
    public let knowledge: KnowledgeSnapshot?
    public let caretUTF16: Int
    /// Agent가 기본적으로 탐색할 수 있는 원고 끝. 커서는 현재 위치 질문에만 쓰며
    /// 전체 작품 조회의 상한이 아니다 (PLAN §14 M10).
    public let documentEndUTF16: Int
    public let outline: DocumentOutline
    public let generationKey: String

    public init(source: AgentSourceSnapshot) {
        activeEntry = source.activeEntry
        entries = source.entries
        folders = source.folders
        knowledge = source.knowledge
        caretUTF16 = source.caretUTF16
        documentEndUTF16 = (source.activeEntry.body as NSString).length
        outline = DocumentOutline.parse(source.activeEntry.body)
        // 원문·스냅샷 내용이 바뀌면 세션 도구 캐시가 자동으로 식는다. 개수만
        // 키에 넣던 이전 구현은 사건 수가 같은 재분석에서 **값이 바뀌어도** 오래된
        // 타임라인을 돌려줬다. Agent가 실제로 읽는 전 필드의 안정 지문을 쓴다.
        generationKey = DocumentOutline.stableHash(
            Self.entryFingerprint(source.activeEntry)
                + "|" + Self.knowledgeFingerprint(source.knowledge)
        )
    }

    /// 위치를 명시한 질의만 해당 위치로 제한한다. 생략하면 작품 전체를 읽는다.
    /// 커서 이후 차단은 고스트 자동완성의 불변식이며 Agent 전체 분석에는 적용하지
    /// 않는다. 범위를 넘는 모델 인자는 원고 끝으로 clamp한다.
    public func boundedOffset(_ requested: Int?) -> Int {
        min(max(0, requested ?? documentEndUTF16), documentEndUTF16)
    }

    private static func entryFingerprint(_ entry: JournalEntry) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry) else {
            return "\(entry.id.uuidString)|\(entry.body)"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func knowledgeFingerprint(_ knowledge: KnowledgeSnapshot?) -> String {
        guard let knowledge else { return "knowledge:nil" }
        var parts: [String] = [
            knowledge.workSummary ?? "",
            knowledge.narrationProfile.displayText
        ]
        parts.append(contentsOf: knowledge.summariesByHash.keys.sorted().map {
            "summary|\($0)|\(knowledge.summariesByHash[$0] ?? "")"
        })
        parts.append(contentsOf: knowledge.events.map { event in
            let deltas = event.deltas.map {
                "\($0.characterID)|\($0.field.rawValue)|\($0.value)"
            }.joined(separator: ",")
            return "event|\(event.sceneHash)|\(event.summary)|\(event.importance)|"
                + "\(event.quote ?? "")|\(deltas)"
        })
        parts.append(contentsOf: knowledge.utterances.map {
            "utterance|\($0.speakerID)|\($0.utf16Start)|\($0.text)|"
                + "\($0.listenerID?.uuidString ?? "")|\($0.politeness?.rawValue ?? "")"
        })
        parts.append(contentsOf: knowledge.dialogues.map {
            "dialogue|\($0.stableKey)|\($0.speakerID?.uuidString ?? "")|"
                + "\($0.speakerLabel)|\($0.utf16Start)|\($0.text)|\($0.attribution.rawValue)"
        })
        parts.append(contentsOf: knowledge.relationDeltas.map {
            "relation|\($0.fromID)|\($0.toID)|\($0.value)|\($0.sceneHash)"
        })
        for hash in knowledge.segmentsByScene.keys.sorted() {
            parts.append(contentsOf: (knowledge.segmentsByScene[hash] ?? []).map {
                "segment|\(hash)|\($0.persistentID)|\($0.localStart)|\($0.localEnd)|"
                    + "\($0.layer.rawValue)|\($0.chrono.rawValue)|\($0.pov ?? "")"
            })
        }
        parts.append(contentsOf: knowledge.plotThreads.map { thread in
            "thread|\(thread.id)|\(thread.title)|\(thread.summary)|\(thread.status.rawValue)|"
                + thread.memberKeys.joined(separator: ",")
        })
        parts.append(contentsOf: knowledge.keyScenes.map {
            "keyscene|\($0.id)|\($0.title)|\($0.summary)|\($0.status.rawValue)|"
                + "\($0.sourceRange?.lowerBound ?? -1)|\($0.sourceRange?.upperBound ?? -1)"
        })
        return parts.joined(separator: "\n")
    }
}

public struct AgentToolResult: Sendable, Equatable {
    /// 다음 모델 턴에 넣는 compact JSON 또는 짧은 평문.
    public var content: String
    /// UI 진행 줄에 보여줄 한 문장.
    public var summary: String

    public init(content: String, summary: String) {
        self.content = content
        self.summary = summary
    }

    public static func error(_ message: String) -> AgentToolResult {
        AgentToolResult(
            content: AgentJSON.encode(.object(["error": .string(message)])),
            summary: message
        )
    }
}

/// 런타임 진행 스트림. 도구 내부 데이터 전체가 아니라 사람이 확인할 수 있는
/// 목적·결과 요지만 UI에 보낸다.
public enum AgentRuntimeEvent: Sendable, Equatable {
    case stepStarted(Int)
    case textChunk(String)
    case toolStarted(name: String, label: String, arguments: [String: JSONValue])
    case toolFinished(name: String, summary: String)
    case repairingToolCall
}

/// 한 답변이 어떤 근거를 조회했는지 사용자가 펼쳐 볼 수 있는 검증 가능한 기록.
/// 모델의 숨은 사고 문자열이 아니라 실제 실행된 도구·입력·결과만 보존한다.
public struct AgentToolTrace: Sendable, Equatable {
    public var step: Int
    public var toolName: String
    public var label: String
    public var arguments: [String: JSONValue]
    public var resultSummary: String

    public init(
        step: Int, toolName: String, label: String,
        arguments: [String: JSONValue], resultSummary: String
    ) {
        self.step = step
        self.toolName = toolName
        self.label = label
        self.arguments = arguments
        self.resultSummary = resultSummary
    }
}

public struct AgentRunResult: Sendable, Equatable {
    public var text: String
    public var steps: Int
    public var toolTrace: [AgentToolTrace]

    public init(text: String, steps: Int, toolTrace: [AgentToolTrace] = []) {
        self.text = text
        self.steps = steps
        self.toolTrace = toolTrace
    }
}

enum AgentJSON {
    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }

    static func signature(name: String, arguments: [String: JSONValue]) -> String {
        "\(name)|\(encode(.object(arguments)))"
    }
}

/// UI가 MLX JSON 타입의 세부 표현을 알지 않고도 도구 입력을 읽기 좋게 표시한다.
enum AgentTraceFormatter {
    static func arguments(
        _ arguments: [String: JSONValue], empty emptyText: String = "없음"
    ) -> String {
        guard !arguments.isEmpty else { return emptyText }
        return arguments.keys.sorted().compactMap { key in
            arguments[key].map { "\(key)=\(AgentJSON.encode($0))" }
        }.joined(separator: " · ")
    }
}

extension JSONValue {
    var agentString: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var agentInt: Int? {
        switch self {
        case let .int(value): value
        case let .double(value): Int(value)
        default: nil
        }
    }

    var agentBool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}
