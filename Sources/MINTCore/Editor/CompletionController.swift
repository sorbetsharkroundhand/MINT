import Foundation
import SwiftUI

/// 고스트 텍스트 자동완성 오케스트레이터 (M3, PLAN §4·§5).
///
/// `MintTextView`에서 편집/커서 이벤트를 받아:
/// **디바운스 → 게이트(IME 조합·문단 끝·컨텍스트 유무) → `CompletionEngine` 호출
/// → `suggestion` 발행**. 새 입력·커서 이동·Esc는 제안 폐기 + in-flight 취소.
///
/// 게이트 규칙:
/// - `hasMarkedText`(한글 조합 중)면 절대 트리거하지 않는다 (PLAN §2).
/// - 커서 뒤~문단 끝에 내용이 있으면 트리거하지 않는다 — 고스트를 본문과
///   겹쳐 그리지 않기 위한 MVP 단순화 (docs/m3-ghost-text.md 결정 사항).
@MainActor
public final class CompletionController: ObservableObject {

    /// 모델 준비 상태 — ContentView 상태 바 표시용 (M4).
    public enum EngineState: Equatable {
        case idle
        /// 허브 다운로드 진행률 0...1.
        case downloading(Double)
        /// 다운로드 완료, 가중치 메모리 로드 중.
        case loading
        case ready
        case failed(String)
    }

    /// 현재 고스트로 띄울 제안. nil이면 없음.
    @Published public private(set) var suggestion: String?
    @Published public private(set) var engineState: EngineState = .idle
    /// 최근 제안의 생성 지연(디바운스 제외) — 상태 바 표시용.
    @Published public private(set) var lastLatency: TimeInterval?
    /// 제안 요청이 예약·진행 중인가 — 툴바 칩의 "예측 중" 표시용 (에디터 v3).
    @Published public private(set) var isPredicting = false

    /// 고스트 렌더 뷰로의 직통 알림 — `MintTextView.Coordinator`가 연결한다.
    public var suggestionDidChange: ((String?) -> Void)?

    public let settings: CompletionSettings
    private let engine: CompletionEngine
    private var pendingTask: Task<Void, Never>?
    /// 편집/커서 이벤트마다 증가 — 뒤늦게 도착한 stale 응답을 버리는 기준.
    private var generation = 0
    /// 제안이 발행된 시점의 커서(UTF-16). 커서가 여기서 벗어나면 폐기.
    private var suggestionAnchor: Int?
    /// 대기 중 요청이 예약된 시점의 커서 — 생성 완료 전에 커서가 움직이면 취소.
    private var pendingCaret: Int?
    /// 로드에 실패한 모델 id — 같은 모델로의 재시도 폭주만 막고,
    /// 사용자가 Settings에서 모델을 바꾸면 다시 트리거를 허용한다.
    private var failedModelID: String?
    /// `→` 한 단어 수락 직후의 편집 이벤트에서 남은 고스트를 지우지 않기 위한 플래그.
    private var retainSuggestionOnNextEdit = false

    public init(
        settings: CompletionSettings = .shared,
        engine: CompletionEngine = CompletionEngine()
    ) {
        self.settings = settings
        self.engine = engine
    }

    // MARK: - 엔진 로드

    /// 앱 시작 시 모델을 미리 로드해 모델 상주(PLAN §9-2)로 첫 제안 지연을 지킨다.
    /// 자동완성이 꺼져 있으면 로드하지 않는다 — 켜는 순간 로드한다.
    public func preloadEngine() {
        guard settings.autocompleteEnabled else { return }
        switch engineState {
        case .idle, .failed: break
        default: return
        }
        engineState = .downloading(0)
        let parameters = settings.parameters
        // 로드가 끝날 때까지 self를 붙잡는다(수명 유한) — 상태 갱신이 목적이므로 의도적.
        Task { [engine] in
            do {
                try await engine.preload(parameters: parameters) { fraction in
                    Task { @MainActor [weak self] in
                        self?.noteLoadProgress(fraction)
                    }
                }
                self.markEngineReady()
            } catch is CancellationError {
                // 모델 교체 등으로 이 로드가 취소됨 — 새 로드가 상태를 이어받는다.
            } catch {
                self.markEngineFailed(error, modelID: parameters.modelID)
            }
        }
    }

    /// 로드 실패 후 재시도 (모델 id를 바꾼 뒤 등).
    public func retryEngineLoad() {
        engineState = .idle
        failedModelID = nil
        preloadEngine()
    }

    /// 모델 스위처에서 모델을 바꿨다 — 고스트 폐기 후 새 모델을 즉시 로드.
    public func modelDidChange() {
        invalidate()
        engineState = .idle
        failedModelID = nil
        preloadEngine()
    }

    /// 자동완성 마스터 스위치 토글 (모델 드롭다운의 스위치).
    /// 끄면 진행 중인 제안까지 즉시 폐기하고, 켜면 모델을 로드한다.
    public func setAutocompleteEnabled(_ enabled: Bool) {
        guard settings.autocompleteEnabled != enabled else { return }
        settings.autocompleteEnabled = enabled
        if enabled {
            preloadEngine()
        } else {
            invalidate()
        }
    }

    private func noteLoadProgress(_ fraction: Double) {
        switch engineState {
        case .ready: return
        default: engineState = fraction >= 1 ? .loading : .downloading(fraction)
        }
    }

    private func markEngineReady() {
        engineState = .ready
        failedModelID = nil
    }

