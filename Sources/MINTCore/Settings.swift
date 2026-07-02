import Foundation
import SwiftUI

/// 자동완성 프롬프트 방식 (PLAN §9-4 — M2 실험으로 확정).
public enum PromptStyle: String, CaseIterable, Codable, Sendable {
    /// 커서 앞 텍스트를 챗 템플릿 없이 그대로 이어쓴다.
    /// 어절 중간에서도 자연스럽게 이어지므로 자동완성 기본값.
    case continuation
    /// instruct 모델 + 간결 시스템 프롬프트("이어질 내용을 짧게 이어써").
    case instruct

    public var label: String {
        switch self {
        case .continuation: "이어쓰기 (continuation)"
        case .instruct: "지시형 (instruct)"
        }
    }
}

/// 모델 프리셋 (PLAN §3).
public enum ModelPresets {
    /// PLAN 기본 모델 — MoE(활성 ~3B)로 한국어 품질과 지연의 균형.
    /// ⚠️ 약 20GB. 저장소 id는 Mac 첫 다운로드 때 검증되며, 없거나 무거우면
    /// Settings(⌘,) 또는 MINTBench `--model`로 아래 대안으로 교체한다.
    public static let qwen3_6_35B_A3B = "mlx-community/Qwen3.6-35B-A3B-4bit"
    /// mlx-swift-lm LLMRegistry에 수록된 검증된 MoE 대안 (활성 ~3B, ~17GB).
    public static let qwen3_30B_A3B = "mlx-community/Qwen3-30B-A3B-4bit"
    /// 더 가벼운 대안 (~1.9GB) — PLAN 실험 대안.
    public static let qwen2_5_3B = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    /// 가장 빠른 대안 (~1GB) — PLAN 실험 대안.
    public static let qwen2_5_1_5B = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    public static let all: [String] = [
        qwen3_6_35B_A3B, qwen3_30B_A3B, qwen2_5_3B, qwen2_5_1_5B,
    ]
}

/// 추론 엔진(actor)에 넘기는 값 스냅샷.
/// MainActor의 `CompletionSettings`에서 복사해 격리 경계를 넘긴다.
/// 기본값 = PLAN 확정치(§1·§9): Qwen3.6-35B-A3B 4bit · 이어쓰기 · 토큰 상한 12 · 온도 0.3.
public struct CompletionParameters: Sendable, Equatable {
    public var modelID: String
    public var promptStyle: PromptStyle
    /// 생성 토큰 상한 — 단어/구 단위 제안 + 저지연 (PLAN §9-2, ~8–16).
    public var maxTokens: Int
    /// 낮을수록 결정적 — 자동완성은 일관성이 중요.
    public var temperature: Double

    public init(
        modelID: String = ModelPresets.qwen3_6_35B_A3B,
        promptStyle: PromptStyle = .continuation,
        maxTokens: Int = 12,
        temperature: Double = 0.3
    ) {
        self.modelID = modelID
        self.promptStyle = promptStyle
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// 자동완성 동작 설정 (M3 배선 · M4 Settings UI).
///
/// 값은 `UserDefaults`에 보존된다. UI(SettingsView)는 이 객체에 바인딩하고,
/// 추론 쪽에는 `parameters` 스냅샷만 넘긴다.
@MainActor
public final class CompletionSettings: ObservableObject {
    /// 입력이 멈춘 뒤 제안을 트리거하기까지 대기(ms) — PLAN §5 "수백 ms".
    public static let defaultDebounceMilliseconds = 350
    /// 커서 앞에서 프롬프트로 쓰는 최대 문자 수 (현재 문서만, PLAN §1).
    public static let defaultContextCharacters = 1_200

    public static let shared = CompletionSettings()

    private enum Keys {
        static let modelID = "completion.modelID"
        static let promptStyle = "completion.promptStyle"
        static let debounceMilliseconds = "completion.debounceMilliseconds"
        static let maxTokens = "completion.maxTokens"
        static let temperature = "completion.temperature"
        static let contextCharacters = "completion.contextCharacters"
    }

    private let defaults: UserDefaults

    @Published public var modelID: String {
        didSet { defaults.set(modelID, forKey: Keys.modelID) }
    }
    @Published public var promptStyle: PromptStyle {
        didSet { defaults.set(promptStyle.rawValue, forKey: Keys.promptStyle) }
    }
    @Published public var debounceMilliseconds: Int {
        didSet { defaults.set(debounceMilliseconds, forKey: Keys.debounceMilliseconds) }
    }
    @Published public var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: Keys.maxTokens) }
    }
    @Published public var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }
    @Published public var contextCharacters: Int {
        didSet { defaults.set(contextCharacters, forKey: Keys.contextCharacters) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = CompletionParameters()
        self.modelID = defaults.string(forKey: Keys.modelID) ?? base.modelID
        self.promptStyle =
            defaults.string(forKey: Keys.promptStyle)
            .flatMap(PromptStyle.init(rawValue:)) ?? base.promptStyle
        self.debounceMilliseconds =
            defaults.object(forKey: Keys.debounceMilliseconds) as? Int
            ?? Self.defaultDebounceMilliseconds
        self.maxTokens = defaults.object(forKey: Keys.maxTokens) as? Int ?? base.maxTokens
        self.temperature =
            defaults.object(forKey: Keys.temperature) as? Double ?? base.temperature
        self.contextCharacters =
            defaults.object(forKey: Keys.contextCharacters) as? Int
            ?? Self.defaultContextCharacters
    }

    /// 추론 엔진으로 넘기는 값 스냅샷.
    public var parameters: CompletionParameters {
        CompletionParameters(
            modelID: modelID,
            promptStyle: promptStyle,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }
}
