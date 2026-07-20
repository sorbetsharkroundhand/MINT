import Foundation
import MLXLMCommon

public enum AgentToolValueType: String, Sendable {
    case string
    case integer
    case boolean
}

public struct AgentToolParameter: Sendable {
    public var name: String
    public var type: AgentToolValueType
    public var description: String
    public var required: Bool
    public var allowedValues: [String]

    public init(
        _ name: String,
        type: AgentToolValueType,
        description: String,
        required: Bool = false,
        allowedValues: [String] = []
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.allowedValues = allowedValues
    }

    var schema: [String: any Sendable] {
        var result: [String: any Sendable] = [
            "type": type.rawValue,
            "description": description,
        ]
        if !allowedValues.isEmpty { result["enum"] = allowedValues }
        return result
    }
}

/// 모든 집필 도구의 공통 계약. MVP 도구는 sideEffect=false이며 EntryStore나
/// 에디터를 잡지 않고 AgentContext 값 복사본만 읽는다 (PLAN §14 M10, ADR-2).
public protocol WritingTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [AgentToolParameter] { get }
    var sideEffect: Bool { get }
    func run(arguments: [String: JSONValue], context: AgentContext) async throws
        -> AgentToolResult
}

public struct ClosureWritingTool: WritingTool {
    public let name: String
    public let description: String
    public let parameters: [AgentToolParameter]
    public let sideEffect: Bool
    private let handler:
        @Sendable ([String: JSONValue], AgentContext) async throws -> AgentToolResult

    public init(
        name: String,
        description: String,
        parameters: [AgentToolParameter] = [],
        sideEffect: Bool = false,
        handler: @Sendable @escaping
            ([String: JSONValue], AgentContext) async throws -> AgentToolResult
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.sideEffect = sideEffect
        self.handler = handler
    }

    public func run(arguments: [String: JSONValue], context: AgentContext) async throws
        -> AgentToolResult
    {
        try await handler(arguments, context)
    }
}

public struct AnyWritingTool: WritingTool {
    public let name: String
    public let description: String
    public let parameters: [AgentToolParameter]
    public let sideEffect: Bool
    private let handler:
        @Sendable ([String: JSONValue], AgentContext) async throws -> AgentToolResult

    public init(_ tool: some WritingTool) {
        name = tool.name
        description = tool.description
        parameters = tool.parameters
        sideEffect = tool.sideEffect
        handler = tool.run
    }

    public func run(arguments: [String: JSONValue], context: AgentContext) async throws
        -> AgentToolResult
    {
        try await handler(arguments, context)
    }
}

public struct ToolRegistry: Sendable {
    private let toolsByName: [String: AnyWritingTool]

    public init(tools: [AnyWritingTool]) {
        toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    public var names: [String] { toolsByName.keys.sorted() }

    public var specs: [ToolSpec] {
        toolsByName.values.sorted { $0.name < $1.name }.map { tool in
            let properties = Dictionary(
                uniqueKeysWithValues: tool.parameters.map { ($0.name, $0.schema) })
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": tool.parameters.filter(\.required).map(\.name),
                        "additionalProperties": false,
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
            ] as ToolSpec
        }
    }

    public func label(for name: String) -> String {
        toolsByName[name]?.description ?? name
    }

    public func execute(_ call: AgentToolCall, context: AgentContext) async -> AgentToolResult {
        guard let tool = toolsByName[call.name] else {
            return .error("알 수 없는 도구예요: \(call.name)")
        }
        if tool.sideEffect {
            return .error("읽기 전용 Agent에서는 원문을 바꾸는 도구를 실행할 수 없어요.")
        }
        if let error = validate(call.arguments, for: tool) { return .error(error) }
        do {
            return try await tool.run(arguments: call.arguments, context: context)
        } catch is CancellationError {
            return .error("요청이 취소됐어요.")
        } catch {
            return .error("\(call.name) 실행 실패: \(error.localizedDescription)")
        }
    }