    private func markEngineFailed(_ error: Error, modelID: String) {
        // 그 사이 다른 모델로 바뀌었다면 이 실패는 이미 낡은 정보다.
        guard settings.modelID == modelID else { return }
        engineState = .failed(error.localizedDescription)
        failedModelID = modelID
    }

    // MARK: - 에디터 이벤트

    /// 텍스트가 변했다 — 기존 고스트/작업 폐기 후, 게이트를 통과하면 새 제안 예약.
    public func noteEdit(
        prefix: String,
        caretLocation: Int,
        isComposing: Bool,
        caretAtParagraphEnd: Bool
    ) {
        // `→` 한 단어 수락이 만든 편집 — 남은 고스트를 유지하고 새 요청도 걸지 않는다.
        if retainSuggestionOnNextEdit {
            retainSuggestionOnNextEdit = false
            if suggestion != nil {
                suggestionAnchor = caretLocation
                return
            }
            // 제안을 다 소진했다 — 아래 일반 경로로 다음 제안을 예약한다.
        }

        invalidate()  // 편집 즉시 고스트 제거 + in-flight 취소 (PLAN §5)

        guard settings.autocompleteEnabled else { return }  // 마스터 스위치 꺼짐
        guard !isComposing else { return }  // 한글 IME 조합 중 — 트리거 금지 (PLAN §2)
        guard caretAtParagraphEnd else { return }
        // 같은 모델로 실패했으면 재시도 폭주 방지. 모델을 바꿨으면 다시 허용.
        if case .failed = engineState, settings.modelID == failedModelID { return }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }  // 컨텍스트가 너무 빈약하면 스킵

        let expected = generation
        let parameters = settings.parameters
        let debounce = Duration.milliseconds(settings.debounceMilliseconds)

        isPredicting = true
        pendingCaret = caretLocation
        pendingTask = Task { [weak self] in
            // 입력이 멈출 때까지 대기 — 그 사이 새 입력이 오면 이 태스크가 취소된다.
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            await self.runCompletion(
                prefix: prefix,
                caretLocation: caretLocation,
                parameters: parameters,
                expected: expected
            )
        }
    }

    /// 커서/선택이 움직였다 — 제안(또는 대기 중 요청)의 위치를 벗어나면 폐기.
    ///
    /// 타이핑도 커서를 움직이지만, 그 경우 `noteEdit`가 같은 커서 위치로
    /// 재예약하므로(위치 일치 → no-op) 알림 순서와 무관하게 안전하다.
    public func noteSelectionChange(caretLocation: Int) {
        if suggestion != nil {
            if suggestionAnchor != caretLocation { invalidate() }
        } else if pendingTask != nil {
            if pendingCaret != caretLocation { invalidate() }
        }
    }

    // MARK: - 수락 / 거부

    public var hasSuggestion: Bool { suggestion != nil }

    /// `Tab` 수락 — 뷰가 본문에 삽입할 텍스트를 반환. 제안이 없으면 nil.
    public func acceptSuggestion() -> String? {
        guard let text = suggestion, !text.isEmpty else { return nil }
        invalidate()
        return text
    }

    /// `→` 한 단어 수락 (에디터 v3) — 제안의 선행 공백+첫 어절만 반환하고,
    /// 나머지는 고스트로 남긴다. 뷰는 반환값을 본문에 삽입한다.
    ///
    /// `insertionLocation`은 삽입 직전 커서(UTF-16). 삽입이 만들 편집·커서
    /// 이벤트에서 남은 고스트가 폐기되지 않도록 앵커를 미리 옮겨 둔다.
    public func acceptWord(insertionLocation: Int) -> String? {
        guard let text = suggestion, !text.isEmpty else { return nil }
        var rest = Substring(text)
        var word = ""
        while let first = rest.first, first.isWhitespace {
            word.append(first)
            rest = rest.dropFirst()
        }
        while let first = rest.first, !first.isWhitespace {
            word.append(first)
            rest = rest.dropFirst()
        }
        guard !word.isEmpty else { return nil }

        let remainder = String(rest)
        retainSuggestionOnNextEdit = true
        suggestionAnchor = insertionLocation + (word as NSString).length
        suggestion = remainder.isEmpty ? nil : remainder
        suggestionDidChange?(suggestion)
        return word
    }

    /// `Esc`·포커스 이탈·외부 텍스트 교체 — 고스트 폐기 + in-flight 취소.
    public func dismissSuggestion() {
        invalidate()
    }

    // MARK: - 내부

    private func invalidate() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        pendingCaret = nil
        suggestionAnchor = nil
        isPredicting = false
        if suggestion != nil {
            suggestion = nil
            suggestionDidChange?(nil)
        }
    }

    private func runCompletion(
        prefix: String,
        caretLocation: Int,
        parameters: CompletionParameters,
        expected: Int
    ) async {
        // 이 요청이 아직 최신일 때만 "예측 중"을 끈다 — 낡았다면 새 요청이 관리한다.
        defer { if expected == generation { isPredicting = false } }
        do {
            let completion = try await engine.complete(prefix: prefix, parameters: parameters) {
                fraction in
                Task { @MainActor [weak self] in
                    self?.noteLoadProgress(fraction)
                }
            }
            guard expected == generation else { return }  // 그 사이 편집됨 — stale 폐기
            markEngineReady()
            lastLatency = completion.totalTime
            guard !completion.text.isEmpty else { return }
            suggestion = completion.text
            suggestionAnchor = caretLocation
            suggestionDidChange?(completion.text)
        } catch is CancellationError {
            // 새 입력으로 취소됨 — 정상 흐름.
        } catch {
            guard expected == generation else { return }
            markEngineFailed(error, modelID: parameters.modelID)
        }
    }
}
