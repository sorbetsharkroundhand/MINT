import Foundation

/// One app-owned monitor for the existing shared engine. Project storage and writer
/// decisions never participate in pressure shedding; only derived/model work pauses.
@MainActor
public final class MemoryPressureRuntime {
    private let coordinator: MemoryPressureCoordinator

    public init(completion: CompletionController, indexer: BackgroundIndexer,
                engine: CompletionEngine,
                source: any MemoryPressureEventSource = SystemMemoryPressureSource()) {
        coordinator = MemoryPressureCoordinator(
            backgroundPause: { [weak indexer] in indexer?.setMemoryPressurePaused($0) },
            completionPause: { [weak completion] in completion?.setMemoryPressurePaused($0) },
            releaseModel: { try await engine.unload() },
            releaseFailed: { [weak completion] in completion?.noteMemoryReleaseFailure($0) })
        coordinator.start(source: source)
    }

    public func stop() { coordinator.stop() }
    public func drain() async { await coordinator.waitForRelease() }
}
