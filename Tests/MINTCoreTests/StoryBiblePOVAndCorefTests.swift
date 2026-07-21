import XCTest

@testable import MINTCore

final class StoryBiblePOVAndCorefTests: XCTestCase {
    // MARK: - 공유 한국어 이름 정규화

    func test_받침판정은_한글종성만_인정() {
        XCTAssertTrue(KoreanName.hasFinalConsonant("순"))
        XCTAssertFalse(KoreanName.hasFinalConsonant("수"))
        XCTAssertFalse(KoreanName.hasFinalConsonant("A"))
    }

    func test_점순과_점순이는_같은인물후보() {
        XCTAssertTrue(KoreanName.mayReferToSame("점순", "점순이"))
        XCTAssertTrue(KoreanName.canonicalForms("점순이").contains("점순"))
    }

    func test_서연이가에서_조사와매개이를_벗김() {
        XCTAssertTrue(KoreanName.canonicalForms("서연이가").contains("서연"))
    }

    func test_긴조사를_먼저벗김() {
        XCTAssertTrue(KoreanName.canonicalForms("민준에게서").contains("민준"))
    }

    func test_받침없는이름의_마지막글자는_벗기지않음() {
        XCTAssertFalse(KoreanName.canonicalForms("영수이도").contains("영수"))
    }

    func test_순이본명은_원형을보존() {
        XCTAssertTrue(KoreanName.canonicalForms("순이").contains("순이"))
        XCTAssertTrue(KoreanName.mayReferToSame("순이", "순이"))
    }

    func test_한글이아닌형태와_한글한글자는_거부() {
        XCTAssertTrue(KoreanName.canonicalForms("A순").isEmpty)
        XCTAssertTrue(KoreanName.canonicalForms("순").isEmpty)
    }

    func test_관련없는이름은_교집합이없음() {
        XCTAssertFalse(KoreanName.mayReferToSame("점순이", "민준"))
    }

    func test_Agent이름조회는_정규화하고_모호하면_모두반환() async {
        let cards = [CharacterCard(name: "점순"), CharacterCard(name: "점순이")]
        let entry = JournalEntry(title: "봄", body: "점순이가 왔다.", kind: .novel, characters: cards)
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
            caretUTF16: (entry.body as NSString).length)
        let registry = DefaultWritingTools.readOnlyMVP

        // 정확 일치가 정규화보다 먼저라 본명 "점순이" 카드만 나온다.
        let exact = await registry.execute(
            AgentToolCall(name: "find_character", arguments: ["character_ref": .string("점순이")]),
            context: AgentContext(source: source))
        XCTAssertTrue(exact.content.contains(cards[1].id.uuidString))
        XCTAssertFalse(exact.content.contains(cards[0].id.uuidString))

