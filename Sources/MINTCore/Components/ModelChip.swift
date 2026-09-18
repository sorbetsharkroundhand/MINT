import SwiftUI

/// Product-facing toolbar presentation for local completion.
///
/// The writing surface describes the capability and its state. Exact model identifiers,
/// quantization, architecture and tuning controls belong in Settings.
enum ModelChipPresentation {
    static func toolbarLabel(
        modelID _: String,
        stateText: String,
        compact: Bool
    ) -> String? {
        compact ? nil : "자동완성 · \(stateText)"
    }
}

/// Compact autocomplete status + quick controls.
///
/// Model selection/download details intentionally live in Settings so the primary writing
/// chrome does not read like an inference dashboard.
struct ModelChip: View {
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme
    var compact = false

    @Environment(\.openSettings) private var openSettings
    @State private var menuOpen = false
    @State private var chipHovered = false

    var body: some View {
        Button {
            menuOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                if completion.isPredicting {
                    PulsingDots(color: theme.blueC)
                } else {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                if let label = ModelChipPresentation.toolbarLabel(
                    modelID: settings.modelID,
                    stateText: stateText,
                    compact: compact
                ) {
                    Text(label)
                        .font(MintFonts.monoUI(11, .semibold))
                        .foregroundStyle(theme.ink2C)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.ink2C)
                }
                if !compact {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.ink3C)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, compact ? 9 : 11)
            .background(
                RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                    .fill(chipHovered ? theme.hoverC : theme.chipC)
            )
            .focusedValue(\.hasMintEditor, true)
            .overlay(
                RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                    .strokeBorder(theme.chipBorderC)
            )
        }
        .buttonStyle(.plain)
        .onHover { chipHovered = $0 }
        .accessibilityLabel("자동완성")
        .accessibilityValue(engineStateAXValue)
        .popover(isPresented: $menuOpen, arrowEdge: .bottom) {
            dropdown
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: MintRadius.sm, style: .continuous)
                        .fill(theme.activeBgC)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.novelC)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("자동완성")
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(stateDescription)
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink3C)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            theme.sepC.frame(height: 1)
            autocompleteToggle
            theme.sepC.frame(height: 1)
            predictionLengthRow

            if case .failed = completion.engineState {
                theme.sepC.frame(height: 1)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("자동완성을 준비하지 못했어요")
                            .font(MintFonts.uiFont(12, .semibold))
                            .foregroundStyle(theme.dangerC)
                        Text("글쓰기는 계속할 수 있습니다.")
                            .font(MintFonts.uiFont(10.5))
                            .foregroundStyle(theme.ink3C)
                    }
                    Spacer(minLength: 0)
                    Button("다시 시도") {
                        completion.retryEngineLoad()
                    }
                    .buttonStyle(.link)
                    .font(MintFonts.uiFont(11, .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            theme.sepC.frame(height: 1)
            Button {
                menuOpen = false
                openSettings()
            } label: {
                HStack(spacing: 10) {
                    Label("모델 및 고급 설정", systemImage: "slider.horizontal.3")
                        .font(MintFonts.uiFont(12, .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.ink3C)
                }
                .foregroundStyle(theme.ink2C)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("설정 창 열기")
        }
        .frame(width: 280)
    }

    private var predictionLengthRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("제안 길이")
                    .font(MintFonts.uiFont(12, .semibold))
                    .foregroundStyle(theme.inkC)
                Text("한 번에 이어 쓰는 분량")
                    .font(MintFonts.uiFont(10.5))
                    .foregroundStyle(theme.ink3C)
            }
            Spacer(minLength: 0)
            StepIconButton(systemName: "minus", theme: theme, help: "짧게") {
                settings.maxTokens = max(4, settings.maxTokens - 2)
            }
            Text("\(settings.maxTokens)")
                .font(MintFonts.monoUI(11, .semibold))
                .foregroundStyle(theme.inkC)
                .frame(minWidth: 22)
            StepIconButton(systemName: "plus", theme: theme, help: "길게") {
                settings.maxTokens = min(32, settings.maxTokens + 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var autocompleteToggle: some View {
        Button {
            completion.setAutocompleteEnabled(!settings.autocompleteEnabled)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("자동완성")
                        .font(MintFonts.uiFont(12, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(settings.autocompleteEnabled
                        ? "멈추면 다음 문장을 조용히 제안"
                        : "꺼짐 — 모델 없이 글쓰기")
                        .font(MintFonts.uiFont(10.5))
                        .foregroundStyle(theme.ink3C)
                }
                Spacer(minLength: 0)
                GlassSwitch(isOn: settings.autocompleteEnabled, theme: theme)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("자동완성 켜기/끄기")
        .accessibilityLabel("자동완성")
        .accessibilityValue(settings.autocompleteEnabled ? "켜짐" : "꺼짐")
    }

    private var stateText: String {
        if !settings.autocompleteEnabled { return "꺼짐" }
        if completion.isPredicting { return "예측 중" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading: return "준비 중"
        case .loading: return "준비 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "대기"
        case .failed: return "오류"
        }
    }

    private var stateDescription: String {
        switch stateText {
        case "꺼짐": "필요할 때 다시 켤 수 있어요."
        case "예측 중": "현재 문맥에 맞는 다음 문장을 만들고 있어요."
        case "준비 중": "로컬 자동완성을 준비하고 있어요."
        case "제안 준비됨": "Tab 또는 → 키로 제안을 받을 수 있어요."
        case "오류": "자동완성만 사용할 수 없고 글쓰기는 계속됩니다."
        default: "글을 멈추면 필요한 순간에만 제안합니다."
        }
    }

    private var dotColor: Color {
        if !settings.autocompleteEnabled { return theme.ink3C }
        return switch completion.engineState {
        case .idle: theme.ink3C
        case .downloading, .loading: theme.warningC
        case .ready: completion.suggestion != nil ? theme.inkC : theme.ink3C
        case .failed: theme.dangerC
        }
    }

    private var engineStateAXValue: String {
        if !settings.autocompleteEnabled { return "자동완성 꺼짐" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading(let fraction):
            return String(format: "준비 %.0f%%", fraction * 100)
        case .loading: return "자동완성 준비 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "준비됨"
        case .failed: return "오류"
        }
    }
}

private struct StepIconButton: View {
    let systemName: String
    let theme: MintTheme
    let help: String
    let action: () -> Void

    var body: some View {
        HoverIconButton(
            theme: theme, help: help,
            contentWidth: 22, contentHeight: 22, cornerRadius: MintRadius.sm,
            action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
    }
}
