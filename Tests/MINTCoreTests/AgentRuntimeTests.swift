@testable import MINTCore
import MLXLMCommon
import XCTest

/// Agent MVP의 결정적 경계 회귀 테스트. 모델·Metal 없이 parser→registry→loop와
/// Agent의 전체 원고 탐색과 명시적 시점 범위를 검증한다.
final class AgentRuntimeTests: XCTestCase {
    private func source(caret: Int? = nil) -> AgentSourceSnapshot {
        let body = """
        # 1장
        서연은 병원 문을 나섰다.
        # 2장
        민준이 범인이었다는 사실이 드러났다.
        """
        let outline = DocumentOutline.parse(body)
        let keyScenes = [
            KeyScene(
                title: "병원을 나서다", summary: "서연이 병원을 나선다",
                sourceRange: outline.scenes[0].utf16Range, status: .confirmed,
                authorConfirmed: true
            ),
            KeyScene(
                title: "범인의 정체", summary: "민준의 정체가 드러난다",
                sourceRange: outline.scenes[1].utf16Range, status: .drafted
            )
        ]
        let entry = JournalEntry(
            title: "비밀", body: body, kind: .novel,
            characters: [CharacterCard(name: "서연")], keyScenes: keyScenes
        )
        return AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: caret ?? (body as NSString).length
        )
    }

    func testHermes와_줄형식_도구호출을_복구() {
        let tagged = AgentToolCallParser.parse(
            #"<tool_call>{"name":"search_text","arguments":{"query":"병원",}}</tool_call>"#
        )
        XCTAssertEqual(tagged.calls.count, 1)
        XCTAssertEqual(tagged.calls[0].name, "search_text")
        XCTAssertEqual(tagged.calls[0].arguments["query"], .string("병원"))
        XCTAssertTrue(tagged.remainingText.isEmpty)

        let line = AgentToolCallParser.parse(#"TOOL: get_outline {}"#)
        XCTAssertEqual(line.calls, [AgentToolCall(name: "get_outline")])
    }

    func testRegistry는_13개_읽기전용_도구와_엄격한_인자를_제공() async {
        let registry = DefaultWritingTools.readOnlyMVP
        XCTAssertEqual(registry.names.count, 13)
        XCTAssertTrue(registry.names.contains("get_character_state"))
        XCTAssertTrue(registry.names.contains("get_dialogues"))
        XCTAssertTrue(registry.names.contains("check_consistency"))

        let context = AgentContext(source: source())
        let invalid = await registry.execute(
            AgentToolCall(
                name: "get_active_document", arguments: ["unexpected": .bool(true)]
            ),
            context: context
        )
        XCTAssertTrue(invalid.content.contains("error"))
        XCTAssertTrue(invalid.summary.contains("허용되지 않은"))
    }

    func testAgent는_커서이후를_포함한_작품전체를_탐색() async {
        let full = source()
        let firstEnd = DocumentOutline.parse(full.activeEntry.body).scenes[0].utf16Range.upperBound
        let context = AgentContext(source: source(caret: firstEnd))
        let registry = DefaultWritingTools.readOnlyMVP

        let outline = await registry.execute(
            AgentToolCall(name: "get_outline"), context: context
        )
        XCTAssertTrue(outline.content.contains("병원을 나서다"))
        XCTAssertTrue(outline.content.contains("범인의 정체"))
        XCTAssertFalse(outline.content.contains("contentHash"))
        XCTAssertFalse(outline.content.contains("분할"))

        let future = await registry.execute(
            AgentToolCall(name: "read_scene", arguments: ["scene_ref": .string("2")]),
            context: context
        )
        XCTAssertFalse(future.content.contains("error"))
        XCTAssertTrue(future.content.contains("범인"))
        XCTAssertEqual(context.boundedOffset(nil), (full.activeEntry.body as NSString).length)
        XCTAssertEqual(context.boundedOffset(firstEnd), firstEnd)
    }

    func testKeyScene없는_기존원고도_장단위로_전체탐색() async {
        let body = "# 1장\n첫 장의 내용이다.\n# 2장\n후반부의 비밀이 드러난다."
        let entry = JournalEntry(title: "기존 원고", body: body, kind: .novel)
        let firstEnd = DocumentOutline.parse(body).scenes[0].utf16Range.upperBound
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: firstEnd
        )
        let context = AgentContext(source: source)
        let registry = DefaultWritingTools.readOnlyMVP

        let outline = await registry.execute(
            AgentToolCall(name: "get_outline"), context: context
        )
        XCTAssertTrue(outline.content.contains("chapter:2"))
        XCTAssertTrue(outline.content.contains("2장"))
        XCTAssertTrue(outline.content.contains(#""key_scenes":[]"#))

        let second = await registry.execute(
            AgentToolCall(
                name: "read_scene",
                arguments: ["scene_ref": .string("chapter:2")]
            ),
            context: context
        )
        XCTAssertTrue(second.content.contains("후반부의 비밀"))
        XCTAssertFalse(second.content.contains("error"))
    }

    func test분석청크_요약과해시는_getOutline에_노출하지_않음() async {
        let body = "# 1장\n서연은 문을 열었다. 뒤에서 민준이 죽는다."
        let character = CharacterCard(name: "서연")
        let entry = JournalEntry(
            title: "경계", body: body, kind: .novel, characters: [character]
        )
        let outline = DocumentOutline.parse(body)
        let secretSummary = "민준이 뒤에서 죽는 장면"
        let knowledge = KnowledgeSnapshot(
            entryID: entry.id, outline: outline,
            summariesByHash: [outline.scenes[0].contentHash: secretSummary],
            characters: [character]
        )
        let caret = ("# 1장\n서연은 문을 열었다." as NSString).length
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [],
            knowledge: knowledge, caretUTF16: caret
        )

        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(name: "get_outline"), context: AgentContext(source: source)
        )
        XCTAssertFalse(result.content.contains(secretSummary))
        XCTAssertFalse(result.content.contains(outline.scenes[0].contentHash))
    }

    func testRuntime이_도구결과를_받아_다음턴에서_답변() async throws {
        let generator = FakeGenerator(turns: [
            AgentModelTurn(
                text: "",
                toolCalls: [AgentToolCall(name: "get_active_document")]
            ),
            AgentModelTurn(text: "현재 문서는 ‘비밀’이고 소설입니다.")
        ])
        let runtime = AgentRuntime(generator: generator, maxSteps: 3)
        let result = try await runtime.run(
            request: "무슨 문서야?", history: [], source: source(),
            parameters: CompletionParameters(maxTokens: 128), onEvent: { _ in }
        )

        XCTAssertEqual(result.text, "현재 문서는 ‘비밀’이고 소설입니다.")
        XCTAssertEqual(result.toolTrace.count, 1)
        XCTAssertEqual(result.toolTrace[0].step, 1)
        XCTAssertEqual(result.toolTrace[0].toolName, "get_active_document")
        XCTAssertTrue(result.toolTrace[0].resultSummary.contains("비밀"))
        let callCount = await generator.callCount
        let lastMessages = await generator.lastMessages
        XCTAssertEqual(callCount, 2)
        XCTAssertTrue(lastMessages.contains {
            $0.role == .tool && $0.content.contains("비밀")
        })
    }

    func testRuntime은_두번깨진도구마크업을_최종답변으로노출하지않음() async throws {
        let broken = AgentModelTurn(text: "<tool_call><arguments={깨진 호출}</tool_call>")
        let generator = FakeGenerator(turns: [
            broken, broken, AgentModelTurn(text: "확인한 근거로 답합니다.")
        ])
        let runtime = AgentRuntime(generator: generator, maxSteps: 3)
        let result = try await runtime.run(
            request: "구조를 알려 줘.", history: [], source: source(),
            parameters: CompletionParameters(maxTokens: 128), onEvent: { _ in }
        )
        XCTAssertEqual(result.text, "확인한 근거로 답합니다.")
        XCTAssertFalse(result.text.contains("tool_call"))
        let callCount = await generator.callCount
        XCTAssertEqual(callCount, 3)
    }

    func testRuntime은_이름미상화자질문을_모델없이결정적으로답함() async throws {
        let body = "나는 닭을 보았다. 내가 점순을 만났다. 난 울타리를 고쳤다."
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel,
            characters: [CharacterCard(name: "점순")]
        )
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (body as NSString).length
        )
        let generator = FakeGenerator(turns: [])
        let result = try await AgentRuntime(generator: generator).run(
            request: "이 작품의 서술 시점과 화자가 누구인지 알려 줘.",
            history: [], source: source,
            parameters: CompletionParameters(maxTokens: 128), onEvent: { _ in }
        )
        XCTAssertTrue(result.text.contains("1인칭"))
        XCTAssertTrue(result.text.contains("이름 미상"))
        XCTAssertTrue(result.text.contains("점순"))
        let callCount = await generator.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testRuntime은_전체플롯초안을_원문대조턴으로검증함() async throws {
        let generator = FakeGenerator(turns: [
            AgentModelTurn(text: "주체가 뒤집힌 초안"),
            AgentModelTurn(text: "원문과 대조해 주체를 바로잡은 5단계")
        ])
        let runtime = AgentRuntime(generator: generator, maxSteps: 3)
        let result = try await runtime.run(
            request: "사건을 실제 시간 순서대로 전체 플롯 5단계로 알려 줘.",
            history: [], source: source(),
            parameters: CompletionParameters(maxTokens: 512), onEvent: { _ in }
        )
        XCTAssertEqual(result.text, "원문과 대조해 주체를 바로잡은 5단계")
        let callCount = await generator.callCount
        let maxTokens = await generator.receivedMaxTokens
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(maxTokens, [512, 384])
    }
}

private actor FakeGenerator: AgentTurnGenerating {
    private var turns: [AgentModelTurn]
    private(set) var callCount = 0
    private(set) var lastMessages: [AgentChatMessage] = []
    private(set) var receivedMaxTokens: [Int] = []

    init(turns: [AgentModelTurn]) {
        self.turns = turns
    }

    func generateAgentTurn(
        messages: [AgentChatMessage], tools _: [ToolSpec],
        parameters: CompletionParameters,
        onChunk: @Sendable @escaping (String) -> Void
    ) async throws -> AgentModelTurn {
        callCount += 1
        lastMessages = messages
        receivedMaxTokens.append(parameters.maxTokens)
        guard !turns.isEmpty else { return AgentModelTurn(text: "끝") }
        let turn = turns.removeFirst()
        if !turn.text.isEmpty { onChunk(turn.text) }
        return turn
    }
}
