import Foundation

protocol WritingDiagnosticsChunkProvider: Sendable {
    func analyzeChunks(_ request: WritingDiagnosticsRequest,
                       emit: @escaping @Sendable (KoreanDiagnosticsChunk) async throws -> Void) async throws
}
extension KoreanDiagnosticsProvider: WritingDiagnosticsChunkProvider { }

struct WritingDiagnosticsReportEvent: Sendable {
    enum Kind: Sendable {
        case progress(completed: Int, total: Int)
        case findings([WritingDiagnosticsFinding])
        case finished(WritingDiagnosticsCoverage)
        case cancelled
        case failed(WritingDiagnosticsAvailability)
    }
    let runtime: ProjectRuntimeIdentity
    let profileRevision: UInt64
    let kind: Kind
}

/// A single-consumer report. Dropping its iterator cancels work even if the report value survives.
struct WritingDiagnosticsReport: AsyncSequence, Sendable {
    typealias Element = WritingDiagnosticsReportEvent
    let storage: WritingDiagnosticsReportStorage
    struct AsyncIterator: AsyncIteratorProtocol {
        private let consumer: WritingReportConsumer
        fileprivate init(_ storage: WritingDiagnosticsReportStorage) { consumer = WritingReportConsumer(storage) }
        mutating func next() async -> Element? { await consumer.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(storage) }
    func cancel() { storage.cancel() }
    var bufferedEventCount: Int { get async { await storage.channel.bufferedCount } }
    func waitForBufferedEvent() async { await storage.channel.waitForBufferedEvent() }
    func waitForCompletion() async { await storage.waitForCompletion() }
}

private final class WritingReportConsumer: Sendable {
    let storage: WritingDiagnosticsReportStorage
    init(_ storage: WritingDiagnosticsReportStorage) { self.storage = storage }
    deinit { storage.cancel() }
    func next() async -> WritingDiagnosticsReportEvent? {
        if Task.isCancelled { storage.cancel(); return nil }
        let event = await withTaskCancellationHandler { await storage.channel.next() } onCancel: { storage.cancel() }
        return Task.isCancelled ? nil : event
    }
}

/// No producer closure captures this storage strongly; abandoned reports cannot form a task cycle.
final class WritingDiagnosticsReportStorage: @unchecked Sendable {
    let channel: WritingReportChannel
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false
    init(runtime: ProjectRuntimeIdentity, profileRevision: UInt64) {
        channel = WritingReportChannel(runtime: runtime, profileRevision: profileRevision)
    }
    deinit { cancel() }
    func start(_ task: Task<Void, Never>) {
        let stop = lock.withLock { self.task = task; return cancelled }
        if stop { task.cancel() }
    }
    func cancel() {
        let task = lock.withLock { cancelled = true; return self.task }
        task?.cancel()
        let channel = channel
        Task { await channel.cancel() }
    }
    func waitForCompletion() async {
        let current = lock.withLock { task }
        await current?.value
    }
}

/// One buffered event, one producer, one consumer. Cancellation wakes every suspended operation.
actor WritingReportChannel {
    private let runtime: ProjectRuntimeIdentity
    private let profileRevision: UInt64
    private var buffered: WritingDiagnosticsReportEvent?
    private var ended = false
    private var cancelled = false
    private var receiver: CheckedContinuation<WritingDiagnosticsReportEvent?, Never>?
    private var capacity: [CheckedContinuation<Void, Error>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    var bufferedCount: Int { buffered == nil ? 0 : 1 }
    init(runtime: ProjectRuntimeIdentity, profileRevision: UInt64) { self.runtime = runtime; self.profileRevision = profileRevision }
    func waitForCapacity() async throws {
        try Task.checkCancellation()
        guard !ended, !cancelled else { throw CancellationError() }
        if buffered == nil { return }
        try await withCheckedThrowingContinuation { capacity.append($0) }
        try Task.checkCancellation()
        guard !ended, !cancelled else { throw CancellationError() }
    }
    func send(_ kind: WritingDiagnosticsReportEvent.Kind) async throws {
        try await waitForCapacity()
        let event = WritingDiagnosticsReportEvent(runtime: runtime, profileRevision: profileRevision, kind: kind)
        if let receiver { self.receiver = nil; receiver.resume(returning: event) }
        else { buffered = event }
        notifyObservers()
    }
    func next() async -> WritingDiagnosticsReportEvent? {
        if let buffered {
            self.buffered = nil; wakeCapacity()
            return buffered
        }
        if ended { return nil }
        // Reports have one consumer; a second simultaneous receiver cannot steal its stream.
        guard receiver == nil else { return nil }
        return await withCheckedContinuation { receiver = $0 }
    }
    func finish() {
        ended = true
        if buffered == nil { receiver?.resume(returning: nil); receiver = nil }
        wakeCapacity(); notifyObservers()
    }
    func cancel() {
        guard !ended else { return }
        cancelled = true; ended = true
        let event = WritingDiagnosticsReportEvent(runtime: runtime, profileRevision: profileRevision, kind: .cancelled)
        if let receiver { self.receiver = nil; receiver.resume(returning: event) }
        else { buffered = event }
        wakeCapacity(); notifyObservers()
    }
    func waitForBufferedEvent() async {
        if buffered != nil || ended { return }
        await withCheckedContinuation { observers.append($0) }
    }
    private func wakeCapacity() {
        let current = capacity; capacity.removeAll()
        for waiter in current {
            if ended || cancelled { waiter.resume(throwing: CancellationError()) } else { waiter.resume() }
        }
    }
    private func notifyObservers() {
        if buffered != nil || ended { let current = observers; observers.removeAll(); current.forEach { $0.resume() } }
    }
}
