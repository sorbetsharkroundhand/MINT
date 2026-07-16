import AppKit
import XCTest

@testable import MINTCore

/// 원고 무결성 회귀 테스트 — 직렬화는 **저장 경로**다. 여기가 틀리면 원고가
/// 손상되고 되돌릴 수 없다 (CLAUDE.md §5-5).
///
/// 성능 작업(증분 직렬화·디바운스) 전에 **현재 동작을 그대로 고정**하는 것이
/// 목적이다. 이상적 동작이 아니라 지금 동작을 박아 둔다 — 회귀를 잡는 그물이지
/// 명세가 아니다. 왕복이 완전 대칭이 아님은 이미 알려져 있다 (BlockTextView
/// `updateNSView`의 `lastSyncedText` 주석, r1 버그).
///
/// `swift test`로 돈다 — MLX 커널을 건드리지 않아 metallib 없이 안전하다.
final class SerializationTests: XCTestCase {

    /// 테스트 수명 동안 창을 살려 둔다 — `undoManager`는 응답자 사슬(창)에서 오므로
    /// 창이 없으면 nil이 되어 undo 테스트가 **조용히 통과**해 버린다.
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.removeAll()
        super.tearDown()
    }

    /// 에디터를 조립한다 (`makeNSView`의 TextKit 1 스택·설정과 동일).
    @MainActor
    private func makeEditor() -> BlockTextView {
        let storage = NSTextStorage()
        let layoutManager = MintLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = BlockTextView(
            frame: NSRect(x: 0, y: 0, width: 700, height: 900), textContainer: container)
        storage.delegate = view
        view.allowsUndo = true  // makeNSView와 동일

        // 창에 넣어야 undoManager가 생긴다 (앱과 같은 조건).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(view)
        window.makeFirstResponder(view)
        windows.append(window)
        return view
    }

    /// 핵심 불변조건: 마크다운을 열어 그대로 저장하면 원문이 나온다.
    @MainActor
    private func assertRoundTrip(
        _ markdown: String, _ message: String = "", file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let view = makeEditor()
        view.load(markdown: markdown)
        XCTAssertEqual(view.serialize(), markdown, message, file: file, line: line)
    }

    // MARK: - 왕복 (열기 → 저장 == 원문)

    @MainActor func testPlainKorean() {
        assertRoundTrip("안녕하세요. 오늘은 비가 왔다.")
    }

    @MainActor func testHeadings() {
        assertRoundTrip("# 1장\n## 절\n### 씬\n본문이다.")
    }

    @MainActor func testBlankLinesPreserved() {
        assertRoundTrip("첫 문단.\n\n둘째 문단.\n\n\n셋째 문단.")
    }

    @MainActor func testConsecutiveNewlines() {
        assertRoundTrip("가\n\n\n\n\n나")
    }

    @MainActor func testTrailingNewline() {
        assertRoundTrip("본문이다.\n")
    }

    @MainActor func testLeadingBlankLines() {
        assertRoundTrip("\n\n본문이다.")
    }

    @MainActor func testEmptyDocument() {
        assertRoundTrip("")
    }

    @MainActor func testBlockKinds() {
        assertRoundTrip("- 불릿\n- 둘\n1. 번호\n2. 둘\n> 인용\n- [ ] 할 일\n- [x] 한 일")
    }

    @MainActor func testDivider() {
        assertRoundTrip("위\n\n---\n\n아래")
    }

    /// ⚠️ **알려진 비대칭 (기존 동작 고정)**: 문서 끝 코드 블록은 왕복에서 개행이
    /// 하나 붙는다. `serialize()`의 "문서가 개행으로 끝나면 마지막 빈 문단도 한 줄"
    /// 규칙이 닫는 ``` 뒤에도 적용되기 때문. 내용 손실은 없고 **1회 정규화 뒤
    /// 안정**하다(`testSerializationIsIdempotent`). 고치려면 여기 기대값을 바꾼다.
    @MainActor func testCodeBlock_knownTrailingNewline() {
        let view = makeEditor()
        view.load(markdown: "```\nlet x = 1\nprint(x)\n```")
        XCTAssertEqual(view.serialize(), "```\nlet x = 1\nprint(x)\n```\n")
    }

    /// 코드 블록이 문서 끝이 아니면 왕복이 정확하다 — 위 비대칭의 경계를 못 박는다.
    @MainActor func testCodeBlockFollowedByText() {
        assertRoundTrip("```\nlet x = 1\n```\n뒤에 본문이 있다.")
    }

    @MainActor func testInlineFormatting() {
        assertRoundTrip("**굵게**와 *기울임*과 `코드`가 있다.")
    }

    @MainActor func testKoreanWithNumbers() {
        // 「날개」에서 선두 숫자가 먹히던 부류의 함정 (사건 파서 회귀와 같은 계열).
        assertRoundTrip("33번지 18가구의 낮은 참 조용하다.\n1930년의 일이다.")
    }

    @MainActor func testMixedDocument() {
        assertRoundTrip(
            """
            # 날개

            > 이상, 1936년 발표

            박제가 되어 버린 천재를 아시오? 나는 유쾌하오.

            ## 1절

            - 첫째
            - 둘째

            **굵은** 문장과 보통 문장.
            """)
    }

    // MARK: - 기존 문서 포맷 호환 (실제 저널)

    private func realJournalBodies() throws -> [(String, String)] {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MINT/entries.json")
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else { throw XCTSkip("로컬 저널 없음 — 이 검사는 실기기 전용") }
        return entries.compactMap { entry in
            guard let body = entry["body"] as? String, !body.isEmpty else { return nil }
            return ((entry["title"] as? String) ?? "?", body)
        }
    }

    /// 실제 저장된 원고에 **글자 손실이 없는지** — 합성 픽스처가 놓치는 조합을 잡는다.
    ///
    /// 왕복이 바이트 단위로 같기를 요구하지 않는다: 첫 저장은 서식 태그를 정규화한다
    /// (조각난 `<font size="12">` 런들이 하나로 병합 — 폰트 수정으로 런이 줄어든
    /// 결과). 정규화는 허용하되 **본문 글자가 사라지면 안 된다.**
    @MainActor func testRealJournalPreservesVisibleText() throws {
        for (title, body) in try realJournalBodies() {
            let view = makeEditor()
            view.load(markdown: body)
            _ = view.serialize()
            // 화면에 보이는 텍스트(= storage 문자열)에 원문의 글자가 살아 있는가.
            // 마크업을 걷어낸 뒤 비교한다.
            func visible(_ s: String) -> String {
                s.replacingOccurrences(
                    of: "<[^>]+>", with: "", options: .regularExpression)
                    .filter { !$0.isWhitespace }
            }
            XCTAssertEqual(
                visible(view.serialize()), visible(body),
                "본문 글자가 왕복에서 바뀌었다: \(title)")
        }
    }

    /// **정규화는 1회, 그 뒤로는 안정해야 한다.**
    ///
    /// 첫 저장이 서식을 정리하는 건 받아들이지만, 열 때마다 결과가 또 바뀌면
    /// 문서가 저장할 때마다 자라거나 흔들린다 — 원고가 조용히 변형된다.
    /// 이것이 왕복 비대칭을 안전하게 만드는 진짜 불변조건이다.
    @MainActor func testSerializationIsIdempotent() throws {
        var cases: [(String, String)] = [
            ("코드블록", "```\nlet x = 1\n```"),
            ("헤딩+본문", "# 1장\n본문이다.\n\n둘째."),
            ("연속 개행", "가\n\n\n\n나"),
            ("인라인 서식", "**굵게** 그리고 *기울임*."),
        ]
        cases += (try? realJournalBodies()) ?? []

        for (label, original) in cases {
            let first = makeEditor()
            first.load(markdown: original)
            let once = first.serialize()

            let second = makeEditor()
            second.load(markdown: once)
            let twice = second.serialize()

            XCTAssertEqual(twice, once, "직렬화가 안정적이지 않다 (열 때마다 변형): \(label)")
        }
    }

    // MARK: - 편집 반영 (문서 처음·끝·대량)

    @MainActor func testEditAtStart() {
        let view = makeEditor()
        view.load(markdown: "본문이다.")
        view.insertText("앞", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.serialize(), "앞본문이다.")
    }

    @MainActor func testEditAtEnd() {
        let view = makeEditor()
        view.load(markdown: "본문이다.")
        let end = (view.string as NSString).length
        view.insertText("뒤", replacementRange: NSRange(location: end, length: 0))
        XCTAssertEqual(view.serialize(), "본문이다.뒤")
    }

    @MainActor func testEditInMiddleOfMultilineDocument() {
        let view = makeEditor()
        view.load(markdown: "첫 줄\n둘째 줄\n셋째 줄")
        let at = (view.string as NSString).range(of: "둘째").location
        view.insertText("X", replacementRange: NSRange(location: at, length: 0))
        XCTAssertEqual(view.serialize(), "첫 줄\nX둘째 줄\n셋째 줄")
    }

    @MainActor func testLargePaste() {
        let view = makeEditor()
        view.load(markdown: "시작.")
        let big = (1...200).map { "\($0)번째 문단이다." }.joined(separator: "\n")
        let end = (view.string as NSString).length
        view.insertText("\n" + big, replacementRange: NSRange(location: end, length: 0))
        XCTAssertEqual(view.serialize(), "시작.\n" + big)
    }

    @MainActor func testDeleteRange() {
        let view = makeEditor()
        view.load(markdown: "앞부분\n지울 줄\n뒷부분")
        let target = (view.string as NSString).range(of: "지울 줄\n")
        view.insertText("", replacementRange: target)
        XCTAssertEqual(view.serialize(), "앞부분\n뒷부분")
    }

    @MainActor func testDeleteEverything() {
        let view = makeEditor()
        view.load(markdown: "# 제목\n본문\n\n더 많은 본문")
        view.insertText(
            "", replacementRange: NSRange(location: 0, length: (view.string as NSString).length))
        XCTAssertEqual(view.serialize(), "")
    }

    // MARK: - 한글 IME 조합

    /// 조합 중(`markedText`)에도 직렬화가 화면 텍스트와 어긋나지 않아야 한다 —
    /// 조합 글자가 사라지거나 중복되면 원고 손상이다.
    @MainActor func testIMEMarkedTextIsSerialized() {
        let view = makeEditor()
        view.load(markdown: "가나다")
        let end = (view.string as NSString).length
        view.setMarkedText(
            "ㄹ", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: end, length: 0))
        XCTAssertTrue(view.hasMarkedText(), "조합 상태여야 한다")
        XCTAssertEqual(view.serialize(), "가나다ㄹ", "조합 중 글자도 직렬화에 보인다")

        view.setMarkedText(
            "라", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: view.markedRange())
        XCTAssertEqual(view.serialize(), "가나다라")

        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.serialize(), "가나다라")
    }

    @MainActor func testIMECompositionThenMoreText() {
        let view = makeEditor()
        view.load(markdown: "")
        view.setMarkedText(
            "ㅎ", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 0, length: 0))
        view.setMarkedText(
            "한", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: view.markedRange())
        view.unmarkText()
        view.insertText(
            "글", replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        XCTAssertEqual(view.serialize(), "한글")
    }

    // MARK: - Undo / Redo

    /// Undo/Redo 뒤의 직렬화가 **화면 텍스트와 정확히 일치**해야 한다.
    /// 어긋나면 사용자가 보는 것과 저장되는 것이 달라진다.
    @MainActor func testUndoRedoMatchesScreen() {
        let view = makeEditor()
        view.load(markdown: "원본이다.")
        let before = view.serialize()

        view.insertText(
            "추가", replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        let after = view.serialize()
        XCTAssertEqual(after, "원본이다.추가")

        view.undoManager?.undo()
        XCTAssertEqual(view.serialize(), before, "undo 후 저장 텍스트가 화면과 달라졌다")

        view.undoManager?.redo()
        XCTAssertEqual(view.serialize(), after, "redo 후 저장 텍스트가 화면과 달라졌다")
    }

    // MARK: - 성능 작업의 핵심 불변조건

    /// `serialize(증분 상태) == serialize(전체 문서)`.
    ///
    /// 여러 번 편집한 뒤의 직렬화가, **같은 내용을 새로 열어 직렬화한 것**과
    /// 같아야 한다. 증분 구조를 넣든 디바운스를 넣든 이 등식이 깨지면 원고 손상이다.
    @MainActor func testIncrementalEqualsFullSerialization() {
        let view = makeEditor()
        view.load(markdown: "# 1장\n첫 문단이다.\n\n둘째 문단이다.")

        view.insertText("맨앞 ", replacementRange: NSRange(location: 0, length: 0))
        let mid = (view.string as NSString).range(of: "둘째").location
        view.insertText("바뀐 ", replacementRange: NSRange(location: mid, length: 0))
        view.insertText(
            "끝", replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText("", replacementRange: (view.string as NSString).range(of: "첫 "))

        let incremental = view.serialize()

        // 같은 내용을 새 에디터에 열어 직렬화 — 증분 상태가 없는 기준선.
        let fresh = makeEditor()
        fresh.load(markdown: incremental)
        XCTAssertEqual(
            fresh.serialize(), incremental,
            "serialize(증분 상태) != serialize(전체 문서) — 원고 손상")
    }
}
