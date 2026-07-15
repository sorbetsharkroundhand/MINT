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
    /// air 모델 — MoE(총 30B, 활성 ~3B: 라우팅 전문가 64개 중 4개 + 공유 1개), ~16.9GB.
    /// 활성 파라미터가 3B대라 디코딩은 3B 밀집 모델급이면서 30B의 이해를 쓴다.
    /// `glm4_moe_lite` 아키텍처는 mlx-swift-lm 3.31.3 LLMModelFactory에 등록되어 있다.
    public static let glm4_7_flash = "mlx-community/GLM-4.7-Flash-4bit"
    /// 더 가벼운 대안 (~1.9GB) — PLAN 실험 대안. air가 안 올라가는 기기의 대체재.
    public static let qwen2_5_3B = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    /// 가장 빠른 대안 (~1GB) — PLAN 실험 대안.
    public static let qwen2_5_1_5B = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    public static let all: [String] = [
        qwen3_6_35B_A3B, qwen3_30B_A3B, glm4_7_flash, qwen2_5_3B, qwen2_5_1_5B,
    ]
}

/// 툴바 모델 스위처에 보여줄 MINT 이름의 프리셋 (에디터 v3).
///
/// 실제 가중치는 `ModelPresets`의 Hugging Face 저장소를 쓰고,
/// UI에는 nano/air/pro 라는 제품 이름으로 노출한다.
public struct ModelChoice: Identifiable, Sendable {
    /// Hugging Face 저장소 id — `CompletionSettings.modelID`와 일치.
    public let id: String
    public let name: String
    public let sizeLabel: String
    public let detail: String
    /// 드롭다운 우측의 대략적 지연 표기 (디자인 v3).
    public let latencyLabel: String

    public static let nano = ModelChoice(
        id: ModelPresets.qwen2_5_1_5B, name: "MINT nano", sizeLabel: "1.5B",
        detail: "가장 빠른 응답", latencyLabel: "~60ms")
    /// 지연 표기는 아직 MINTBench로 재지 않았다 (CLAUDE.md §2-7 — 측정 없이 튜닝 없음).
    /// Qwen2.5-3B의 ~180ms는 다른 모델의 수치이므로 물려쓰지 않는다.
    public static let air = ModelChoice(
        id: ModelPresets.glm4_7_flash, name: "MINT air", sizeLabel: "30B·A3B",
        detail: "속도와 품질의 균형", latencyLabel: "측정 전")
    public static let pro = ModelChoice(
        id: ModelPresets.qwen3_6_35B_A3B, name: "MINT pro", sizeLabel: "35B·A3B",
        detail: "가장 자연스러운 문장", latencyLabel: "~420ms")

    public static let all: [ModelChoice] = [nano, air, pro]

    public static func matching(_ modelID: String) -> ModelChoice? {
        all.first(where: { $0.id == modelID })
    }
}

/// 추론 엔진(actor)에 넘기는 값 스냅샷.
/// MainActor의 `CompletionSettings`에서 복사해 격리 경계를 넘긴다.
/// 기본 모델은 첫 실행 부담을 줄이려 가장 가벼운 nano(~1GB)로 둔다 — 예전 기본값인
/// pro(35B·A3B)는 ~20GB라, 앱을 켜자마자 조용히 대용량을 내려받아 사용자를 놀라게 했다.
/// 더 자연스러운 문장을 원하면 툴바 모델 스위처나 Settings(⌘,)에서 air/pro로 올린다.
public struct CompletionParameters: Sendable, Equatable {
    public var modelID: String
    public var promptStyle: PromptStyle
    /// 생성 토큰 상한 — 단어/구 단위 제안 + 저지연 (PLAN §10, ~8–16).
    public var maxTokens: Int
    /// 낮을수록 결정적 — 자동완성은 일관성이 중요.
    public var temperature: Double
    /// 누적 확률 컷 — 하드코딩(0.9)에서 승격, MINTBench로 튜닝 (PLAN §10).
    public var topP: Double
    /// 프리필 토큰 안전 예산 — 문자 창이 넘칠 때만 프롬프트 앞을 잘라낸다
    /// (PLAN §11). UI 미노출, 벤치에서 오버라이드.
    public var maxPromptTokens: Int
    /// 이어쓰기 프리필 KV 재사용 (PLAN §12) — 문제 시 끌 수 있는 킬 스위치.
    public var kvCacheEnabled: Bool

