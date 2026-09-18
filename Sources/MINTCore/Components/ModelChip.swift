import SwiftUI

/// 모델 상태 칩 + 디자인형 드롭다운 — ContentView에서 파일 분리 (이슈 #61 PR5).
/// 모델 상태 칩 + 디자인형 드롭다운 (264px 카드, mint/basil/peppermint).
struct ModelChip: View {
    @ObservedObject var completion: CompletionController
    @ObservedObject var settings: CompletionSettings
    let theme: MintTheme

    @Environment(\.openSettings) private var openSettings
    @State private var menuOpen = false
    @State private var hoveredID: String?
    @State private var chipHovered = false
    /// 모델 가중치 프리페치 — 드롭다운 행의 다운로드 버튼·진행률 담당.
    @StateObject private var downloads = ModelDownloadManager()

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
                        .accessibilityHidden(true)  // 의미는 아래 AX 값이 말한다 (#59-3).
                }
                Text(statusLabel)
                    .font(MintFonts.monoUI(11, .semibold))
                    .foregroundStyle(theme.ink2C)
                Text("▼")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.ink3C)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("자동완성")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Text("글을 멈추면 다음 내용을 이 Mac에서 제안합니다.")
                    .font(MintFonts.uiFont(10.5))
                    .foregroundStyle(theme.ink3C)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 10)
            theme.sepC.frame(height: 1)
            VStack(spacing: 0) {
                ForEach(ModelChoice.all) { choice in
                    row(choice)
                }
                if ModelChoice.matching(settings.modelID) == nil {
                    customRow
                }
                if case .failed = completion.engineState {
                    theme.sepC.frame(height: 1).padding(.vertical, 4)
                    Button("모델 다시 로드") { completion.retryEngineLoad() }
                        .buttonStyle(.plain)
                        .font(MintFonts.uiFont(12, .medium))
                        .foregroundStyle(theme.blueC)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .padding(6)
            downloadFailureFooter
            theme.sepC.frame(height: 1)
            autocompleteToggle
            theme.sepC.frame(height: 1)
            predictionLengthRow
            theme.sepC.frame(height: 1)
            advancedModelSettingsButton
        }
        .frame(width: 292)
        // 열 때마다 로컬 캐시를 다시 확인한다 — 엔진 로드로 받아진 모델도 반영.
        .onAppear { downloads.refresh(ModelChoice.all.map(\.id)) }
    }

    /// 예측 길이(최대 토큰) 조절 — SettingsView(⌘,)의 스테퍼와 같은 값·범위.
    /// 값은 다음 제안부터 적용된다 (parameters 스냅샷 경계).
    private var predictionLengthRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("예측 길이")
                    .font(MintFonts.uiFont(13, .semibold))
                    .foregroundStyle(theme.inkC)
                Text("한 번에 제안하는 최대 토큰")
                    .font(MintFonts.uiFont(11.5))
                    .foregroundStyle(theme.ink2C)
            }
            Spacer(minLength: 0)
            StepIconButton(systemName: "minus", theme: theme, help: "짧게") {
                settings.maxTokens = max(4, settings.maxTokens - 2)
            }
            Text("\(settings.maxTokens)")
                .font(MintFonts.monoUI(12, .semibold))
                .foregroundStyle(theme.inkC)
                .frame(minWidth: 22)
            StepIconButton(systemName: "plus", theme: theme, help: "길게") {
                settings.maxTokens = min(32, settings.maxTokens + 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    /// 드롭다운 하단의 자동완성 마스터 스위치 — 끄면 제안·모델 로드 중단.
    private var autocompleteToggle: some View {
        Button {
            completion.setAutocompleteEnabled(!settings.autocompleteEnabled)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("자동완성")
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(settings.autocompleteEnabled
                        ? "글을 멈추면 이어질 내용을 제안해요"
                        : "꺼짐 — 제안하지 않아요")
                        .font(MintFonts.uiFont(11.5))
                        .foregroundStyle(theme.ink2C)
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
        .accessibilityLabel(Text("자동완성"))
    }

    /// 모델 행 — **실제 Button**이라 Tab 포커스·Enter 활성화·VO 버튼 역할을 갖는다
    /// (#25). 다운로드 액세서리는 trailing overlay의 독립 Button으로 올려,
    /// 버튼 중첩 충돌 없이(overlay가 히트를 먼저 가져간다) 두 동작을 분리한다.
    /// 실패 원인은 AX value로 읽혀 색·help에만 의존하지 않는다.
    private func row(_ choice: ModelChoice) -> some View {
        let selected = settings.modelID == choice.id
        return Button {
            pick(choice.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name)
                        .font(MintFonts.uiFont(13, .semibold))
                        .foregroundStyle(theme.inkC)
                    Text(Self.userFacingSummary(for: choice))
                        .font(MintFonts.uiFont(11))
                        .foregroundStyle(theme.ink2C)
                }
                Spacer(minLength: 0)
                Text(selected ? "✓" : "")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.blueC)
                    .frame(width: 16)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                    .fill(selected
                        ? theme.activeBgC
                        : (hoveredID == choice.id ? theme.hoverC : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? choice.id : nil }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(choice.name) 모델"))
        .accessibilityValue(Text(selected ? "선택됨" : Self.userFacingSummary(for: choice)))
        .accessibilityHint(Text("이 모델로 전환"))
        .overlay(alignment: .trailing) {
            downloadAccessory(choice)
                .padding(.trailing, 30)   // ✓ 칼럼 폭만큼 비켜난다
                .padding(.leading, 8)
        }
    }

    /// 다운로드 실패 원인 가시 푸터 (#25 완료 조건 3) — help 뒤에 숨기지 않는다.
    @ViewBuilder
    private var downloadFailureFooter: some View {
        let failure = downloads.states.first { state in
            if case .failed = state.value { return true }
            return false
        }
        if let failure {
            if case .failed(let message) = failure.value {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ModelChip.displayName(failure.key)) 다운로드 실패")
                        .font(MintFonts.uiFont(11, .semibold))
                        .foregroundStyle(theme.dangerC)
                    Text(Self.recoveryAdvice(for: message))
                        .font(MintFonts.uiFont(10.5))
                        .foregroundStyle(theme.ink2C)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.pillC)
            }
        }
    }

    /// 오류 메시지 → 다음 행동 제안 (#25). 결정적 매핑 — 네트워크/디스크/형식.
    static func recoveryAdvice(for message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("network") || lowered.contains("인터넷") || lowered.contains("연결") {
            return "네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        }
        if lowered.contains("disk") || lowered.contains("space") || lowered.contains("공간")
            || lowered.contains("no space")
        {
            return "디스크 여유 공간을 확보한 뒤 다시 시도해 주세요."
        }
        if lowered.contains("404") || lowered.contains("not found") || lowered.contains("찾을 수 없") {
            return "저장소 id가 맞는지 확인해 주세요 (설정에서 직접 입력한 경우 오타 확인)."
        }
        return "잠시 후 다시 시도해 주세요."
    }

    /// 행 우측의 다운로드 상태 — 안 받았으면 받기 버튼, 진행 중엔 %, 받았으면 체크.
    /// 미리 받아 두면 그 모델로 전환할 때 다운로드 없이 바로 로드된다.
    @ViewBuilder
    private func downloadAccessory(_ choice: ModelChoice) -> some View {
        switch downloads.states[choice.id] {
        case .downloading(let fraction):
            Button {
                downloads.cancel(choice.id)
            } label: {
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(MintFonts.monoUI(10, .semibold))
                    .foregroundStyle(theme.blueC)
            }
            .buttonStyle(.plain)
            .help("다운로드 중 — 누르면 취소")
                .accessibilityLabel(Text("다운로드 취소"))
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink3C)
                .help("다운로드됨 — 전환 시 바로 로드")
                    .accessibilityLabel(Text("다운로드됨 — 이 모델로 전환"))
        case .failed(let message):
            Button {
                downloads.download(choice.id)
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink2C)
            }
            .buttonStyle(.plain)
            .help("실패 — 다시 시도 (\(message))")
                    .accessibilityLabel(Text("모델 다운로드 실패 — 다시 시도"))
                    .accessibilityValue(Text(message))
        case .notDownloaded, .none:
            Button {
                downloads.download(choice.id)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.blueC)
            }
            .buttonStyle(.plain)
            .help("모델 미리 받기 (\(choice.sizeLabel))")
                    .accessibilityLabel(Text("\(choice.name) 모델 미리 받기"))
        }
    }

    /// 사용자 지정 저장소 ID는 primary writing surface에 그대로 노출하지 않는다.
    /// 정확한 저장소 ID와 생성 파라미터는 Settings의 고급 모델 영역에서 관리한다.
    private var customRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("사용자 지정 모델")
                    .font(MintFonts.uiFont(12, .semibold))
                    .foregroundStyle(theme.inkC)
                Text("고급 설정에서 관리")
                    .font(MintFonts.uiFont(10.5))
                    .foregroundStyle(theme.ink3C)
            }
            Spacer(minLength: 0)
            Text("✓")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.blueC)
                .frame(width: 16)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: MintRadius.md, style: .continuous)
                .fill(theme.activeBgC)
        )
    }

    private var advancedModelSettingsButton: some View {
        Button {
            menuOpen = false
            openSettings()
        } label: {
            HStack {
                Label("고급 모델 설정", systemImage: "gearshape")
                    .font(MintFonts.uiFont(11.5, .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.ink2C)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("모델 ID와 생성 파라미터 설정 열기")
    }

    private func pick(_ id: String) {
        menuOpen = false
        guard id != settings.modelID else { return }
        settings.modelID = id
        completion.modelDidChange()
    }

    private var statusLabel: String {
        "자동완성 · \(stateText)"
    }

    private var stateText: String {
        if !settings.autocompleteEnabled { return "꺼짐" }
        if completion.isPredicting { return "예측 중" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading(let fraction): return String(format: "다운로드 %.0f%%", fraction * 100)
        case .loading: return "로드 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "대기"
        case .failed: return "오류"
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

    /// 상태점의 의미를 텍스트로 — 색만 보고 판단하지 않게 (#59-3).
    fileprivate var engineStateAXValue: String {
        if !settings.autocompleteEnabled { return "자동완성 꺼짐" }
        switch completion.engineState {
        case .idle: return "대기"
        case .downloading(let fraction):
            return String(format: "다운로드 %.0f%%", fraction * 100)
        case .loading: return "모델 로드 중"
        case .ready: return completion.suggestion != nil ? "제안 준비됨" : "준비됨"
        case .failed: return "오류"
        }
    }

    static func userFacingSummary(for choice: ModelChoice) -> String {
        switch choice.id {
        case ModelPresets.ternaryBonsai27B:
            "8.5GB · 실험적"
        case ModelPresets.glm4_7_flash:
            "16.9GB · 기본"
        case ModelPresets.qwen3_6_35B_A3B:
            "20GB · 큰 모델"
        default:
            "로컬 모델"
        }
    }

    static func displayName(_ modelID: String) -> String {
        ModelChoice.matching(modelID)?.name ?? "사용자 지정 모델"
    }

    static func shortID(_ modelID: String) -> String {
        modelID.components(separatedBy: "/").last ?? modelID
    }
}

/// 드롭다운의 작은 ± 스텝 버튼 — HoverIconButton 위임 (#61 PR3).
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
