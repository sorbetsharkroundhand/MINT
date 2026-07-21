import Foundation
import MLXLMCommon

private struct AgentReadableTarget {
    var reference: String
    var title: String
    var range: Range<Int>
}

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
        description: "특정 시점 질의의 UTF-16 상한. 생략하면 작품 전체를 조회합니다.")

    private static let activeDocument = ClosureWritingTool(
        name: "get_active_document",
        description: "현재 문서의 제목·종류·장르·분량·서술 시점·핵심 장면 수를 확인합니다."
    ) { _, context in
        let entry = context.activeEntry
        let narration = context.knowledge?.narrationProfile
        let value: JSONValue = .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "kind": .string(entry.resolvedKind.label),
            "genre": entry.genre.map(JSONValue.string) ?? .null,
            "characters": .array((entry.characters ?? []).map { .string($0.name) }),
            "document_utf16_length": .int(context.documentEndUTF16),
            "caret_utf16": .int(context.caretUTF16),
            "key_scene_count": .int(context.visibleKeyScenes.count),
            "chapter_count": .int(context.chapters.count),
            "narration_mode": narration.map { .string($0.mode.rawValue) } ?? .null,
            "narrator": narration?.narratorName.map(JSONValue.string) ?? .null,
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "‘\(entry.title)’ · 핵심 장면 \(context.visibleKeyScenes.count)개")
    }

    private static let outline = ClosureWritingTool(
        name: "get_outline",
        description: "작품 전체의 장·절 아웃라인과 작가가 관리하는 핵심 장면을 확인합니다."
    ) { _, context in
        let chapters = context.chapters.map { chapter -> JSONValue in
            .object([
                "chapter_ref": .string(chapter.reference),
                "heading": .string(chapter.title),
                "path": .array(chapter.path.map(JSONValue.string)),
                "range": .array([.int(chapter.range.lowerBound), .int(chapter.range.upperBound)]),
            ])
        }
        let scenes = context.visibleKeyScenes.enumerated().map { index, scene -> JSONValue in
            let range: JSONValue = scene.sourceRange.map {
                .array([.int($0.lowerBound), .int($0.upperBound)])
            } ?? .null
            return .object([
                "index": .int(index + 1),
                "scene_ref": .string(scene.id.uuidString),
                "chapter": .array(scene.chapterAnchor.map(JSONValue.string)),
                "title": .string(scene.title),
                "range": range,
                "status": .string(scene.status.rawValue),
                "importance": .int(scene.importance),
                "author_confirmed": .bool(scene.authorConfirmed),
                "stale": .bool(context.knowledge?.staleKeySceneIDs.contains(scene.id) == true),
                "summary": .string(scene.summary),
            ])
        }
        return AgentToolResult(
            content: AgentJSON.encode(.object([
                "chapters": .array(chapters), "key_scenes": .array(scenes),
            ])),
            summary: "장·절 \(chapters.count)개와 핵심 장면 \(scenes.count)개를 확인했어요.")
    }

    private static let readScene = ClosureWritingTool(
        name: "read_scene",
        description: "get_outline의 장·절 또는 핵심 장면 원문을 페이지 단위로 읽습니다.",
        parameters: [
            AgentToolParameter(
                "scene_ref", type: .string,
                description: "chapter_ref, 핵심 장면 UUID·번호·제목",
                required: true),
            AgentToolParameter("offset", type: .integer, description: "장면 범위 안 시작 위치(기본 0)"),
            AgentToolParameter("limit", type: .integer, description: "읽을 UTF-16 길이(기본 1200, 최대 3000)"),
        ]
    ) { arguments, context in
        guard let reference = arguments["scene_ref"]?.agentString else {
            return .error("scene_ref가 필요해요.")
        }
        let target: AgentReadableTarget
        switch context.resolveKeyScene(reference) {
        case .success(let resolved):
            guard let source = resolved.scene.sourceRange else {
                return .error("계획 단계 핵심 장면은 아직 연결된 원문이 없어요.")
            }
            target = AgentReadableTarget(
                reference: resolved.scene.id.uuidString,
                title: resolved.scene.title, range: source)
        case .failure:
            guard let chapter = context.resolveChapter(reference) else {
                return .error("장·절 또는 핵심 장면 '\(reference)'을 찾지 못했어요.")
            }
            target = AgentReadableTarget(
                reference: chapter.reference, title: chapter.title, range: chapter.range)
        }
        let offset = max(0, arguments["offset"]?.agentInt ?? 0)
        let limit = min(3_000, max(1, arguments["limit"]?.agentInt ?? 1_200))
        let lower = min(target.range.upperBound, target.range.lowerBound + offset)
        let upper = min(target.range.upperBound, lower + limit)
        guard upper > lower else { return .error("이 범위에서 더 읽을 원문이 없어요.") }
        let text = context.text(in: lower..<upper)
        let value: JSONValue = .object([
            "scene_ref": .string(target.reference),
            "title": .string(target.title),
            "offset": .int(offset),
            "has_more": .bool(upper < target.range.upperBound),
            "text": .string(text),
        ])
        return AgentToolResult(
            content: AgentJSON.encode(value),
            summary: "\(target.title) · \(text.count)자를 읽었어요.")
    }

    private static let searchText = ClosureWritingTool(
        name: "search_text",
        description: "문서 원문에서 정확한 문자열을 찾아 위치와 짧은 문맥을 반환합니다.",
        parameters: [
            AgentToolParameter(
                "query", type: .string, description: "찾을 문자열", required: true),
            AgentToolParameter(
                "all_documents", type: .boolean,
                description: "true면 다른 문서도 함께 검색합니다. 현재 문서도 작품 전체를 검색합니다."),
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
            let body = entry.body
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
        description: "인물이 참여한 사건을 담화 순서로 확인합니다.",
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
        description: "인물의 대사 예문·말투·참여 대화를 확인합니다.",
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
        description: "사건을 담화순 또는 작품 내 시간순으로 확인합니다.",
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
        description: "작품의 죽은 인물 발화와 확립된 존대 붕괴를 결정적으로 검사합니다.",
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
        let pov: JSONValue = (position?.pov ?? context.knowledge?.narrationProfile.agentPOV)
            .map(JSONValue.string) ?? .null
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
    var visibleKeyScenes: [KeyScene] {
        knowledge?.keyScenes
            ?? KeySceneReconciler.reconcile(activeEntry.keyScenes ?? [], in: activeEntry.body).scenes
    }

    struct AgentChapter {
        var reference: String
        var title: String
        var path: [String]
        var range: Range<Int>
    }

    /// 내부 분석 청크를 그대로 노출하지 않고, 같은 헤딩 경로의 연속 범위를
    /// Agent가 읽을 수 있는 장·절 단위로 접는다. KeyScene이 0개여도 원문 전체에
    /// 도달할 수 있는 결정적 폴백이다.
    var chapters: [AgentChapter] {
        var grouped: [(path: [String], range: Range<Int>)] = []
        for scene in outline.scenes {
            let path = Array(scene.headingPath.prefix(2))
            if let last = grouped.indices.last, grouped[last].path == path {
                grouped[last].range = grouped[last].range.lowerBound..<scene.utf16Range.upperBound
            } else {
                grouped.append((path, scene.utf16Range))
            }
        }
        return grouped.enumerated().map { index, item in
            let parts = item.path.filter { !$0.isEmpty }
            return AgentChapter(
                reference: "chapter:\(index + 1)",
                title: parts.isEmpty ? "문서 전체" : parts.joined(separator: " > "),
                path: item.path, range: item.range)
        }
    }

    func resolveChapter(_ reference: String) -> AgentChapter? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = chapters.first(where: { $0.reference == trimmed }) { return exact }
        // KeyScene이 하나도 없는 레거시 원고에서는 숫자만으로도 장을 읽을 수 있다.
        if visibleKeyScenes.isEmpty, let number = Int(trimmed), chapters.indices.contains(number - 1) {
            return chapters[number - 1]
        }
        let matches = chapters.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        return matches.count == 1 ? matches[0] : nil
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

    struct ResolvedKeyScene {
        var index: Int
        var scene: KeyScene
    }

    enum KeySceneResolution {
        case success(ResolvedKeyScene)
        case failure(String)
    }

    func resolveKeyScene(_ reference: String) -> KeySceneResolution {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed), visibleKeyScenes.indices.contains(number - 1) {
            return .success(.init(index: number - 1, scene: visibleKeyScenes[number - 1]))
        }
        if let id = UUID(uuidString: trimmed),
            let match = visibleKeyScenes.enumerated().first(where: { $0.element.id == id })
        {
            return .success(.init(index: match.offset, scene: match.element))
        }
        let matches = visibleKeyScenes.enumerated().filter {
            $0.element.title.localizedCaseInsensitiveContains(trimmed)
        }
        if matches.count == 1, let match = matches.first {
            return .success(.init(index: match.offset, scene: match.element))
        }
        if matches.count > 1 { return .failure("제목이 같은 핵심 장면이 여러 개예요. UUID를 사용하세요.") }
        return .failure("핵심 장면 '\(reference)'을 찾지 못했어요.")
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
        let normalized = cards.filter { card in
            KoreanName.mayReferToSame(query, card.name)
                || aliases(of: card).contains { KoreanName.mayReferToSame(query, $0) }
        }
        if !normalized.isEmpty { return normalized }
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
