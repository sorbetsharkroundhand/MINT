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

    // MARK: 긴 문단 나누기 (docs/editor-paragraph-split.md)

    /// 현재 문서의 긴 산문 문단 감지 결과 — 툴바의 조용한 표시가 관찰한다.
    /// `count > 0`일 때만 표시가 나타난다(대상 없으면 아무 UI도 없음).
    /// 문서 로드 때 1회 계산 → 키 입력 경로에 O(문서)를 넣지 않는다.
    @Published public private(set) var longParagraph: LongParagraphInfo = .none

    public struct LongParagraphInfo: Equatable, Sendable {
        public var count: Int
        public var maxLength: Int
        public var typicalLength: Int
        public static let none = LongParagraphInfo(count: 0, maxLength: 0, typicalLength: 0)
        /// "보통 문단의 N배" — 0으로 나눔 방지, 최소 1배.
        public var ratio: Int { typicalLength > 0 ? max(1, maxLength / typicalLength) : 0 }
    }

    /// 에디터가 배선하는 감지·실행 다리 (`knowledgeProvider`와 같은 패턴).
    public var detectLongParagraphs: (() -> LongParagraphInfo)?
    /// 실행 → 나눈 문단 수. 성공 후 감지를 갱신한다.
    public var splitLongParagraphs: (() -> Int)?

    /// 감지를 다시 계산해 발행한다 — 문서 로드·분할 직후 에디터가 호출.
    public func refreshLongParagraphDetection() {
        longParagraph = detectLongParagraphs?() ?? .none
    }

    /// 툴바의 "문단 나누기" 실행 → 감지 갱신(대상이 사라져 표시가 숨는다).
    public func performLongParagraphSplit() {
        _ = splitLongParagraphs?()
        refreshLongParagraphDetection()
    }

    public let settings: CompletionSettings
    private let engine: CompletionEngine

    /// 활성 문서 스냅샷 공급자 — ContentView가 1회 배선한다. 예측 직전에 pull해
    /// 제목·장르·인물 카드를 조립기에 넘긴다 (PLAN §10). 푸시(onChange) 대신
    /// pull인 이유: 본문이 큰 저널에서 매 키 입력마다 Equatable 비교를 하지 않는다.
    public var documentContextProvider: (() -> DocumentContext?)?

    /// 지식 스냅샷 공급자 (M6, PLAN §11) — 인덱서가 발행한 인메모리 값만 pull.
    /// 활성 문서와의 일치 확인은 배선부(ContentView)의 몫이다.
    public var knowledgeProvider: (() -> KnowledgeSnapshot?)?

    /// 종류별 컨텍스트 창 상한 — 소설은 넓게 (PLAN §10 Smart/Story 예산).
    /// 에디터(BlockTextView)가 prefix 추출 한도로 읽는다.
    public var effectiveContextCharacters: Int {
        documentContextProvider?()?.kind == .novel
            ? settings.novelContextCharacters
            : settings.contextCharacters
    }
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
    /// 마지막 편집의 예측 창 (prefix·커서) — KV 프리웜이 **예측과 같은 창**으로
    /// 조립하기 위한 기록 (PLAN §12-1). 편집이 5s+ 멈춘 유휴에 패스가 돌므로,
    /// 이 값이 곧 "다음 예측이 쓸 창"이다.
    private var lastWindow: (prefix: String, caret: Int)?
    /// 진행 중 프리웜 — 타이핑 재개 시 즉시 취소된다 (예측이 항상 이긴다, CLAUDE.md §2-6).
    private var prewarmTask: Task<Void, Never>?

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
        // 조합 확정 이후의 창만 기록 — 프리웜용. 문단 끝 게이트보다 앞에 두는
        // 이유: 문단 중간을 고치다 멈춰도 그 자리가 다음 예측의 창이다.
        lastWindow = (prefix, caretLocation)
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

    // MARK: - A+B 프리픽스 KV 프리웜 (M6, PLAN §12-1)

    /// 문서 전환 — 이전 문서의 창을 버린다. 남겨 두면 새 문서의 헤더에 남의
    /// 문서 본문을 붙인 쓰레기 프롬프트를 프리웜하게 된다 (ContentView가 배선).
    public func noteDocumentSwitch() {
        lastWindow = nil
        prewarmTask?.cancel()
        prewarmTask = nil
    }

    /// 이해 패스 완주 직후(인덱서 신호) — 새 지식이 반영된 프롬프트로 KV를
    /// 미리 데운다. 지식 세대가 바뀌면 헤더 첫 글자부터 LCP가 죽어 다음 예측이
    /// 통째로 콜드인데, 그 프리필을 유휴 시간으로 옮기는 것이 이 호출이다 —
    /// "백그라운드가 이해를 준비하고, 예측은 조립만 한다" (CLAUDE.md §2-2).
    ///
    /// 조립은 `runCompletion`과 **완전히 같은 경로** — 프리웜된 캐시가 다음
    /// 예측과 어긋날 방법을 없앤다. 지식이 안 바뀌었으면 LCP가 전부라 1토큰
    /// 프리필로 끝난다 (호출이 공짜에 가깝다).
    public func prewarmPrefix() {
        prewarmTask?.cancel()
        prewarmTask = nil
        guard settings.autocompleteEnabled else { return }
        guard case .ready = engineState else { return }  // 로드 유발 금지
        // 예측이 걸려 있으면 그쪽이 데운다 — 엔진 경합을 만들지 않는다.
        guard !isPredicting else { return }
        guard let (prefix, caret) = lastWindow else { return }
        let parameters = settings.parameters
        guard parameters.promptStyle == .continuation, parameters.kvCacheEnabled
        else { return }  // instruct는 KV 재사용이 없다 (PLAN §12 M5 범위)
        // 열 시민의식 — 프리웜은 최적화일 뿐, 뜨거운 기기에서 할 일이 아니다.
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return
        default: break
        }

        let prompt = ContextAssembler.assemble(
            prefix: prefix,
            document: documentContextProvider?(),
            knowledge: knowledgeProvider?(),
            prefixStartUTF16: max(0, caret - (prefix as NSString).length),
            style: .continuation
        )
        prewarmTask = Task { [engine] in
            // 취소는 **시작 전**에만 듣는다. 시작한 프리필을 중간에 취소하면
            // 엔진이 캐시를 통째로 버려(abandon) 웜 캐시까지 잃는다 — 이 프리필은
            // 다음 예측이 어차피 해야 할 일이라, 완주가 취소보다 항상 이득이다.
            // (프리필 자체도 청크 단위라 중간 인터럽트가 안 된다 — PLAN §9와 동일.)
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                await engine.prewarm(prompt: prompt, parameters: parameters)
            }.value
        }
    }

    // MARK: - 폴더 이름 생성 (사이드바 DnD)

    /// AI 이름 생성이 진행 중인 폴더들 — 사이드바 행의 로딩 점 표시용.
    @Published public private(set) var namingFolderIDs: Set<UUID> = []

    /// 자동 생성 폴더("새 폴더")의 이름을 멤버 문서 내용에서 지어 붙인다.
    ///
    /// 엔진을 쓸 수 없으면(자동완성 꺼짐·로드 실패) 조용히 기본 이름을 유지한다 —
    /// 폴더 명명이 대용량 모델 다운로드를 유발해서는 안 된다. 실패·빈 결과도
    /// 같은 폴백. 고스트 자동완성의 generation/suggestion에는 손대지 않으므로
    /// 타이핑 중 제안 흐름과 간섭하지 않는다 (엔진 actor가 순차 처리).
    public func requestFolderName(for folderID: UUID, in store: EntryStore) {
        guard settings.autocompleteEnabled else { return }
        if case .failed = engineState { return }
        guard !namingFolderIDs.contains(folderID) else { return }
        let content = store.folderNamingContext(
            for: folderID, maxCharacters: settings.contextCharacters)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        namingFolderIDs.insert(folderID)
        let parameters = settings.parameters
        // 이름이 도착할 때까지 self를 붙잡는다(수명 유한) — 진행 표시 해제가 목적.
        Task { [engine, weak store] in
            let name =
                (try? await engine.generateFolderName(
                    content: content, parameters: parameters)) ?? ""
            self.namingFolderIDs.remove(folderID)
            guard !name.isEmpty, let store else { return }
            // 사용자가 그 사이 직접 이름을 바꿨다면 스토어 쪽 가드가 조용히 무시한다.
            withAnimation(.easeOut(duration: 0.18)) {
                store.renameFolderIfPlaceholder(folderID, to: name)
            }
        }
    }

    // MARK: - 내부

    private func invalidate() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        // 타이핑 재개 = 프리웜 선점 — 예측(과 그 앞의 타이핑)이 항상 이긴다.
        prewarmTask?.cancel()
        prewarmTask = nil
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
        // 조립은 예측 시점의 마지막 MainActor 작업 — 준비된 값(메타·카드·요약)을
        // 얹기만 하고, 지식 계산은 전부 백그라운드의 몫이다 (CLAUDE.md §2-2).
        let document = documentContextProvider?()
        let prompt = ContextAssembler.assemble(
            prefix: prefix,
            document: document,
            knowledge: knowledgeProvider?(),
            // C 창이 본문 어디서 시작하는지 — 이 앞에서 끝난 씬만 B로 들어간다.
            prefixStartUTF16: max(0, caretLocation - (prefix as NSString).length),
            style: parameters.promptStyle
        )
        // 대화 모드 (PLAN §10) — 커서가 열린 따옴표 안이면 정지 사다리를 발화
        // 끝으로 확장한다. 조립기의 말투 승격과 같은 감지를 써서 어긋나지 않는다.
        var parameters = parameters
        if document?.kind == .novel, ContextAssembler.isInsideUtterance(prefix) {
            parameters.stopAtUtteranceEnd = true
        }
        do {
            let completion = try await engine.complete(prompt: prompt, parameters: parameters) {
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
