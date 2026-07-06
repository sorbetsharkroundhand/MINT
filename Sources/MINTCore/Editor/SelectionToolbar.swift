import AppKit
import SwiftUI

/// 서식 툴바 액션 — `BlockTextView.perform(_:)`이 처리한다.
enum SelectionToolbarAction {
    /// 블록 전환 (같은 블록을 다시 누르면 본문으로 토글).
    case block(MintBlock)
    case toggleBold
    case toggleItalic
    case toggleCode
    /// nil = 왼쪽(기본) / "center" / "right".
    case align(String?)
    /// 인라인 색 hex, nil = 기본 잉크색으로 복원.
    case color(String?)
}

/// 툴바 버튼 하이라이트용 — 선택 시작 위치의 현재 서식 상태.
struct SelectionStyleState: Equatable {
    var block: MintBlock = .p
    var bold = false
    var italic = false
    var code = false
    var align: String?
    var colorHex: String?
}

/// 드래그 선택 위에 뜨는 플로팅 서식 툴바 (리퀴드 글래스 필 — 단축키 필과 동일 톤).
struct SelectionToolbarView: View {
    let theme: MintTheme
    let state: SelectionStyleState
    let onAction: (SelectionToolbarAction) -> Void

    /// 인라인 색 프리셋 (시스템 팔레트 계열).
    static let colorPresets = ["FF453A", "FF9F0A", "30D158", "0A84FF", "BF5AF2"]

    var body: some View {
        HStack(spacing: 2) {
            textButton("H1", active: state.block == .h1, help: "큰 제목") {
                onAction(.block(.h1))
            }
            textButton("H2", active: state.block == .h2, help: "중간 제목") {
                onAction(.block(.h2))
            }
            textButton("H3", active: state.block == .h3, help: "작은 제목") {
                onAction(.block(.h3))
            }
            divider
            textButton("B", weight: .bold, active: state.bold, help: "굵게 (⌘B / **텍스트**)") {
                onAction(.toggleBold)
            }
            textButton("I", italic: true, active: state.italic, help: "기울임 (⌘I / *텍스트*)") {
                onAction(.toggleItalic)
            }
            iconButton(
                "chevron.left.forwardslash.chevron.right",
                active: state.code, help: "인라인 코드 (`텍스트`)"
            ) { onAction(.toggleCode) }
            divider
            iconButton("text.quote", active: state.block == .quote, help: "인용") {
                onAction(.block(.quote))
            }
            iconButton("curlybraces", active: state.block == .code, help: "코드 블록 (```)") {
                onAction(.block(.code))
            }
            divider
            iconButton("text.alignleft", active: state.align == nil, help: "왼쪽 정렬") {
                onAction(.align(nil))
            }
            iconButton(
                "text.aligncenter", active: state.align == "center", help: "가운데 정렬"
            ) { onAction(.align("center")) }
            iconButton("text.alignright", active: state.align == "right", help: "오른쪽 정렬") {
                onAction(.align("right"))
            }
            divider
            colorDot(nil)
            ForEach(Self.colorPresets, id: \.self) { hex in
                colorDot(hex)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.pillC)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(theme.pillBorderC)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .fixedSize()
    }

    // MARK: 구성 요소

    private var divider: some View {
        theme.sepStrongC.frame(width: 1, height: 15).padding(.horizontal, 3)
    }

    private func textButton(
        _ label: String, weight: Font.Weight = .semibold, italic: Bool = false,
        active: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        ToolbarButton(theme: theme, active: active, help: help, action: action) {
            Text(label)
                .font(.system(size: 12, weight: weight, design: .serif))
                .italic(italic)
        }
    }

    private func iconButton(
        _ systemName: String, active: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        ToolbarButton(theme: theme, active: active, help: help, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private func colorDot(_ hex: String?) -> some View {
        let active = state.colorHex == hex
        let fill: Color =
            hex.flatMap { NSColor(inlineHex: $0).map(Color.init(nsColor:)) } ?? theme.inkC
        return ToolbarButton(
            theme: theme, active: active,
            help: hex == nil ? "기본색" : "글자색", action: { onAction(.color(hex)) }
        ) {
            Circle()
                .fill(fill)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(theme.sepStrongC))
        }
    }
}

/// 툴바 공용 버튼 — hover/활성 배경.
private struct ToolbarButton<Label: View>: View {
    let theme: MintTheme
    let active: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(active ? theme.blueC : theme.inkC)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? theme.activeBgC : (hovered ? theme.hoverC : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
