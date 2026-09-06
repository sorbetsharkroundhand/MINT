import SwiftUI

/// 기존 트리의 검색·이동·이름 변경을 재사용하며 문서 탐색을 항상 유지한다.
/// #104의 프로젝트 세션 연결 전에는 안전한 기존 EntryStore를 데이터 원본으로 쓴다.
struct ProjectNavigatorView: View {
    @ObservedObject var store: EntryStore
    @ObservedObject var completion: CompletionController
    let theme: MintTheme

    var body: some View {
        SidebarView(presentation: .navigator, store: store, completion: completion, theme: theme)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mint.navigator")
            .accessibilityLabel("문서 탐색기")
    }
}
