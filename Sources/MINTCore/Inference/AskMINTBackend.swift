import Foundation

enum ReadyInstructionLimits {
    static func promptFits(count: Int, budget: Int) -> Bool { count > 0 && budget > 0 && count <= budget }
}

/// A bounded ordered stream; overflow ends the producer before any later chunk can bridge the gap.
struct AskAnswerGeneration: Sendable {
    enum Failure: Error { case overflow }
    let stream: AsyncThrowingStream<String, Error>
    private let task: Task<Void, Never>
    init(bufferLimit: Int = 64, operation: @escaping @Sendable (@escaping @Sendable (String) throws -> Void) async throws -> Void) {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream(bufferingPolicy: .bufferingOldest(max(1, bufferLimit)))
        self.stream = stream
        let worker = Task {
            do {
                try Task.checkCancellation()
                try await operation { chunk in
                    switch continuation.yield(chunk) {
                    case .enqueued: break
                    case .dropped: throw Failure.overflow
                    case .terminated: throw CancellationError()
                    @unknown default: throw Failure.overflow
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        task = worker
        continuation.onTermination = { _ in worker.cancel() }
    }
    func cancelAndDrain() async { task.cancel(); await task.value }

    static func local(engine: CompletionEngine, packet: AskEvidencePacket, question: String, parameters: CompletionParameters) throws -> Self {
        let user = try packet.userMessage(question: question)
        return Self { emit in
            try await engine.streamInstructionIfReady(system: AskEvidencePacket.systemMessage, user: user, parameters: parameters, onChunk: emit)
        }
    }
}
