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
    /// **MINT** — Ternary-Bonsai-27B (Qwen3.5-27B dense, 2비트 삼진 ~1.71bpw), ~8.5GB.
    /// 27B **밀집** 모델이라 토큰마다 전 가중치를 읽는다 — 파일은 셋 중 가장 작지만
    /// 토큰당 대역폭은 MoE(활성 ~3B)보다 크다. 즉 "작다 = 빠르다"가 성립하지 않는
    /// 체급이다 (지연은 MINTBench로 재기 전까지 표기하지 않는다, CLAUDE.md §2-7).
    /// 저장소 config는 VLM(`Qwen3_5ForConditionalGeneration` + vision_config)이지만
    /// `model_type: "qwen3_5"`가 mlx-swift-lm LLMModelFactory에 등록되어 있고,
    /// `Qwen35Model`이 `textConfig`만 취해 언어 모델로 로드한다 (비전 타워는 미사용).
    /// ⚠️ 한국어 지원이 모델 카드에 명시되지 않았고 1.71bpw는 공격적 양자화다 —
    /// 한국어 장편 품질은 **실사용·벤치로 판정 대기** (PLAN §16 열린 질문).
    public static let ternaryBonsai27B = "prism-ml/Ternary-Bonsai-27B-mlx-2bit"
    /// **Basil** — MoE(총 30B, 활성 ~3B: 라우팅 전문가 64개 중 4개 + 공유 1개), ~16.9GB.
    /// 활성 파라미터가 3B대라 디코딩은 3B 밀집 모델급이면서 30B의 이해를 쓴다.
    /// `glm4_moe_lite` 아키텍처는 mlx-swift-lm 3.31.3 LLMModelFactory에 등록되어 있다.
    public static let glm4_7_flash = "mlx-community/GLM-4.7-Flash-4bit"
    /// **Peppermint** — MoE(활성 ~3B), 약 20GB. 저장소 id는 Mac 첫 다운로드 때
    /// 검증되며, 없거나 무거우면 Settings(⌘,)·MINTBench `--model`로 대안 교체.
    public static let qwen3_6_35B_A3B = "mlx-community/Qwen3.6-35B-A3B-4bit"

    // MARK: 대안 (피커 미노출 — Settings 직접 입력·벤치 `--model` 전용)

    /// mlx-swift-lm LLMRegistry에 수록된 검증된 MoE 대안 (활성 ~3B, ~17GB).
    public static let qwen3_30B_A3B = "mlx-community/Qwen3-30B-A3B-4bit"
    /// 경량 대안 (~4.7GB, 2026-08-25 벤치 통과로 슬롯 교체 — 이슈 #63).
    /// A.X-4.0-Light(SKT, Apache-2.0) 한국어 특화 · 순수 어텐션(qwen2)이라
    /// §12 KV 재사용이 온전히 작동(웜 460/461 tok, 웜 TTFC 0.03s). 같은 fixture에서
    /// 이전 경량 후보 Qwen2.5-3B보다 어절 적중률 17% vs 8%.
    public static let ax4Light = "meetLog/A.X-4.0-Light-mlx-4bit"
    /// 가벼운 대안 (~1.9GB).
    public static let qwen2_5_3B = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    /// 가장 가벼운 대안 (~1GB).
    public static let qwen2_5_1_5B = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    public static let all: [String] = [
        ternaryBonsai27B, glm4_7_flash, qwen3_6_35B_A3B,
        qwen3_30B_A3B, ax4Light, qwen2_5_3B, qwen2_5_1_5B,
    ]
}

/// 툴바 모델 스위처에 보여줄 MINT 이름의 프리셋 (에디터 v3 · 라인업 v2).
///
/// 실제 가중치는 `ModelPresets`의 Hugging Face 저장소를 쓰고, UI에는 허브 이름
/// (mint/basil/peppermint)으로 노출한다.
///
/// **왜 nano/air/pro를 버렸나**: 그 이름은 *체급 사다리*(작다→크다 = 빠르다→좋다)를
/// 약속한다. 새 라인업은 8.5·16.9·20GB로 체급이 좁고, 셋 다 27~35B급 이해를 쓴다 —
/// 다른 것은 크기가 아니라 **성격**이다. 특히 MINT는 파일이 가장 작지만 밀집
/// 모델이라 디코딩이 가장 느릴 수 있어, "nano = 가장 빠름"은 사실과 어긋난다.
/// 이름이 거짓 약속을 하지 않도록 사다리를 버리고 허브 이름을 쓴다.
///
/// ⚠️ `detail`은 **아키텍처에서 곧바로 따라오는 사실**만 적는다. 품질·지연 서열은
/// MINTBench 수치가 나오기 전엔 쓰지 않는다 (CLAUDE.md §2-7 측정 없이 튜닝 없음).
public struct ModelChoice: Identifiable, Sendable {
    /// Hugging Face 저장소 id — `CompletionSettings.modelID`와 일치.
    public let id: String
    public let name: String
    public let sizeLabel: String
    public let detail: String
    /// 드롭다운 우측의 대략적 지연 표기 (디자인 v3).
    public let latencyLabel: String

