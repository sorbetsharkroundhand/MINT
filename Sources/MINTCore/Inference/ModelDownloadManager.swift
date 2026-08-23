import Foundation
import HuggingFace

/// 모델 가중치 프리페치 관리자 — 툴바 모델 드롭다운의 다운로드 버튼용.
///
/// `CompletionEngine`의 로드와 **같은 허브 캐시**(HubCache 기본 위치, Python 호환)에
/// 내려받는다 — 여기서 미리 받아 두면 그 모델로 전환할 때 다운로드 없이 바로
/// 메모리 로드만 남는다. 파일 패턴도 MLXLMCommon의 modelDownloadPatterns와
/// 같게 유지해 캐시가 정확히 겹치게 한다.
@MainActor
public final class ModelDownloadManager: ObservableObject {

    public enum State: Equatable {
        case notDownloaded
        /// 진행률 0...1.
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    /// 모델 id → 상태. UI(ModelChip 드롭다운)가 구독한다.
    @Published public private(set) var states: [String: State] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    /// 모델별 진행률 coalescing (이슈 #46) — 틱마다 @Published를 쓰면
    /// 드롭다운 전체가 다시 그려진다. 250ms 간격으로만 상태를 바꾼다.
    private var progressGates: [String: ProgressCoalescer] = [:]

    /// MLXLMCommon modelDownloadPatterns(safetensors + 토크나이저)와 동일.
    private static let filePatterns = ["*.safetensors", "*.json", "*.jinja"]

    public init() {}

    /// 로컬 캐시를 확인해 각 모델의 상태를 갱신한다 (드롭다운을 열 때 호출).
    /// 진행 중인 다운로드는 건드리지 않는다.
    public func refresh(_ modelIDs: [String]) {
        for id in modelIDs where tasks[id] == nil {
            states[id] = Self.hasLocalWeights(id) ? .downloaded : .notDownloaded
        }
    }

    /// 다운로드 시작 — 이미 진행 중이면 무시. 실패했던 모델은 다시 시도한다.
    /// 열·저전력 게이트(AGENTS §4 백그라운드 3요건)에 걸리면 시작하지 않고
    /// 이유를 남긴다 — 사용자가 조건이 나아지면 같은 버튼으로 재시도한다.
    public func download(_ modelID: String) {
        guard tasks[modelID] == nil, let repo = Self.repoID(modelID) else { return }
        if let reason = Self.startBlockReason(
            thermal: ProcessInfo.processInfo.thermalState,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) {
            states[modelID] = .failed(reason)
            return
        }
        states[modelID] = .downloading(0)
        progressGates[modelID] = ProgressCoalescer()
        tasks[modelID] = Task { [weak self] in
            do {
                _ = try await HubClient().downloadSnapshot(
                    of: repo, kind: .model, matching: Self.filePatterns
                ) { progress in
                    self?.noteProgress(modelID, progress.fractionCompleted)
                }  // noteProgress 내부에서 coalesce — 틱마다 @Published 쓰지 않음
                self?.finish(modelID, state: .downloaded)
            } catch is CancellationError {
                // 취소 — 부분 캐시가 있어도 완주 전이므로 미다운로드로 되돌린다.
                self?.finish(modelID, state: .notDownloaded)
            } catch {
                self?.finish(modelID, state: .failed(error.localizedDescription))
            }
        }
    }

    /// 진행 중 다운로드 취소.
    public func cancel(_ modelID: String) {
        tasks[modelID]?.cancel()
    }

    private func noteProgress(_ modelID: String, _ fraction: Double) {
        guard case .downloading = states[modelID] else { return }
        guard progressGates[modelID]?.shouldEmit(fraction) ?? true else { return }
        states[modelID] = .downloading(fraction)
    }

    /// 다운로드 시작 가능 여부 — 걸리는 이유를 사용자 문구로 돌려준다.
    /// 열 상태는 심각 이상, 저전력은 항상 보류한다. 네트워크 전송 자체는
    /// 가볍지만 수 분 길이의 백그라운드 작업이라 AGENTS §4를 따른다.
    nonisolated static func startBlockReason(
        thermal: ProcessInfo.ThermalState, lowPower: Bool
    ) -> String? {
        switch thermal {
        case .serious, .critical:
            return "기기가 뜨거워요 — 온도가 내려오면 다시 시도하세요"
        default: break
        }
        if lowPower {
            return "저전력 모드 중에는 내려받지 않아요 — 충전하거나 해제 후 다시 시도하세요"
        }
        return nil
    }

    private func finish(_ modelID: String, state: State) {
        states[modelID] = state
        tasks[modelID] = nil
    }

    /// 허브 캐시 snapshots/에 safetensors가 하나라도 있으면 받은 것으로 본다 —
    /// 가중치가 파일 크기의 대부분이라 이 판정이 실용적으로 정확하다.
    private nonisolated static func hasLocalWeights(_ modelID: String) -> Bool {
        guard let repo = repoID(modelID) else { return false }
        let snapshots = HubCache.default.snapshotsDirectory(repo: repo, kind: .model)
        guard let enumerator = FileManager.default.enumerator(
            at: snapshots, includingPropertiesForKeys: nil)
        else { return false }
        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            return true
        }
        return false
    }

    private nonisolated static func repoID(_ modelID: String) -> Repo.ID? {
        let parts = modelID.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Repo.ID(namespace: String(parts[0]), name: String(parts[1]))
    }
}