    private func validate(
        _ arguments: [String: JSONValue], for tool: AnyWritingTool
    ) -> String? {
        let definitions = Dictionary(
            uniqueKeysWithValues: tool.parameters.map { ($0.name, $0) })
        for parameter in tool.parameters where parameter.required {
            guard let value = arguments[parameter.name], value != .null else {
                return "\(tool.name): 필수 인자 '\(parameter.name)'이(가) 없어요."
            }
        }
        for (name, value) in arguments {
            guard let definition = definitions[name] else {
                return "\(tool.name): 허용되지 않은 인자 '\(name)'이에요."
            }
            let valid: Bool
            switch (definition.type, value) {
            case (.string, .string), (.integer, .int), (.boolean, .bool): valid = true
            default: valid = false
            }
            guard valid else {
                return "\(tool.name): '\(name)' 인자 형식이 \(definition.type.rawValue)이(가) 아니에요."
            }
            if !definition.allowedValues.isEmpty,
                let string = value.agentString,
                !definition.allowedValues.contains(string)
            {
                return "\(tool.name): '\(name)' 값은 \(definition.allowedValues.joined(separator: ", ")) 중 하나여야 해요."
            }
        }
        return nil
    }
}

// MARK: - MVP 조회 도구 12종

public enum DefaultWritingTools {
    public static let readOnlyMVP: ToolRegistry = ToolRegistry(tools: [
        AnyWritingTool(activeDocument),
        AnyWritingTool(outline),
        AnyWritingTool(readScene),
        AnyWritingTool(searchText),
        AnyWritingTool(findCharacter),
        AnyWritingTool(characterState),
        AnyWritingTool(characterEvents),
        AnyWritingTool(characterDialogues),
        AnyWritingTool(relation),
        AnyWritingTool(timeline),
        AnyWritingTool(consistency),
        AnyWritingTool(contextAtCursor),
    ])

    private static let beforeParameter = AgentToolParameter(
        "before", type: .integer,
        description: "조회 상한 UTF-16 위치. 생략하면 현재 커서이며 커서 이후 값은 자동 차단됩니다.")