    public static let mint = ModelChoice(
        id: ModelPresets.ternaryBonsai27B, name: "MINT", sizeLabel: "27B·2bit",
        // 2026-08-22 리플레이 벤치(docs/model-lineup-bench.md) — 웜 KV 재사용 0,
        // 웜 TTFC 4.24s, 어절 적중 8%, 제안에 중국자 유입. 기본 부적합 판정 (#40).
        detail: "27B 밀집 · 가장 작은 설치(8.5GB)", latencyLabel: "부적합 판정")
    public static let basil = ModelChoice(
        id: ModelPresets.glm4_7_flash, name: "Basil", sizeLabel: "30B·A3B",
        // 벤치 실측 — 웜 KV 재사용 884/885 tok, 콜드→웜 TTFC 2.34s→0.05s,
        // 어절 적중 25%. MINT 대비 지연·재사용·오염 전 항목 우위 (#40).
        detail: "MoE · 활성 3B · 웜 첫 글자 ~0.05s", latencyLabel: "~50ms 웜")
    public static let peppermint = ModelChoice(
        id: ModelPresets.qwen3_6_35B_A3B, name: "Peppermint", sizeLabel: "35B·A3B",
        detail: "MoE · 가장 큰 이해(20GB)", latencyLabel: "~420ms")

    public static let all: [ModelChoice] = [mint, basil, peppermint]

    public static func matching(_ modelID: String) -> ModelChoice? {
        all.first(where: { $0.id == modelID })
    }
}

/// 추론 엔진(actor)에 넘기는 값 스냅샷.
/// MainActor의 `CompletionSettings`에서 복사해 격리 경계를 넘긴다.
///
/// 기본 모델은 **Basil**(~16.9GB)이다 (#40, 2026-08-22 리플레이 벤치 판정).
/// MINT(8.5GB)는 웜 KV 재사용이 구조적으로 불가(Qwen3.5 하이브리드 MambaCache,
/// PLAN §12)해 웜 TTFC 4.24s — 지연 예산의 ~9배 초과 + 제안에 중국자 유입 +
/// 어절 적중 8%로 기본 부적합이 실측됐다. Basil은 웜 0.05s·재사용 884/885로
/// §12 전략이 온전히 유효하다. 첫 실행 다운로드 부담은 **첫 실행 모델 선택
/// 흐름**(ContentView 시트)으로 완화한다 — 자동 다운로드 전에 사용자가 크기를
/// 보고 고른다 (메타 이슈 #65 Phase 4 #40 결정안 2).
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
    /// 대화 모드의 정지 사다리 확장 (PLAN §10) — 문장 경계 대신 발화 끝(닫는
    /// 따옴표)에서 멈춘다. 설정이 아니라 **요청별 런타임 값** — 컨트롤러가
    /// 커서의 따옴표 상태로 매 요청 결정한다 (UserDefaults 저장 안 함).
    public var stopAtUtteranceEnd: Bool

    public init(
        modelID: String = ModelPresets.glm4_7_flash,
        promptStyle: PromptStyle = .continuation,
        maxTokens: Int = 12,
        temperature: Double = 0.3,
        topP: Double = 0.9,
        maxPromptTokens: Int = 3_072,
        kvCacheEnabled: Bool = true,
        stopAtUtteranceEnd: Bool = false
    ) {
        self.modelID = modelID
        self.promptStyle = promptStyle
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.maxPromptTokens = maxPromptTokens
        self.kvCacheEnabled = kvCacheEnabled
        self.stopAtUtteranceEnd = stopAtUtteranceEnd
    }
}

