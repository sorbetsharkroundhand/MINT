import XCTest

@testable import MINTCore

/// ContextAssembler의 사용자 결정(Pin) 규율과 stableKey 고유성 검증.
///
/// - Pin은 "항상 실린다"가 계약이다(§31) — 상한(maxCards)이 사용자 지정을
///   이기면 인스펙터에서 고정한 항목이 말없이 사라져 신뢰가 깨진다.
/// - stableKey는 오버라이드의 키다 — 두 항목이 같은 키를 쓰면 Pin/Exclude가
///   서로를 덮어 "인스펙터가 보는 것 = 조립이 하는 것"(§6.5)이 무너진다.
final class ContextAssemblerSelectionTests: XCTestCase {

    // MARK: - 카드 선택 (Pin은 상한을 이긴다)

    private func cards(_ names: [String]) -> [CharacterCard] {
        names.map { CharacterCard(name: $0) }
    }

    func test_핀카드가_상한보다_많아도_전부_실린다() {
        let all = cards(["가", "나", "다", "라", "마"])
        let pins = Set(all.prefix(4).map { "card|\($0.id.uuidString)" })
        let chosen = ContextAssembler.selectCards(
            from: all, window: "", controls: .init(pins: pins))
        XCTAssertEqual(
            Set(chosen.map(\.name)), ["가", "나", "다", "라"],
            "Pin 4장은 maxCards(3)를 넘어도 전부 실린다 — 사용자 지정이 휴리스틱 예산을 이긴다")
    }

    func test_핀_뒤_남는자리는_언급카드로_채운다() {
        let all = cards(["서연", "민준", "도윤", "하늘", "지우"])
        let pins = Set([all[3]].map { "card|\($0.id.uuidString)" })  // "하늘"만 고정
        let chosen = ContextAssembler.selectCards(
            from: all, window: "지우가 고개를 끄덕였다", controls: .init(pins: pins))
        XCTAssertEqual(Set(chosen.map(\.name)), ["서연", "하늘", "지우"])
    }

    func test_핀없으면_기존규칙_문서순_상한채움() {
        let all = cards(["서연", "민준", "도윤", "하늘", "지우"])
        let chosen = ContextAssembler.selectCards(from: all, window: "")
        XCTAssertEqual(chosen.map(\.name), ["서연", "민준", "도윤"])
    }

    // MARK: - 흐름 사건 stableKey

    /// 씬 3개 — 2장이 회상 구간(남편 소속), 남편 참여 사건 2개.
    private func flashbackSnapshot() -> (KnowledgeSnapshot, DocumentOutline, UUID) {
        let body = """
            # 1장
            남편은 아침을 먹었다. 아내가 커피를 내렸다.

            # 2장
            남편이 어린 시절을 떠올렸다. 그날의 여름은 길고 뜨거웠다.

            # 3장
            진실이 드러났다. 남편은 고개를 떨궜다.
            """
        let outline = DocumentOutline.parse(body)
        let h2 = outline.scenes[1].contentHash
        let 남편 = CharacterCard(name: "남편")
        // 같은 인물이 참여한 사건 2개 — 인물 흐름 파생의 최소 조건(2개↑).
        let events = [
            StoryEvent(sceneHash: h2, participants: [남편.id], summary: "우물가의 여름", importance: 3),
            StoryEvent(sceneHash: h2, participants: [남편.id], summary: "아버지와의 다툼", importance: 3),
        ]
        let segments = SceneSegmentation(segments: [
            NarrativeSegment(
                sceneHash: h2, localStart: 0, localEnd: 500,
                startQuote: "남편이 어린 시절을 떠올렸다",
                layer: .flashback, depth: 1, subjectCharacter: "남편")
        ])
        let snapshot = KnowledgeSnapshot(
            entryID: UUID(), outline: outline, summariesByHash: [:],
            events: [h2: events], segments: [h2: segments],
            characters: [남편])
        return (snapshot, outline, 남편.id)
    }

    func test_흐름사건_stableKey가_사건마다_고유다() {
        let (snapshot, outline, _) = flashbackSnapshot()
        var report: [ContextReport.Item] = []
        // 회상 구간 안 커서 — writingInPast + 인물 흐름.
        let cursor = outline.scenes[1].utf16Range.lowerBound + 5
        _ = ContextAssembler.knowledgeText(
            snapshot, before: cursor,
            position: snapshot.position(at: cursor),
            controls: .init(snapshot), report: &report)
        let flowItems = report.filter { $0.kind == .flowEvent }
        XCTAssertEqual(flowItems.count, 2, "흐름의 두 사건이 모두 주입돼야 한다")
        XCTAssertEqual(
            Set(flowItems.map(\.stableKey)).count, flowItems.count,
            "stableKey가 겹치면 한쪽의 Pin/Exclude가 다른 쪽까지 덮는다")
        XCTAssertTrue(
            flowItems.allSatisfy { $0.stableKey.hasPrefix("flow|") },
            "키는 정본 사건 키를 포함해 인스펙터에서 개별 지정 가능해야 한다")
    }
}
