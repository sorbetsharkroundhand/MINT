@testable import MINTCore
import XCTest

/// EPUB OPF 메타데이터 회귀 테스트 — 저자 이름(설정 `mint.authorName`)이
/// `<dc:creator>`로 실리는지, 비었을 땐 아예 빠지는지를 고정한다.
@MainActor
final class EpubMetadataTests: XCTestCase {
    private func opf(author: String) -> String {
        let entry = JournalEntry(title: "첫 소설", body: "# 1장\n서연은 창밖을 보았다.")
        return EpubExporter.packageOPF(
            entry: entry, chapters: [], images: [], author: author
        )
    }

    func test저자가_있으면_creator와_role이_들어간다() {
        let xml = opf(author: "류제경")
        XCTAssertTrue(xml.contains("<dc:creator id=\"creator\">류제경</dc:creator>"))
        XCTAssertTrue(
            xml.contains(
                "<meta refines=\"#creator\" property=\"role\" scheme=\"marc:relators\">aut</meta>"
            )
        )
    }

    func test저자가_비면_creator를_넣지_않는다() {
        // 빈 저자명을 쓰느니 없는 편이 낫다.
        XCTAssertFalse(opf(author: "").contains("dc:creator"))
        XCTAssertFalse(opf(author: "   \n").contains("dc:creator"))
    }

    func test저자_이름의_XML_특수문자는_이스케이프된다() {
        let xml = opf(author: "A & B <필명>")
        XCTAssertTrue(xml.contains("A &amp; B &lt;필명&gt;"))
        XCTAssertFalse(xml.contains("<필명>"))
    }
}
