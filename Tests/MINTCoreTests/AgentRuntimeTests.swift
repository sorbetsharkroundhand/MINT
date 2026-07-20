import MLXLMCommon
import XCTest

@testable import MINTCore

/// Agent MVP의 결정적 경계 회귀 테스트. 모델·Metal 없이 parser→registry→loop와
/// 커서 이후 차단을 검증한다.
final class AgentRuntimeTests: XCTestCase {
    private func source(caret: Int? = nil) -> AgentSourceSnapshot {
        let body = """
            # 1장
            서연은 병원 문을 나섰다.
            # 2장
            민준이 범인이었다는 사실이 드러났다.
            """
        let entry = JournalEntry(
            title: "비밀", body: body, kind: .novel,
            characters: [CharacterCard(name: "서연")])
        return AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: caret ?? (body as NSString).length)
    }

    func testHermes와_줄형식_도구호출을_복구() {
        let tagged = AgentToolCallParser.parse(
            #"<tool_call>{"name":"search_text","arguments":{"query":"병원",}}</tool_call>"#)
        XCTAssertEqual(tagged.calls.count, 1)
        XCTAssertEqual(tagged.calls[0].name, "search_text")
        XCTAssertEqual(tagged.calls[0].arguments["query"], .string("병원"))
        XCTAssertTrue(tagged.remainingText.isEmpty)

        let line = AgentToolCallParser.parse(#"TOOL: get_outline {}"#)
        XCTAssertEqual(line.calls, [AgentToolCall(name: "get_outline")])
    }

    func testRegistry는_12개_읽기전용_도구와_엄격한_인자를_제공() async {
        let registry = DefaultWritingTools.readOnlyMVP
        XCTAssertEqual(registry.names.count, 12)
        XCTAssertTrue(registry.names.contains("get_character_state"))
        XCTAssertTrue(registry.names.contains("check_consistency"))

        let context = AgentContext(source: source())
        let invalid = await registry.execute(
            AgentToolCall(
                name: "get_active_document", arguments: ["unexpected": .bool(true)]),
            context: context)
        XCTAssertTrue(invalid.content.contains("error"))
        XCTAssertTrue(invalid.summary.contains("허용되지 않은"))
    }

    func test원문_도구는_현재_커서_이후_씬을_노출하지_않음() async {
        let full = source()
        let firstEnd = DocumentOutline.parse(full.activeEntry.body).scenes[0].utf16Range.upperBound
        let context = AgentContext(source: source(caret: firstEnd))
        let registry = DefaultWritingTools.readOnlyMVP

        let outline = await registry.execute(
            AgentToolCall(name: "get_outline"), context: context)
        XCTAssertTrue(outline.content.contains("1장"))
        XCTAssertFalse(outline.content.contains("2장"))

        let future = await registry.execute(
            AgentToolCall(name: "read_scene", arguments: ["scene_ref": .string("2")]),
            context: context)
        XCTAssertTrue(future.content.contains("error"))
        XCTAssertFalse(future.content.contains("범인"))
    }

    func test작성중_씬의_전체요약은_커서앞에_노출하지_않음() async {
        let body = "# 1장\n서연은 문을 열었다. 뒤에서 민준이 죽는다."
        let character = CharacterCard(name: "서연")
        let entry = JournalEntry(
            title: "경계", body: body, kind: .novel, characters: [character])
        let outline = DocumentOutline.parse(body)
        let secretSummary = "민준이 뒤에서 죽는 장면"
        let knowledge = KnowledgeSnapshot(
            entryID: entry.id, outline: outline,
            summariesByHash: [outline.scenes[0].contentHash: secretSummary],
            characters: [character])
        let caret = ("# 1장\n서연은 문을 열었다." as NSString).length
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [],
            knowledge: knowledge, caretUTF16: caret)

        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(name: "get_outline"), context: AgentContext(source: source))
        XCTAssertFalse(result.content.contains(secretSummary))
    }

    func testRuntime이_도구결과를_받아_다음턴에서_답변() async throws {
        let generator = FakeGenerator(turns: [
            AgentModelTurn(
                text: "",
                toolCalls: [AgentToolCall(name: "get_active_document")]),
            AgentModelTurn(text: "현재 문서는 ‘비밀’이고 소설입니다."),
        ])
        let runtime = AgentRuntime(generator: generator, maxSteps: 3)
        let result = try await runtime.run(
            request: "무슨 문서야?", history: [], source: source(),
            parameters: CompletionParameters(maxTokens: 128), onEvent: { _ in })

        XCTAssertEqual(result.text, "현재 문서는 ‘비밀’이고 소설입니다.")
        let callCount = await generator.callCount
        let lastMessages = await generator.lastMessages
        XCTAssertEqual(callCount, 2)
        XCTAssertTrue(lastMessages.contains {
            $0.role == .tool && $0.content.contains("비밀")
        })
    }
}

private actor FakeGenerator: AgentTurnGenerating {
    private var turns: [AgentModelTurn]
    private(set) var callCount = 0
    private(set) var lastMessages: [AgentChatMessage] = []

    init(turns: [AgentModelTurn]) {
        self.turns = turns
    }

    func generateAgentTurn(
        messages: [AgentChatMessage], tools: [ToolSpec],
        parameters: CompletionParameters,
        onChunk: @Sendable @escaping (String) -> Void
    ) async throws -> AgentModelTurn {
        callCount += 1
        lastMessages = messages
        guard !turns.isEmpty else { return AgentModelTurn(text: "끝") }
        let turn = turns.removeFirst()
        if !turn.text.isEmpty { onChunk(turn.text) }
        return turn
    }
}
