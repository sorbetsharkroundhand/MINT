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
    /// 글자 크기 pt (절대값) — 블록 기본 크기와 같으면 속성이 제거된다.
    case fontSize(Double)
    /// 선택 문단들의 줄 간격 pt (요구 4).
    case lineSpacing(Double)
}

/// 툴바 버튼 하이라이트용 — 선택 시작 위치의 현재 서식 상태.
struct SelectionStyleState: Equatable {
    var block: MintBlock = .p
    var bold = false
    var italic = false
    var code = false
    var align: String?
    var colorHex: String?
    /// 선택 시작 위치의 실제 글자 크기 pt (표시·± 스텝 기준).
    var fontSize: Double = 20
    /// 선택 시작 문단의 줄 간격 pt (표시·± 스텝 기준).
    var lineSpacing: Double = 7
}

/// 드래그 선택 위에 뜨는 플로팅 서식 툴바 (리퀴드 글래스 필 — 단축키 필과 동일 톤).
struct SelectionToolbarView: View {
    let theme: MintTheme
    let state: SelectionStyleState
    let onAction: (SelectionToolbarAction) -> Void

    /// 인라인 색 프리셋 (시스템 팔레트 계열).
    static let colorPresets = ["FF453A", "FF9F0A", "30D158", "0A84FF", "BF5AF2"]
    /// 글자 크기 허용 범위 (± 버튼·키보드 입력 공통 한계).
    static let minFontSize = 10.0
    static let maxFontSize = 64.0
    /// 줄 간격 허용 범위(pt).
    static let minLineSpacing = 0.0
    static let maxLineSpacing = 20.0

    var body: some View {
        // 인라인 문자 서식에 집중한다 — 제목·목록·인용·정렬·코드 블록 같은 블록/구조
        // 서식은 서식 메뉴(⌘⌥1~3 등)로 옮겨 툴바를 가볍게 했다(예전엔 ~20개가 본문을
        // 가렸다). 툴바엔 쓰다가 바로 집는 것만: 굵게·기울임·코드·크기·색.
        HStack(spacing: 2) {
            textButton("B", weight: .bold, active: state.bold, help: "굵게 (⌘B / **텍스트**)") {
                onAction(.toggleBold)
            }
            textButton("I", italic: true, active: state.italic, help: "기울임 (⌘I / *텍스트*)") {
                onAction(.toggleItalic)
            }
            iconButton(
                "chevron.left.forwardslash.chevron.right",
                active: state.code, help: "인라인 코드 (⌘⇧C / `텍스트`)"
            ) { onAction(.toggleCode) }
            divider
            iconButton("textformat.size.smaller", active: false, help: "글자 작게") {
                onAction(.fontSize(max(Self.minFontSize, state.fontSize - 2)))
            }
            NumberField(
                theme: theme, value: state.fontSize,
                range: Self.minFontSize ... Self.maxFontSize,
                help: "글자 크기 (누르면 전체 선택 · 숫자 입력 후 Enter)"
            ) { onAction(.fontSize($0)) }
            iconButton("textformat.size.larger", active: false, help: "글자 크게") {
                onAction(.fontSize(min(Self.maxFontSize, state.fontSize + 2)))
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
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
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
            help: hex == nil ? "기본색" : "글자색", action: { onAction(.color(hex)) }, label: {
                Circle()
                    .fill(fill)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(theme.sepStrongC))
            }
        )
    }
}

/// 숫자 입력 필드 (글자 크기·줄 간격 공용) — 표시값을 직접 타이핑해 바꾼다.
/// 포커스되면 **전체 선택**되어 바로 숫자를 타이핑하면 값이 교체된다 (요구).
/// Enter나 포커스 이탈 때 커밋하고, ± 버튼으로 바뀐 값(`value`)은 즉시 반영한다.
private struct NumberField: View {
    let theme: MintTheme
    /// 현재 값 — 외부(± 버튼)에서 바뀌면 표시를 갱신한다.
    let value: Double
    let range: ClosedRange<Double>
    let help: String
    let onCommit: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(MintFonts.monoUI(11, .semibold))
            .foregroundStyle(theme.inkC)
            .frame(width: 26)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, now in
                if now {
                    // 포커스되는 순간 필드 에디터의 텍스트를 전체 선택한다 —
                    // 곧바로 숫자를 치면 선택이 교체되어 그 값으로 바뀐다.
                    DispatchQueue.main.async {
                        (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil)
                    }
                } else {
                    commit()
                }
            }
            // 외부 값 변화(± 버튼)는 편집 중이 아닐 때만 표시에 반영한다.
            .onChange(of: value) { _, _ in
                if !focused { text = display(value) }
            }
            .onAppear { text = display(value) }
            .help(help)
    }

    private func display(_ v: Double) -> String {
        String(Int(v.rounded()))
    }

    /// 입력값을 숫자로 파싱해 허용 범위로 자른 뒤 커밋한다. 빈 값·오입력은 되돌린다.
    private func commit() {
        guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            text = display(value)
            return
        }
        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
        text = display(clamped)
        onCommit(clamped)
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
