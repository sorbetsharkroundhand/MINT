import Foundation

final class NativeCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, KoreanNativeError>?
    private var waiters: [CheckedContinuation<Value, any Error>] = []

    func finish(_ result: Result<Value, KoreanNativeError>) {
        let pending: [CheckedContinuation<Value, any Error>] = lock.withLock {
            guard self.result == nil else { return [] }
            self.result = result
            defer { waiters.removeAll() }
            return waiters
        }
        for waiter in pending { resume(waiter, with: result) }
    }

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let completed: Result<Value, KoreanNativeError>? = lock.withLock {
                if let result { return result }
                waiters.append(continuation)
                return nil as Result<Value, KoreanNativeError>?
            }
            if let completed { resume(continuation, with: completed) }
        }
    }

    private func resume(_ waiter: CheckedContinuation<Value, any Error>,
                        with result: Result<Value, KoreanNativeError>) {
        switch result {
        case .success(let value): waiter.resume(returning: value)
        case .failure(let error): waiter.resume(throwing: error)
        }
    }
}

final class NativeAnalysisRequest: @unchecked Sendable {
    let completion = NativeCompletion<KoreanNativeAnalysis>()
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() {
        lock.withLock { cancelled = true }
        completion.finish(.failure(.cancelled))
    }
    func value() async throws -> KoreanNativeAnalysis {
        try await withTaskCancellationHandler {
            guard !Task.isCancelled else { cancel(); throw KoreanNativeError.cancelled }
            return try await completion.value()
        } onCancel: { self.cancel() }
    }
}