    private static let activeDocument = ClosureWritingTool(
        name: "get_active_document",
        description: "현재 문서의 제목·종류·장르·분량·씬 수를 확인합니다."
    ) { _, context in
        let entry = context.activeEntry
        let value: JSONValue = .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "kind": .string(entry.resolvedKind.label),
            "genre": entry.genre.map(JSONValue.string) ?? .null,
            "characters": .array((entry.characters ?? []).map { .string($0.name) }),
            "visible_utf16_length": .int(context.caretUTF16),
            "scene_count": .int(context.visibleScenes.count),
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "‘\(entry.title)’ · 씬 \(context.visibleScenes.count)개")
    }

    private static let outline = ClosureWritingTool(
        name: "get_outline",
        description: "현재 커서까지의 장·절·씬 아웃라인과 준비된 요약을 확인합니다."
    ) { _, context in
        let scenes = context.visibleScenes.enumerated().map { index, scene -> JSONValue in
            let clipped = context.visibleRange(of: scene)
            // 현재 작성 중인 씬의 요약은 커서 뒤 원문까지 읽어 만든 파생물일 수
            // 있다. 씬이 완전히 끝난 경우에만 Agent에 공개한다.
            let summary: JSONValue = scene.utf16Range.upperBound <= context.caretUTF16
                ? context.knowledge?.summariesByHash[scene.contentHash]
                    .map(JSONValue.string) ?? .null
                : .null
            return .object([
                "index": .int(index + 1),
                "scene_ref": .string(scene.contentHash),
                "heading": .string(context.heading(of: scene)),
                "range": .array([.int(clipped.lowerBound), .int(clipped.upperBound)]),
                "summary": summary,
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object(["scenes": .array(scenes)])),
            summary: "커서 이전 씬 \(scenes.count)개를 확인했어요.")
    }

    private static let readScene = ClosureWritingTool(
        name: "read_scene",
        description: "씬 번호·해시·헤딩으로 현재 커서 이전 원문 한 씬을 읽습니다.",
        parameters: [
            AgentToolParameter(
                "scene_ref", type: .string,
                description: "get_outline의 1부터 시작하는 index, scene_ref 해시, 또는 헤딩",
                required: true)
        ]
    ) { arguments, context in
        guard let reference = arguments["scene_ref"]?.agentString else {
            return .error("scene_ref가 필요해요.")
        }
        switch context.resolveScene(reference) {
        case .failure(let message): return .error(message)
        case .success(let resolved):
            let text = context.text(in: context.visibleRange(of: resolved.scene))
            let value: JSONValue = .object([
                "index": .int(resolved.index + 1),
                "scene_ref": .string(resolved.scene.contentHash),
                "heading": .string(context.heading(of: resolved.scene)),
                "text": .string(text),
            ])
            return AgentToolResult(
                content: AgentJSON.encode(value),
                summary: "\(context.heading(of: resolved.scene)) · \(text.count)자를 읽었어요.")
        }
    }

    private static let searchText = ClosureWritingTool(
        name: "search_text",
        description: "문서 원문에서 정확한 문자열을 찾아 위치와 짧은 문맥을 반환합니다.",
        parameters: [
            AgentToolParameter(
                "query", type: .string, description: "찾을 문자열", required: true),
            AgentToolParameter(
                "all_documents", type: .boolean,
                description: "true면 다른 문서도 함께 검색합니다. 현재 문서는 커서 이후를 제외합니다."),
            AgentToolParameter(
                "limit", type: .integer, description: "결과 상한(기본 12, 최대 30)"),
        ]
    ) { arguments, context in
        guard let query = arguments["query"]?.agentString?
            .trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty
        else { return .error("비어 있지 않은 query가 필요해요.") }
        let limit = min(30, max(1, arguments["limit"]?.agentInt ?? 12))
        let targets = arguments["all_documents"]?.agentBool == true
            ? context.entries : [context.activeEntry]
        var matches: [JSONValue] = []
        for entry in targets {
            if matches.count >= limit { break }
            let body = entry.id == context.activeEntry.id
                ? context.text(in: 0..<context.caretUTF16) : entry.body
            matches.append(contentsOf: context.matches(
                query: query, in: body, entry: entry, remaining: limit - matches.count))
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object([
                "query": .string(query), "matches": .array(matches),
            ])),
            summary: "‘\(query)’ 일치 \(matches.count)건을 찾았어요.")
    }

    private static let findCharacter = ClosureWritingTool(
        name: "find_character",
        description: "이름이나 별칭으로 등록 인물 카드와 안정 식별자를 찾습니다.",
        parameters: [
            AgentToolParameter(
                "character_ref", type: .string, description: "인물 이름·별칭·UUID",
                required: true)
        ]
    ) { arguments, context in
        guard let reference = arguments["character_ref"]?.agentString else {
            return .error("character_ref가 필요해요.")
        }
        let matches = context.characterMatches(reference)
        let values = matches.map { card -> JSONValue in
            .object([
                "id": .string(card.id.uuidString),
                "name": .string(card.name),
                "aliases": .array(context.aliases(of: card).map(JSONValue.string)),
                "note": .string(card.note),
                "auto_registered": .bool(card.autoRegistered == true),
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object(["characters": .array(values)])),
            summary: matches.isEmpty
                ? "‘\(reference)’에 해당하는 등록 인물이 없어요."
                : "인물 \(matches.map(\.name).joined(separator: ", "))을 찾았어요.")
    }

    private static let characterState = ClosureWritingTool(
        name: "get_character_state",
        description: "특정 시점의 인물 위치·감정·관계·목표·생사 상태를 확인합니다.",
        parameters: [
            AgentToolParameter(
                "character_ref", type: .string, description: "인물 이름·별칭·UUID",
                required: true),
            beforeParameter,
        ]
    ) { arguments, context in
        guard let resolved = context.uniqueCharacter(arguments["character_ref"]?.agentString)
        else { return .error(context.characterResolutionError(arguments["character_ref"]?.agentString)) }
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let state = knowledge.stateAt(of: resolved.id, before: before)
        var object: [String: JSONValue] = [
            "character": .string(resolved.name), "before": .int(before),
        ]
        for field in StateDelta.Field.allCases {
            object[field.rawValue] = state[field].map(JSONValue.string) ?? .null
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object(object)),
            summary: state.isEmpty ? "\(resolved.name)의 확정 상태가 아직 없어요."
                : "\(resolved.name)의 상태 \(state.count)항목을 확인했어요.")
    }

    private static let characterEvents = ClosureWritingTool(
        name: "get_character_events",
        description: "인물이 참여한 사건을 현재 커서 이전 담화 순서로 확인합니다.",
        parameters: [
            AgentToolParameter(
                "character_ref", type: .string, description: "인물 이름·별칭·UUID",
                required: true),
            beforeParameter,
        ]
    ) { arguments, context in
        guard let character = context.uniqueCharacter(arguments["character_ref"]?.agentString)
        else { return .error(context.characterResolutionError(arguments["character_ref"]?.agentString)) }
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let events = knowledge.events(before: before).filter { $0.participants.contains(character.id) }
        let values = events.map { event -> JSONValue in
            .object([
                "summary": .string(event.summary),
                "importance": .int(event.importance),
                "scene_ref": .string(event.sceneHash),
                "heading": .string(context.heading(forHash: event.sceneHash)),
                "quote": event.quote.map(JSONValue.string) ?? .null,
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object([
                "character": .string(character.name), "events": .array(values),
            ])),
            summary: "\(character.name)의 사건 \(events.count)개를 확인했어요.")
    }

    private static let characterDialogues = ClosureWritingTool(
        name: "get_character_dialogues",
        description: "인물의 커서 이전 대사 예문·말투·참여 대화를 확인합니다.",
        parameters: [
            AgentToolParameter(
                "character_ref", type: .string, description: "인물 이름·별칭·UUID",
                required: true),
            beforeParameter,
        ]
    ) { arguments, context in
        guard let character = context.uniqueCharacter(arguments["character_ref"]?.agentString)
        else { return .error(context.characterResolutionError(arguments["character_ref"]?.agentString)) }
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let utterances = knowledge.utterances.filter {
            $0.speakerID == character.id && $0.utf16Start < before
        }.suffix(12)
        let profile = knowledge.speechProfile(of: character.id, before: before, maxExamples: 4)
        let conversations = knowledge.conversations(involving: character.id)
            // 주제·어조는 대화 전체에서 보완되므로 끝까지 커서 이전인 대화만.
            .filter { $0.utf16End <= before }.suffix(8)
        let defaultPoliteness: JSONValue = (profile?.defaultPoliteness?.rawValue)
            .map(JSONValue.string) ?? .null
        let utteranceValues: [JSONValue] = utterances.map { utterance in
            let politeness: JSONValue = (utterance.politeness?.rawValue)
                .map(JSONValue.string) ?? .null
            return .object([
                "text": .string(utterance.text),
                "position": .int(utterance.utf16Start),
                "politeness": politeness,
            ])
        }
        let conversationValues: [JSONValue] = conversations.map { conversation in
            .object([
                "first_line": .string(conversation.firstLine),
                "position": .int(conversation.utf16Start),
                "topic": conversation.topic.map(JSONValue.string) ?? .null,
                "tone": conversation.tone.map(JSONValue.string) ?? .null,
            ])
        }
        let value: JSONValue = .object([
            "character": .string(character.name),
            "default_politeness": defaultPoliteness,
            "utterances": .array(utteranceValues),
            "conversations": .array(conversationValues),
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "\(character.name)의 최근 대사 \(utterances.count)개를 확인했어요.")
    }

    private static let relation = ClosureWritingTool(
        name: "get_relation",
        description: "두 인물 사이의 방향 있는 관계 변화와 존대 사용을 확인합니다.",
        parameters: [
            AgentToolParameter(
                "from_character", type: .string, description: "관계를 바라보는 인물",
                required: true),
            AgentToolParameter(
                "to_character", type: .string, description: "관계 대상 인물",
                required: true),
            beforeParameter,
        ]
    ) { arguments, context in
        guard let from = context.uniqueCharacter(arguments["from_character"]?.agentString)
        else { return .error(context.characterResolutionError(arguments["from_character"]?.agentString)) }
        guard let to = context.uniqueCharacter(arguments["to_character"]?.agentString)
        else { return .error(context.characterResolutionError(arguments["to_character"]?.agentString)) }
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let history = knowledge.relationHistory(from: from.id, to: to.id).filter {
            context.sceneEnd(forHash: $0.sceneHash) <= before
        }
        let current = knowledge.relation(from: from.id, to: to.id, before: before)
        let honorific = knowledge.honorific(from: from.id, to: to.id, before: before)
        let currentValue: JSONValue = current.map { .string($0.value) } ?? .null
        let honorificValue: JSONValue = honorific.map { .string($0.rawValue) } ?? .null
        let historyValues: [JSONValue] = history.map { delta in
            .object([
                "value": .string(delta.value),
                "scene_ref": .string(delta.sceneHash),
                "heading": .string(context.heading(forHash: delta.sceneHash)),
                "quote": delta.quote.map(JSONValue.string) ?? .null,
            ])
        }
        let value: JSONValue = .object([
            "from": .string(from.name), "to": .string(to.name),
            "current": currentValue,
            "honorific": honorificValue,
            "history": .array(historyValues),
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "\(from.name) → \(to.name) 관계 변화 \(history.count)건을 확인했어요.")
    }

    private static let timeline = ClosureWritingTool(
        name: "get_timeline",
        description: "커서 이전 사건을 담화순 또는 작품 내 시간순으로 확인합니다.",
        parameters: [
            AgentToolParameter(
                "order", type: .string, description: "discourse 또는 chronological",
                allowedValues: ["discourse", "chronological"]),
            beforeParameter,
        ]
    ) { arguments, context in
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let order = arguments["order"]?.agentString ?? "discourse"
        let visibleEvents = knowledge.events(before: before)
        let values: [JSONValue]
        if order == "chronological" {
            let visibleKeys = Set(visibleEvents.map(\.stableKey))
            values = knowledge.eventChronoOrder.compactMap { key in
                guard let canonical = knowledge.canonicalEvent(for: key),
                    canonical.perspectives.contains(where: { visibleKeys.contains($0.eventKey) })
                else { return nil }
                return .object([
                    "event_key": .string(canonical.canonicalKey),
                    "summary": .string(canonical.summary),
                    "scene_ref": .string(canonical.sceneHash),
                    "heading": .string(context.heading(forHash: canonical.sceneHash)),
                ])
            }
        } else {
            values = visibleEvents.map { event in
                .object([
                    "event_key": .string(event.stableKey),
                    "summary": .string(event.summary),
                    "scene_ref": .string(event.sceneHash),
                    "heading": .string(context.heading(forHash: event.sceneHash)),
                ])
            }
        }
        let conflicts = knowledge.chronoConflicts.map { edge in
            JSONValue.object([
                "a": .string(edge.aKey), "b": .string(edge.bKey),
                "relation": .string(edge.relation.rawValue),
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object([
                "order": .string(order), "events": .array(values),
                "chrono_conflicts": .array(conflicts),
            ])),
            summary: "\(order == "chronological" ? "시간순" : "담화순") 사건 \(values.count)개를 확인했어요.")
    }

    private static let consistency = ClosureWritingTool(
        name: "check_consistency",
        description: "커서 이전의 죽은 인물 발화와 확립된 존대 붕괴를 결정적으로 검사합니다.",
        parameters: [beforeParameter]
    ) { arguments, context in
        guard let knowledge = context.knowledge else { return .error("준비된 Story Intelligence가 없어요.") }
        let before = context.boundedOffset(arguments["before"]?.agentInt)
        let warnings = ConsistencyChecker.check(
            snapshot: knowledge, characters: context.activeEntry.characters ?? [])
            .filter { $0.utf16Position < before }
        let values = warnings.map { warning in
            JSONValue.object([
                "kind": .string(warning.kind.rawValue),
                "position": .int(warning.utf16Position),
                "message": .string(warning.message),
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object(["warnings": .array(values)])),
            summary: warnings.isEmpty ? "결정적 일관성 경고가 없어요."
                : "일관성 경고 \(warnings.count)건을 찾았어요.")
    }

    private static let contextAtCursor = ClosureWritingTool(
        name: "get_context_at_cursor",
        description: "현재 서사 좌표와 자동완성이 실제로 참고할 지식 항목을 확인합니다."
    ) { _, context in
        let cursor = context.caretUTF16
        let start = max(0, cursor - CompletionSettings.defaultNovelContextCharacters)
        let prefix = context.text(in: start..<cursor)
        let document = DocumentContext(
            title: context.activeEntry.title,
            kind: context.activeEntry.resolvedKind,
            genre: context.activeEntry.genre,
            characters: context.activeEntry.characters ?? [])
        let (_, report) = ContextAssembler.assembleWithReport(
            prefix: prefix, document: document, knowledge: context.knowledge,
            prefixStartUTF16: start, style: .continuation)
        let position = context.knowledge?.position(at: cursor)
        let sceneIndex = context.outline.sceneIndex(at: cursor)
        let scene = sceneIndex.map { context.outline.scenes[$0] }
        let pov: JSONValue = (position?.pov).map(JSONValue.string) ?? .null
        let value: JSONValue = .object([
            "cursor": .int(cursor),
            "scene_ref": scene.map { .string($0.contentHash) } ?? .null,
            "heading": scene.map { .string(context.heading(of: $0)) } ?? .null,
            "flow": position.map { .string($0.flowID) } ?? .null,
            "layer": position.map { .string($0.layer.rawValue) } ?? .null,
            "pov": pov,
            "context_items": .array(report.items.map { item in
                .object([
                    "kind": .string(item.kind.rawValue),
                    "text": .string(item.text),
                    "pinned": .bool(item.pinned),
                ])
            }),
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "현재 위치와 컨텍스트 \(report.items.count)항목을 확인했어요.")
    }
}

// MARK: - 결정적 조회 어댑터

private extension AgentContext {
    var visibleScenes: [DocumentOutline.Scene] {
        // 경계와 정확히 같은 커서는 아직 그 씬 원문 앞이다. `<=`면 빈 범위의
        // 미래 씬 헤딩·요약이 노출되므로 엄격히 `<`를 쓴다.
        outline.scenes.filter { $0.utf16Range.lowerBound < caretUTF16 }
    }

    func visibleRange(of scene: DocumentOutline.Scene) -> Range<Int> {
        scene.utf16Range.lowerBound..<min(scene.utf16Range.upperBound, caretUTF16)
    }

    func text(in range: Range<Int>) -> String {
        let body = activeEntry.body as NSString
        let lower = min(max(0, range.lowerBound), body.length)
        let upper = min(max(lower, range.upperBound), body.length)
        return body.substring(with: NSRange(location: lower, length: upper - lower))
    }

    func heading(of scene: DocumentOutline.Scene) -> String {
        let path = scene.headingPath.filter { !$0.isEmpty }.joined(separator: " > ")
        let base = path.isEmpty ? "문서 서두" : path
        if scene.segmentIndex > 0 { return "\(base) (분할 \(scene.segmentIndex + 1))" }
        return base
    }

    func heading(forHash hash: String) -> String {
        outline.scenes.first(where: { $0.contentHash == hash }).map(heading(of:)) ?? "알 수 없는 씬"
    }

    func sceneEnd(forHash hash: String) -> Int {
        outline.scenes.first(where: { $0.contentHash == hash })?.utf16Range.upperBound ?? .max
    }

    struct ResolvedScene {
        var index: Int
        var scene: DocumentOutline.Scene
    }

    enum SceneResolution {
        case success(ResolvedScene)
        case failure(String)
    }

    func resolveScene(_ reference: String) -> SceneResolution {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed), visibleScenes.indices.contains(number - 1) {
            return .success(ResolvedScene(index: number - 1, scene: visibleScenes[number - 1]))
        }
        if let match = visibleScenes.enumerated().first(where: { $0.element.contentHash == trimmed }) {
            return .success(ResolvedScene(index: match.offset, scene: match.element))
        }
        let matches = visibleScenes.enumerated().filter {
            heading(of: $0.element).localizedCaseInsensitiveContains(trimmed)
        }
        if matches.count == 1, let match = matches.first {
            return .success(ResolvedScene(index: match.offset, scene: match.element))
        }
        if matches.count > 1 {
            return .failure("헤딩이 여러 씬과 일치해요. get_outline의 index나 scene_ref를 사용하세요.")
        }
        return .failure("현재 커서 이전에서 씬 '\(reference)'을 찾지 못했어요.")
    }

    func aliases(of card: CharacterCard) -> [String] {
        card.aliases.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    func characterMatches(_ reference: String) -> [CharacterCard] {
        let query = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let cards = activeEntry.characters ?? []
        if let id = UUID(uuidString: query), let card = cards.first(where: { $0.id == id }) {
            return [card]
        }
        let exact = cards.filter { card in
            card.name.compare(query, options: .caseInsensitive) == .orderedSame
                || aliases(of: card).contains {
                    $0.compare(query, options: .caseInsensitive) == .orderedSame
                }
        }
        if !exact.isEmpty { return exact }
        return cards.filter { card in
            card.name.localizedCaseInsensitiveContains(query)
                || aliases(of: card).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func uniqueCharacter(_ reference: String?) -> CharacterCard? {
        guard let reference else { return nil }
        let matches = characterMatches(reference)
        return matches.count == 1 ? matches[0] : nil
    }

    func characterResolutionError(_ reference: String?) -> String {
        guard let reference, !reference.isEmpty else { return "인물 참조가 필요해요." }
        let matches = characterMatches(reference)
        if matches.isEmpty { return "등록 인물 '\(reference)'을 찾지 못했어요." }
        return "'\(reference)'이(가) 여러 인물과 일치해요: \(matches.map(\.name).joined(separator: ", "))"
    }

    func matches(
        query: String, in body: String, entry: JournalEntry, remaining: Int
    ) -> [JSONValue] {
        guard remaining > 0 else { return [] }
        let source = body as NSString
        var searchRange = NSRange(location: 0, length: source.length)
        var result: [JSONValue] = []
        while searchRange.length > 0, result.count < remaining {
            let found = source.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            let snippetStart = max(0, found.location - 45)
            let snippetEnd = min(source.length, NSMaxRange(found) + 65)
            let snippet = source.substring(
                with: NSRange(location: snippetStart, length: snippetEnd - snippetStart))
                .replacingOccurrences(of: "\n", with: " ")
            result.append(.object([
                "document_id": .string(entry.id.uuidString),
                "document_title": .string(entry.title),
                "position": .int(found.location),
                "snippet": .string(snippet),
            ]))
            let next = NSMaxRange(found)
            if next >= source.length { break }
            searchRange = NSRange(location: next, length: source.length - next)
        }
        return result
    }
}