/// 자동완성 동작 설정 (M3 배선 · M4 Settings UI).
///
/// 모델 ID 수동 입력의 커밋 경계 검증 (이슈 #25 / #65 H2).
/// TextField는 초안만 편집하고, 이 검증을 통과한 값만 changeModel로 간다 —
/// 불완전한 ID가 네트워크 작업(취소·다운로드·preload)을 시작하지 않게.
public enum ModelIDCommit {

    public enum ValidationError: Swift.Error, Equatable, CustomStringConvertible {
        case empty
        case malformed(String)

        public var message: String {
            switch self {
            case .empty:
                return "모델 ID를 입력해 주세요."
            case .malformed(let raw):
                return "'\(raw)'은(는) Hugging Face 형식이 아니에요 — namespace/model"
            }
        }

        public var description: String { message }
    }

    /// 공백 제거 후 namespace/model 형식을 검증해 정제된 ID를 돌려준다.
    public static func validate(_ raw: String) -> Result<String, ValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        if trimmed.contains(where: { $0 == " " || $0 == "\t" }) {
            return .failure(.malformed(trimmed))
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
            !parts[0].isEmpty, !parts[1].isEmpty
        else { return .failure(.malformed(trimmed)) }
        return .success(trimmed)
    }
}

/// 값은 `UserDefaults`에 보존된다. UI(SettingsView)는 이 객체에 바인딩하고,
/// 추론 쪽에는 `parameters` 스냅샷만 넘긴다.
@MainActor
public final class CompletionSettings: ObservableObject {    /// 입력이 멈춘 뒤 제안을 트리거하기까지 대기(ms) — PLAN §5 "수백 ms".
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
        /// 저자 이름은 예측 동작이 아니라 **작품 메타데이터**라 `completion.*`이
        /// 아닌 앱 전역 이름공간(`mint.*`)에 둔다 — 예측 파라미터 스냅샷
        /// (`CompletionParameters`)에도 들어가지 않는다.
        static let authorName = "mint.authorName"
        /// 첫 실행 모델 선택 확인 (#40) — 기본 Basil(16.9GB)의 자동 다운로드 전에
        /// 사용자가 크기를 보고 골랐는지. true가 되면 시작 preload가 허용된다.
        static let initialModelConfirmed = "mint.initialModelConfirmed"
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
    /// 저자 이름(필명) — EPUB 내보내기의 `<dc:creator>`에 실린다. 비워 두면
    /// 저자 정보를 아예 넣지 않는다(빈 저자명보다 없는 편이 낫다).
    @Published public var authorName: String {
        didSet { defaults.set(authorName, forKey: Keys.authorName) }
    }
    /// 본문 기본 글자 크기(pt) — 모든 블록이 이 값에 비례한다(⌘+/⌘−).
    @Published public var editorFontSize: Double {
        didSet {
            let clamped = min(Self.maxFontSize, max(Self.minFontSize, editorFontSize))
            if clamped != editorFontSize { editorFontSize = clamped; return }
            defaults.set(editorFontSize, forKey: Keys.fontSize)
        }
    }
    /// 첫 실행 모델 선택 확인 (#40) — false면 ContentView가 선택 시트를 띄우고
    /// 시작 preload를 보류한다. 사용자가 고르거나 "나중에"를 누르면 true.
    @Published public var initialModelConfirmed: Bool {
        didSet { defaults.set(initialModelConfirmed, forKey: Keys.initialModelConfirmed) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = CompletionParameters()
        self.autocompleteEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        // 기존 보호 규칙 — 저장된 modelID가 있으면 그대로 존중한다. 신규 사용자만
        // 새 기본(Basil)으로 시작한다 (#40).
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
        self.authorName = defaults.string(forKey: Keys.authorName) ?? ""
        // 첫 실행 모델 선택 확인 (#40). 플래그가 전혀 없을 때의 판별:
        // - 모델 ID 저장 이력이 있는 사람 = 업데이트로 들어온 **기존 사용자** —
        //   자기 모델을 이미 알고 있다. 시트 없이 통과시킨다.
        // - 그 외 = **신규 설치** — Basil(16.9GB) 자동 다운로드 전에 선택 시트.
        if let confirmed = defaults.object(forKey: Keys.initialModelConfirmed) as? Bool {
            self.initialModelConfirmed = confirmed
        } else {
            let isExistingUser = defaults.string(forKey: Keys.modelID) != nil
            self.initialModelConfirmed = isExistingUser
            defaults.set(isExistingUser, forKey: Keys.initialModelConfirmed)
        }
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