    public init(
        modelID: String = ModelPresets.qwen2_5_1_5B,
        promptStyle: PromptStyle = .continuation,
        maxTokens: Int = 12,
        temperature: Double = 0.3,
        topP: Double = 0.9,
        maxPromptTokens: Int = 3_072,
        kvCacheEnabled: Bool = true
    ) {
        self.modelID = modelID
        self.promptStyle = promptStyle
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.maxPromptTokens = maxPromptTokens
        self.kvCacheEnabled = kvCacheEnabled
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
    /// 커서 앞에서 프롬프트로 쓰는 최대 문자 수 (저널 = Fast 모드, PLAN §10).
    public static let defaultContextCharacters = 1_200
    /// 소설의 컨텍스트 창 상한 (Smart/Story, PLAN §10) — KV 재사용(PLAN §12)이
    /// 있어야 부담 없는 크기라 M5에서 함께 도입한다.
    nonisolated public static let defaultNovelContextCharacters = 4_000
    /// 본문 줄 간격(pt) 기본값 — 줄 사이에 더해지는 여백. 0이면 폰트 기본 높이만.
    public static let defaultLineSpacing = 7.0
    /// 본문 기본 글자 크기(pt) 기본값 — 디자인 기준. 모든 블록이 이 값에 비례한다.
    public static let defaultFontSize = 20.0
    /// 글자 크기 허용 범위 — ⌘+/⌘−·Settings 공용.
    public static let minFontSize = 14.0
    public static let maxFontSize = 30.0

    public static let shared = CompletionSettings()

    private enum Keys {
        static let enabled = "completion.enabled"
        static let modelID = "completion.modelID"
        static let promptStyle = "completion.promptStyle"
        static let debounceMilliseconds = "completion.debounceMilliseconds"
        static let maxTokens = "completion.maxTokens"
        static let temperature = "completion.temperature"
        static let topP = "completion.topP"
        static let contextCharacters = "completion.contextCharacters"
        static let novelContextCharacters = "completion.novelContextCharacters"
        static let kvCache = "completion.kvCache"
        static let lineSpacing = "editor.lineSpacing"
        static let fontSize = "editor.fontSize"
    }

    private let defaults: UserDefaults

    /// 자동완성 마스터 스위치 — 끄면 제안 트리거·모델 로드를 모두 멈춘다.
    @Published public var autocompleteEnabled: Bool {
        didSet { defaults.set(autocompleteEnabled, forKey: Keys.enabled) }
    }
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
    @Published public var topP: Double {
        didSet { defaults.set(topP, forKey: Keys.topP) }
    }
    @Published public var contextCharacters: Int {
        didSet { defaults.set(contextCharacters, forKey: Keys.contextCharacters) }
    }
    /// 소설 종류 문서의 컨텍스트 창 상한 (PLAN §10).
    @Published public var novelContextCharacters: Int {
        didSet { defaults.set(novelContextCharacters, forKey: Keys.novelContextCharacters) }
    }
    /// KV 프리필 재사용 (PLAN §12) — 이상 동작 시 사용자가 끌 수 있는 킬 스위치.
    @Published public var kvCacheEnabled: Bool {
        didSet { defaults.set(kvCacheEnabled, forKey: Keys.kvCache) }
    }
    /// 본문 줄 간격(pt) — 에디터 표시용(추론과 무관). 낮추면 줄이 촘촘해진다.
    @Published public var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) }
    }
    /// 본문 기본 글자 크기(pt) — 모든 블록이 이 값에 비례한다(⌘+/⌘−).
    @Published public var editorFontSize: Double {
        didSet {
            let clamped = min(Self.maxFontSize, max(Self.minFontSize, editorFontSize))
            if clamped != editorFontSize { editorFontSize = clamped; return }
            defaults.set(editorFontSize, forKey: Keys.fontSize)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = CompletionParameters()
        self.autocompleteEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
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
        self.topP = defaults.object(forKey: Keys.topP) as? Double ?? base.topP
        self.contextCharacters =
            defaults.object(forKey: Keys.contextCharacters) as? Int
            ?? Self.defaultContextCharacters
        self.novelContextCharacters =
            defaults.object(forKey: Keys.novelContextCharacters) as? Int
            ?? Self.defaultNovelContextCharacters
        self.kvCacheEnabled =
            defaults.object(forKey: Keys.kvCache) as? Bool ?? base.kvCacheEnabled
        self.lineSpacing =
            defaults.object(forKey: Keys.lineSpacing) as? Double
            ?? Self.defaultLineSpacing
        self.editorFontSize =
            defaults.object(forKey: Keys.fontSize) as? Double
            ?? Self.defaultFontSize
    }

    /// 추론 엔진으로 넘기는 값 스냅샷.
    public var parameters: CompletionParameters {
        CompletionParameters(
            modelID: modelID,
            promptStyle: promptStyle,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            kvCacheEnabled: kvCacheEnabled
        )
    }
}