        let ambiguousCards = [CharacterCard(name: "점순", aliases: "순덕"), CharacterCard(name: "순덕이")]
        let ambiguousEntry = JournalEntry(
            title: "모호", body: "", kind: .novel, characters: ambiguousCards)
        let ambiguousSource = AgentSourceSnapshot(
            activeEntry: ambiguousEntry, entries: [ambiguousEntry], folders: [], knowledge: nil,
            caretUTF16: 0)
        let ambiguous = await registry.execute(
            AgentToolCall(name: "find_character", arguments: ["character_ref": .string("순덕이가")]),
            context: AgentContext(source: ambiguousSource))
        XCTAssertTrue(ambiguous.content.contains(ambiguousCards[0].id.uuidString))
        XCTAssertTrue(ambiguous.content.contains(ambiguousCards[1].id.uuidString))
    }

    // MARK: - 전역 서술 시점

    func test_대사속나는을제외하고_1인칭판정() {
        let body = """
            # 1장
            나는 문을 열었다. 내가 먼저 도착했다. 난 한동안 창밖을 보았다.
            “나는 범인이 아니야.” 그가 외쳤다.
            """
        let profile = NarrationAnalyzer.analyze(body: body, outline: .parse(body))
        XCTAssertEqual(profile.mode, .firstPerson)
        XCTAssertEqual(profile.firstPersonSubjectHits, 3)
    }

    func test_반복호명된_유일한이름을_1인칭화자로연결() {
        let 점순 = CharacterCard(name: "점순")
        let body = """
            나는 문을 열었다. 내가 먼저 왔다. 난 마루에 앉았다.
            “점순아, 여기 있었구나.” 그가 말했다. “점순아, 이제 가자.”
            """
        let profile = NarrationAnalyzer.analyze(
            body: body, outline: .parse(body), characters: [점순])
        XCTAssertEqual(profile.mode, .firstPerson)
        XCTAssertEqual(profile.narratorName, "점순")
    }

    func test_1인칭원고의_다른인물주어를_혼합으로오인하지않음() {
        let 민준 = CharacterCard(name: "민준")
        let body = """
            나는 문을 열었다. 내가 먼저 왔다. 민준은 뒤따라왔다.
            민준이가 불을 켰다. 민준도 의자에 앉았다.
            """
        let profile = NarrationAnalyzer.analyze(
            body: body, outline: .parse(body), characters: [민준])
        XCTAssertEqual(profile.mode, .firstPerson)
    }

    func test_등록인물주어로_3인칭판정() {
        let 서연 = CharacterCard(name: "서연")
        let body = """
            # 1장
            서연은 문을 열었다. 서연이가 먼저 도착했다. 서연도 창밖을 보았다.
            바람이 오래 불었다.
            """
        let profile = NarrationAnalyzer.analyze(
            body: body, outline: .parse(body), characters: [서연])
        XCTAssertEqual(profile.mode, .thirdPerson)
        XCTAssertEqual(profile.thirdPersonProperNameSubjectHits, 3)
    }

    func test_장마다_시점이다르면_혼합판정() {
        let 서연 = CharacterCard(name: "서연")
        let body = """
            # 서연의 기록
            나는 문을 열었다. 내가 먼저 도착했다. 난 비밀을 알고 있었다.
            # 관찰자의 기록
            서연은 문을 닫았다. 서연이가 계단을 올랐다. 서연도 뒤를 돌아봤다.
            """
        let profile = NarrationAnalyzer.analyze(
            body: body, outline: .parse(body), characters: [서연])
        XCTAssertEqual(profile.mode, .mixed)
    }

    func test_짧고근거없는원고는_미상() {
        let body = "비가 내렸다."
        let profile = NarrationAnalyzer.analyze(body: body, outline: .parse(body))
        XCTAssertEqual(profile.mode, .unknown)
    }

    func test_두인물의내면이면_전지적힌트() {
        let 서연 = CharacterCard(name: "서연")
        let 민준 = CharacterCard(name: "민준")
        let body = """
            서연은 그가 오리라고 생각했다. 민준은 자신이 늦었다고 느꼈다.
            서연이 문을 열었다. 민준도 고개를 들었다.
            """
        let profile = NarrationAnalyzer.analyze(
            body: body, outline: .parse(body), characters: [서연, 민준])
        XCTAssertEqual(profile.mode, .thirdPerson)
        XCTAssertEqual(profile.omniscientHint, true)
    }

    func test_사용자시점수정이_자동판정을이기고_헤더에주입() {
        let body = "나는 문을 열었다. 내가 먼저 왔다. 난 자리에 앉았다."
        let outline = DocumentOutline.parse(body)
        let snapshot = KnowledgeSnapshot(
            entryID: UUID(), outline: outline, summariesByHash: [:],
            overrides: NarrativeOverrides([
                NarrativeOverride(kind: .narrationMode, key: "global", value: "3인칭")
            ]), body: body)
        XCTAssertEqual(snapshot.narrationProfile.mode, .thirdPerson)
        let header = ContextAssembler.headerText(
            document: DocumentContext(title: "시험", kind: .novel),
            window: body, knowledge: snapshot)
        XCTAssertTrue(header.contains("[서술] 3인칭"))
    }

    func test_Agent도구가_전역시점과_커서POV폴백을노출() async {
        let body = "나는 문을 열었다. 내가 먼저 왔다. 난 자리에 앉았다."
        let entry = JournalEntry(title: "화자", body: body, kind: .novel)
        let snapshot = KnowledgeSnapshot(
            entryID: entry.id, outline: .parse(body), summariesByHash: [:], body: body)
        let source = AgentSourceSnapshot(
            activeEntry: entry, entries: [entry], folders: [], knowledge: snapshot,
            caretUTF16: (body as NSString).length)
        let context = AgentContext(source: source)
        let registry = DefaultWritingTools.readOnlyMVP
        let active = await registry.execute(
            AgentToolCall(name: "get_active_document"), context: context)
        XCTAssertTrue(active.content.contains(#""narration_mode":"1인칭""#))
        let atCursor = await registry.execute(
            AgentToolCall(name: "get_context_at_cursor"), context: context)
        XCTAssertTrue(atCursor.content.contains(#""pov":"1인칭 서술자""#))
    }
}
