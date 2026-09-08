import SwiftUI

/// Reuses the existing search, move, and rename tree so document navigation stays available.
/// The #104 session drives shell routing; #118 owns the project-first document handoff.
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
