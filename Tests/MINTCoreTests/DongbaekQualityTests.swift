@testable import MINTCore
import XCTest

/// 사용자의 실제 「동백꽃」에서 드러난 품질 실패를 작은 공개 사실 픽스처로
/// 고정한다. 원문 전체를 복제하지 않고, 실패를 재현하는 최소 구절만 사용한다.
final class DongbaekQualityTests: XCTestCase {
    private let 점순 = CharacterCard(name: "점순")

    func test_이름미상1인칭화자를_역할카드로자동등록하고삭제거부를존중() {
        let body = "나는 닭을 보았다. 내가 막대기를 들었다. 난 울타리를 넘었다."
        let outline = DocumentOutline.parse(body)
        let card = BackgroundIndexer.narratorCardIfNeeded(
            body: body, outline: outline, characters: [점순]
        )
        XCTAssertEqual(card?.name, "화자")
        XCTAssertEqual(card?.role, .narrator)
        XCTAssertEqual(card?.autoRegistered, true)
        XCTAssertNil(BackgroundIndexer.narratorCardIfNeeded(
            body: body, outline: outline, characters: [점순],
            rejectedNames: [CharacterCard.narratorRejectionMarker]
        ))
    }

    func test_Agent근거팩은_스토리바이블과전체대사와짧은작품원문전체를제공() {
        let 화자 = CharacterCard(name: "화자", autoRegistered: true, role: .narrator)
        let body = """
        나는 울타리를 고쳤다. 내가 점순을 보았다. 난 고개를 들었다.
        점순이가 말했다. "얘! 너 혼자만 일하니?"
        "그래." 하고 나는 대답했다.
        """
        let cards = [점순, 화자]
        let dialogues = DialogueAttribution.dialogues(in: body, cards: cards)
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: cards
        )
        let snapshot = KnowledgeSnapshot(
            entryID: entry.id, outline: .parse(body), summariesByHash: [:],
            dialogues: dialogues, characters: cards, body: body
        )
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: snapshot,
            caretUTF16: (body as NSString).length
        )
        let pack = AgentEvidencePack.make(request: "모든 대사와 화자를 알려 줘.", source: source)
        XCTAssertTrue(pack.contains("스토리 바이블 인물 카드 전체"))
        XCTAssertTrue(pack.contains("역할=화자"))
        XCTAssertTrue(pack.contains("큰따옴표 전체 대사 인덱스"))
        XCTAssertTrue(pack.contains("활성 작품 원문 전체"))
        XCTAssertTrue(pack.contains(body))

        let answer = AgentEvidencePack.directAnswer(
            request: "모든 대사와 화자를 알려 줘.", source: source
        )
        XCTAssertTrue(answer?.contains("큰따옴표 대사 2개") == true)
        XCTAssertTrue(answer?.contains("점순:") == true)
        XCTAssertTrue(answer?.contains("화자:") == true)
    }

    func test_getDialogues는_미상도포함한전수목록을반환() async {
        let body = "\"알겠어.\" 점순이 말했다.\n\"누구인지 모르는 말.\""
        let entry = JournalEntry(
            title: "대사", body: body, kind: .novel, characters: [점순]
        )
        let context = AgentContext(source: AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (body as NSString).length
        ))
        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(name: "get_dialogues"), context: context
        )
        XCTAssertTrue(result.content.contains(#""total_before":2"#))
        XCTAssertTrue(result.content.contains(#""speaker":"점순""#))
        XCTAssertTrue(result.content.contains(#""speaker":"미상""#))
    }

    func test_분리문단의_점순대사를_이웃서술로귀속() {
        let body = """
        어쩌다 동리 어른이 웃으면,

        "염려 마서유. 갈 때 되면 어련히 갈라구!"

        이렇게 천연덕스레 받는 점순이었다.

        그러나 점순이가 앞으로 다가와서,

        "그럼 너 이담부텀 안 그럴 테냐?"

        하고 물을 때에야 나는 고개를 들었다.

        "그래!"

        하고 나는 무턱대고 대답하였다.
        """
        let utterances = DialogueAttribution.utterances(in: body, cards: [점순])
        XCTAssertEqual(utterances.map(\.text), [
            "염려 마서유. 갈 때 되면 어련히 갈라구!",
            "그럼 너 이담부텀 안 그럴 테냐?"
        ])
        XCTAssertTrue(utterances.allSatisfy { $0.speakerID == 점순.id })
        XCTAssertFalse(utterances.contains { $0.text == "그래!" })
    }

    func test_등록인물이_소유어로만나온리드인은_그인물대사로오인하지않음() {
        let body = """
        나는 사방을 둘러보고 점순이 집에 아무도 없음을 알았다. 막대기를 들며,

        "이놈의 계집애! 남의 닭을 왜 때리니?"

        하고 소리를 질렀다.
        """
        XCTAssertTrue(DialogueAttribution.utterances(in: body, cards: [점순]).isEmpty)
    }

    func test_명시적_장기회상을_분석청크경계너머로타일링() {
        let opening = Array(repeating: "오늘도 우리 수탉이 쫓기었다. 나는 닭을 떼어 놓았다.", count: 10)
            .joined(separator: " ")
        let past = Array(repeating: "나는 울타리를 고치고 점순은 닭을 몰고 왔다.", count: 90)
            .joined(separator: " ")
        let body = """
        \(opening)
        나흘 전 감자 건만 하더라도 나는 잘못한 것이 없다. \(past)
        그랬던 걸 이렇게 오다 보니까 또 쌈을 붙여 놓았다. 나는 다시 닭을 가두었다.
        """
        let outline = DocumentOutline.parse(body)
        XCTAssertGreaterThan(outline.scenes.count, 1)
        let narration = NarrationAnalyzer.analyze(body: body, outline: outline)
        let segments = TemporalShiftDetector.explicitFlashbackSegments(
            in: body, outline: outline, narration: narration
        )
        XCTAssertGreaterThan(segments.count, 1)

        let snapshot = KnowledgeSnapshot(
            entryID: UUID(), outline: outline, summariesByHash: [:],
            segments: segments.mapValues { SceneSegmentation(segments: $0) },
            body: body
        )
        let source = body as NSString
        let middle = source.range(of: "점순은 닭을 몰고 왔다").location
        let returned = source.range(of: "그랬던 걸 이렇게").location
        XCTAssertEqual(snapshot.position(at: middle).layer, .flashback)
        XCTAssertEqual(snapshot.position(at: middle).chrono, .before)
        XCTAssertEqual(snapshot.position(at: returned).layer, .present)

        let currentEvent = StoryEvent(
            sceneHash: outline.scenes[0].contentHash, participants: [],
            summary: "현재 닭싸움을 목격했다", importance: 4
        )
        let pastIndex = outline.scenes.indices.first { index in
            segments[outline.scenes[index].contentHash]?.contains {
                $0.localStart == 0 && $0.chrono == .before
            } == true
        }!
        let pastEvent = StoryEvent(
            sceneHash: outline.scenes[pastIndex].contentHash, participants: [],
            summary: "과거 점순이 닭을 몰고 왔다", importance: 4
        )
        let chronology = KnowledgeSnapshot(
            entryID: UUID(), outline: outline, summariesByHash: [:],
            events: [
                outline.scenes[0].contentHash: [currentEvent],
                outline.scenes[pastIndex].contentHash: [pastEvent]
            ],
            segments: segments.mapValues { SceneSegmentation(segments: $0) },
            body: body
        )
        XCTAssertEqual(
            chronology.chronologicalSceneOrder().first, pastIndex,
            "segments=\(segments)"
        )
        XCTAssertEqual(
            chronology.eventChronoOrder.first, pastEvent.stableKey,
            "current=\(currentEvent.stableKey), past=\(pastEvent.stableKey)"
        )
    }

    func test_Agent_결정적근거팩은_화자회상대사와신분원문을선제제공() {
        let body = """
        나는 닭을 보았다. 내가 점순을 보았다. 난 울타리를 고쳤다.
        나흘 전 감자 건만 하더라도 점순네는 마름이고 우리는 땅을 부쳤다.
        "염려 마서유. 갈 때 되면 어련히 갈라구!"
        이렇게 받는 점순이었다.
        그랬던 걸 이렇게 오다 보니까 다시 닭이 싸웠다.
        """
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: [점순]
        )
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (body as NSString).length
        )
        let pack = AgentEvidencePack.make(
            request: "점순의 말투와 회상 구조, 두 집안의 신분을 설명해 줘.",
            source: source
        )
        XCTAssertTrue(pack.contains("화자 이름 미상"))
        XCTAssertTrue(pack.contains("현재 → 회상 → 현재"))
        XCTAssertTrue(pack.contains("나흘 전"))
        XCTAssertTrue(pack.contains("그랬던 걸 이렇게"))
        XCTAssertTrue(pack.contains("염려 마서유"))
        XCTAssertTrue(pack.contains("마름"))
    }

    func test_Agent_전체플롯근거팩은_회복과실제죽음을따로제공() {
        let body = """
        점순네 수탉은 크고 작은 우리 수탉은 자꾸 쫓겼다.
        나는 우리 수탉에게 고추장을 먹였다.
        큰 닭이 앙갚음하자 우리 수탉은 찔끔 못하고 막 곯는다.
        고추장물을 먹은 우리 수탉은 오늘 아침에서야 겨우 정신이 든 모양이다.
        우리 수탉은 피를 흘리고 거의 빈사 지경이었다.
        나는 큰 수탉을 단매로 때려 엎었다. 닭은 꼼짝 못하고 그대로 죽어 버렸다.
        """
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: [점순]
        )
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (body as NSString).length
        )
        let pack = AgentEvidencePack.make(
            request: "전체 플롯을 실제 시간 순서로 요약해 줘.", source: source
        )
        XCTAssertTrue(pack.contains("생사 상태 원문 체크포인트"))
        XCTAssertTrue(pack.contains("죽은 것이 아니라 다시 정신이 듦"))
        XCTAssertTrue(pack.contains("잠시 반격했지만 결국 다시 밀림"))
        XCTAssertTrue(pack.contains("점순네 큰 수탉을 죽임"))
        XCTAssertTrue(pack.contains("꼼짝 못하고 그대로 죽어 버렸다"))

        let corrected = AgentEvidencePack.correctedAnswer(
            "화자는 고추장을 먹여 이기게 했다. 마지막에는 단도로 큰 수탉을 때려 죽였다.",
            request: "전체 플롯을 실제 시간 순서로 요약해 줘.", source: source
        )
        XCTAssertTrue(corrected.contains("잠시 반격하게 했지만 결국 다시 밀렸"))
        XCTAssertTrue(corrected.contains("이튿날 정신을 되찾았다"))
        XCTAssertTrue(corrected.contains("단매로 큰 수탉"))
        XCTAssertFalse(corrected.contains("이기게 했다"))
        XCTAssertFalse(corrected.contains("단도로"))

        let numbered = AgentEvidencePack.correctedAnswer(
            """
            1. 감자를 거절했다.
            2. 씨암탉을 때렸다.
            3. 고추장 독으로 우리 수탉이 죽었다.
            4. 화자가 단도리에 큰 수탉을 죽였다.
            5. 두 사람이 끝났다.
            """,
            request: "전체 플롯을 실제 시간 순서로 요약해 줘.", source: source
        )
        XCTAssertTrue(numbered.contains("결국 다시 밀렸다"))
        XCTAssertTrue(numbered.contains("이튿날 정신을 되찾았다"))
        XCTAssertFalse(numbered.contains("고추장 독"))
        XCTAssertFalse(numbered.contains("단도리에"))
    }

    func test_Agent_명시적수탉죽음은_모델없이소유자까지답함() {
        let body = """
        나는 닭을 보았다. 내가 울타리를 고쳤다. 난 다시 밭으로 갔다.
        점순네 수탉은 크고 작은 우리 수탉은 자꾸 쫓겼다.
        우리 수탉은 피를 흘리고 거의 빈사 지경이었다.
        나는 큰 수탉을 단매로 때려 엎었다. 닭은 꼼짝 못하고 그대로 죽어 버렸다.
        """
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: [점순]
        )
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (body as NSString).length
        )
        let answer = AgentEvidencePack.directAnswer(
            request: "마지막에 누가 누구의 수탉을 죽였는지 알려 줘.", source: source
        )
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer?.contains("이름 미상 1인칭 화자") == true)
        XCTAssertTrue(answer?.contains("점순네 큰 수탉") == true)
        XCTAssertFalse(answer?.contains("자신의 수탉") == true)
    }

    func test_사건파서는_같은씬의_동일요약을한번만받음() {
        let output = """
        점순이 감자를 건넸다 | 참여: 점순 | 중요도: 4
        점순이 감자를 건넸다 | 참여: 점순 | 중요도: 4
        """
        let events = EventParser.parse(
            output, sceneHash: "h", nameIndex: EventParser.nameIndex([점순])
        )
        XCTAssertEqual(events.count, 1)
    }

    func test_같은안정키끼리는_동일사건관계가될수없음() {
        let result = EventGraphParser.parse(
            "동일: 1 & 2", keys: ["same-event", "same-event"]
        )
        XCTAssertTrue(result.identities.isEmpty)
    }

    func test_Agent는_이름미상화자를_등록인물로추정하지않도록표시() async {
        let body = "나는 닭을 보았다. 내가 막대기를 들었다. 난 점순을 바라보았다."
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: [점순]
        )
        let snapshot = KnowledgeSnapshot(
            entryID: entry.id, outline: .parse(body), summariesByHash: [:],
            characters: [점순], body: body
        )
        let context = AgentContext(source: AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: snapshot,
            caretUTF16: (body as NSString).length
        ))
        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(name: "get_active_document"), context: context
        )
        XCTAssertTrue(result.content.contains(#""narration_mode":"1인칭""#))
        XCTAssertTrue(result.content.contains("등록 인물을 화자로 추정하지 말 것"))
    }

    func test_타임라인은_내부해시대신_읽을수있는장참조와근거를줌() async {
        let body = "오늘도 닭이 싸웠다. 화자가 점순네 수탉을 막대기로 때려 죽였다."
        let outline = DocumentOutline.parse(body)
        let hash = outline.scenes[0].contentHash
        let event = StoryEvent(
            sceneHash: hash, participants: [점순.id],
            summary: "화자가 점순네 수탉을 죽였다", importance: 5,
            quote: "수탉을 막대기로 때려 죽였다"
        )
        let entry = JournalEntry(
            title: "동백꽃", body: body, kind: .novel, characters: [점순]
        )
        let snapshot = KnowledgeSnapshot(
            entryID: entry.id, outline: outline, summariesByHash: [:],
            events: [hash: [event]], characters: [점순], body: body
        )
        let context = AgentContext(source: AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: snapshot,
            caretUTF16: (body as NSString).length
        ))
        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(name: "get_timeline"), context: context
        )
        XCTAssertTrue(result.content.contains(#""chapter_ref":"chapter:1""#))
        XCTAssertTrue(result.content.contains(#""chapter_offset":0"#))
        XCTAssertTrue(result.content.contains(#""evidence":"직접""#))
        XCTAssertTrue(result.content.contains("수탉을 막대기로 때려 죽였다"))
        XCTAssertFalse(result.content.contains(hash))
    }

    func test_getCharacter_별칭호출을_findCharacter로복구() async {
        var automatic = 점순
        automatic.autoRegistered = true
        automatic.note = "검증되지 않은 자동 성격 초안"
        let entry = JournalEntry(
            title: "동백꽃", body: "점순이가 왔다.", kind: .novel,
            characters: [automatic]
        )
        let context = AgentContext(source: AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (entry.body as NSString).length
        ))
        let result = await DefaultWritingTools.readOnlyMVP.execute(
            AgentToolCall(
                name: "get_character",
                arguments: ["character_ref": .string("점순이")]
            ),
            context: context
        )
        XCTAssertFalse(result.content.contains("error"))
        XCTAssertTrue(result.content.contains(점순.id.uuidString))
        XCTAssertFalse(result.content.contains("검증되지 않은 자동 성격 초안"))
        XCTAssertTrue(result.content.contains("자동 초안"))
    }
}
