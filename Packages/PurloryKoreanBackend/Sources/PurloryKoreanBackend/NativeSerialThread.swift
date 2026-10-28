import Foundation

/// C handles and their allocator lifetime stay on one utility thread until retirement.
final class NativeSerialThread: @unchecked Sendable {
    struct Job: Sendable {
        var valid: @Sendable () -> Bool
        var perform: @Sendable () -> Void
        var cancel: @Sendable () -> Void
        var retired: (@Sendable () -> Void)? = nil
    }
    private let condition = NSCondition()
    private var jobs: [Job] = []
    private var thread: Thread?

    func enqueue(_ job: Job) {
        condition.lock()
        guard job.valid() else { condition.unlock(); job.cancel(); return }
        jobs.append(job)
        if thread == nil {
            let next = Thread { [self] in run() }
            next.name = "Purlory Korean diagnostics"
            next.qualityOfService = .utility
            thread = next
            next.start()
        }
        condition.signal()
        condition.unlock()
    }

    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool {
                if job.valid() { job.perform() } else { job.cancel() }
            }
            if let retired = job.retired {
                condition.lock()
                let abandoned = jobs
                jobs.removeAll()
                thread = nil
                condition.unlock()
                for job in abandoned { job.cancel() }
                retired()
                return
            }
        }
    }
}
