import SwiftUI

/// 자동완성 설정 화면 (M4) — 앱 메뉴/⌘,의 Settings 씬에서 연다.
///
/// `CompletionSettings`(UserDefaults 보존)에 바인딩된다. 모델·프롬프트 방식
/// 변경은 **다음 제안부터** 적용되며, 새 모델은 첫 사용 시 다운로드된다.
public struct SettingsView: View {
    @ObservedObject private var settings: CompletionSettings

    public init(settings: CompletionSettings = .shared) {
        self._settings = ObservedObject(wrappedValue: settings)
    }

    public var body: some View {
        Form {
            Section("모델") {
                TextField("Hugging Face 저장소 id", text: $settings.modelID)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Menu("프리셋에서 선택") {
                    ForEach(ModelPresets.all, id: \.self) { preset in
                        Button(preset) { settings.modelID = preset }
                    }
                }
                Text("모델 변경은 다음 제안부터 적용 — 새 모델은 첫 사용 시 다운로드돼요(수 GB).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("제안") {
                Toggle("자동완성 사용", isOn: $settings.autocompleteEnabled)

                Picker("프롬프트 방식", selection: $settings.promptStyle) {
                    ForEach(PromptStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Stepper(
                    "디바운스: \(settings.debounceMilliseconds)ms",
                    value: $settings.debounceMilliseconds,
                    in: 150...1_000,
                    step: 50
                )
                Stepper(
                    "최대 토큰: \(settings.maxTokens)",
                    value: $settings.maxTokens,
                    in: 4...32
                )
                VStack(alignment: .leading) {
                    Slider(value: $settings.temperature, in: 0...1) {
                        Text(String(format: "온도: %.2f", settings.temperature))
                    }
                    Text("낮을수록 일관된 제안, 높을수록 다양한 제안.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("에디터") {
                Stepper(
                    "줄 간격: \(Int(settings.lineSpacing.rounded()))pt",
                    value: $settings.lineSpacing,
                    in: 0...20,
                    step: 1
                )
                Text("줄 사이 여백을 조절해요 — 낮추면 촘촘하게, 높이면 시원하게.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView(settings: CompletionSettings())
}
