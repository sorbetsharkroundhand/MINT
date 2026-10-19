import SwiftUI

struct WorkspaceCompactCard<Content: View>: View {
    @ObservedObject var model: SpatialWorkspaceController
    let id: String
    let title: String
    let detail: String
    let term: String
    let theme: MintTheme
    @ViewBuilder let content: () -> Content
    private var matches: Bool { !term.isEmpty && model.activeParagraph.contains(term) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { model.expandedItem = model.expandedItem == id ? nil : id }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(matches ? theme.blueC : theme.sepC).frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).mintUIFont(11, .medium).foregroundStyle(theme.inkC)
                        if model.expandedItem != id { Text(detail).mintUIFont(10).foregroundStyle(theme.ink3C).lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: model.expandedItem == id ? "chevron.up" : "chevron.down").font(.system(size: 8)).foregroundStyle(theme.ink3C)
                }.fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mint.card.\(id)")
            if model.expandedItem == id { content() }
        }.padding(10).background(RoundedRectangle(cornerRadius: 6).fill(matches ? theme.activeBgC : theme.editorSurfaceC))
    }
}
