import AppKit
import SwiftUI

/// 좌측 저널 사이드바 (에디터 v3 — 디자인 이식).
///
/// 상단: 신호등 여백 + "MINT"(세리프) + 새 저널(＋).
/// 목록: 활성 점 · 제목(더블클릭 이름변경) · 활성 행 삭제(✕) / 비활성 행 날짜.
struct SidebarView: View {
    @ObservedObject var store: EntryStore
    let theme: MintTheme

    @State private var editingID: UUID?
    @State private var draftTitle = ""
    @State private var hoveredID: UUID?
    @State private var plusHovered = false
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // hiddenTitleBar 창의 신호등이 떠 있는 영역 (디자인 52px).
            Color.clear.frame(height: 44)
            header
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.entries) { entry in
                        row(entry)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .background(theme.sidebarTintC)
        .overlay(alignment: .trailing) { theme.sepC.frame(width: 1) }
        .onChange(of: renameFieldFocused) { _, focused in
            // Enter(onSubmit) 외에 포커스를 잃어도 커밋 — Esc는 editingID를
            // 먼저 비우므로 여기 걸리지 않는다.
            if !focused, let id = editingID { commitRename(id) }
        }
    }

    private var header: some View {
        HStack {
            Text("MINT")
                .font(MintFonts.serifUI(19, .semibold))
                .foregroundStyle(theme.inkC)
            Spacer()
            Button {
                store.newEntry()
            } label: {
                Text("＋")
                    .font(.system(size: 19))
                    .foregroundStyle(theme.ink2C)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(plusHovered ? theme.hoverC : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { plusHovered = $0 }
            .help("새 저널")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private func row(_ entry: JournalEntry) -> some View {
        let active = entry.id == store.activeID
        let editing = editingID == entry.id
        let hovered = hoveredID == entry.id

        HStack(spacing: 11) {
            Circle()
                .fill(active ? theme.blueC : theme.ink3C)
                .frame(width: 7, height: 7)

            if editing {
                TextField("제목", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.kbdC))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).strokeBorder(theme.blueC)
                    )
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(entry.id) }
                    .onExitCommand {
                        editingID = nil
                        renameFieldFocused = false
                    }
            } else {
                Text(entry.title)
                    .font(MintFonts.uiFont(13, active ? .semibold : .medium))
                    .foregroundStyle(active ? theme.inkC : theme.ink2C)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if active && !editing {
                DeleteButton(theme: theme) { store.delete(entry.id) }
            } else if !editing {
                Text(store.dayLabel(for: entry))
                    .font(MintFonts.uiFont(11))
                    .foregroundStyle(theme.ink3C)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active ? theme.activeBgC : (hovered ? theme.hoverC : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hoveredID = $0 ? entry.id : nil }
        .onTapGesture(count: 2) { startRename(entry) }
        .onTapGesture { store.select(entry.id) }
        .contextMenu {
            Button("이름 바꾸기") { startRename(entry) }
            Button("삭제", role: .destructive) { store.delete(entry.id) }
        }
    }

    private func startRename(_ entry: JournalEntry) {
        store.select(entry.id)
        draftTitle = entry.title
        editingID = entry.id
        // 필드가 뷰 트리에 붙은 다음 틱에 포커스를 준다.
        Task { renameFieldFocused = true }
    }

    private func commitRename(_ id: UUID) {
        store.rename(id, to: draftTitle)
        editingID = nil
    }
}

/// 활성 행의 ✕ — hover 시 빨간 배경 (디자인).
private struct DeleteButton: View {
    let theme: MintTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 12))
                .foregroundStyle(hovered ? Color(nsColor: NSColor(hex: 0xFF453A)) : theme.ink3C)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovered
                            ? Color(nsColor: NSColor(hex: 0xFF453A, alpha: 0.14)) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("이 저널 삭제")
    }
}
