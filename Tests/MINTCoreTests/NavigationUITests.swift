@testable import MINTCore
import XCTest

final class NavigationUITests: XCTestCase {
    func test_breadcrumb는_커서가_속한_헤딩경로를_반환한다() {
        let body = """
        # 1부
        시작.
        ## 2장
        이어진다.
        ### 골목
        마주쳤다.
        """
        let outline = DocumentOutline.parse(body)
        let cursor = (body as NSString).range(of: "마주쳤다").location

        XCTAssertEqual(outline.headingPath(at: cursor), ["1부", "2장", "골목"])
    }

    func test_breadcrumb는_헤딩없는_원고에서_비어있다() {
        let body = "헤딩 없이 이어지는 원고"
        XCTAssertEqual(DocumentOutline.parse(body).headingPath(at: 5), [])
    }

    func test_사이드바_단계는_전체_레일_숨김_순으로_순환한다() {
        XCTAssertEqual(SidebarPresentation.full.next, .rail)
        XCTAssertEqual(SidebarPresentation.rail.next, .hidden)
        XCTAssertEqual(SidebarPresentation.hidden.next, .full)
    }
}
