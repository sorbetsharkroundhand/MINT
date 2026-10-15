import Foundation
import Dispatch
import Darwin
import Kiwi

// Headless boundary test; main.swift also supports Xcode's application archive entry point.
enum ProbeError: Error { case failed(String) }
func require(_ value: Bool, _ reason: String) throws {
    if !value { throw ProbeError.failed(reason) }
}
func nanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func nativeError() -> String { kiwi_error().map { String(cString: $0) } ?? "native operation failed" }

final class Backend: @unchecked Sendable {
    let handle: kiwi_h
    let typos: kiwi_prepared_typo_h
    let initializationNS: UInt64

    init(model: String) throws {
        let start = nanoseconds()
        // Pinned C ABI: default dictionaries + explicit CoNg model, one native thread.
        guard let builder = kiwi_builder_init(model, 1, 15 | 0x0400, 0) else {
            throw ProbeError.failed(nativeError())
        }
        defer { kiwi_builder_close(builder) }
        // The current C/Swift API supplies a prepared transformer per analysis.
        // The legacy builder-level transformer crashed in the pinned binary probe.
        guard let instance = kiwi_builder_build(builder, nil, 0) else {
            throw ProbeError.failed(nativeError())
        }
        guard let prepared = kiwi_typo_prepare(kiwi_typo_get_default(1)) else {
            kiwi_close(instance)
            throw ProbeError.failed(nativeError())
        }
        handle = instance
        typos = prepared
        initializationNS = nanoseconds() - start
    }

    deinit { kiwi_prepared_typo_close(typos); kiwi_close(handle) }

    func analyze(_ text: String) throws -> [String: Any] {
        try require(text.utf16.count <= 4096, "native request exceeds 4096 UTF-16 units")
        var options = kiwi_analyze_option_t()
        options.match_options = 0x80003f // KIWI_MATCH_ALL, preserving original coda.
        options.typo_threshold = 2.5
        options.typo_transformer = typos
        options.dialect_cost = 3
        let utf16 = Array(text.utf16) + [0]
        let start = nanoseconds()
        let result = utf16.withUnsafeBufferPointer {
            kiwi_analyze_w(handle, $0.baseAddress, 1, options, nil)
        }
        let callNS = nanoseconds() - start
        guard let result else { throw ProbeError.failed(nativeError()) }
        defer { kiwi_res_close(result) }
        try require(kiwi_res_size(result) > 0, "native analysis returned no candidates")
        guard let joiner = kiwi_new_joiner(handle, 1) else { throw ProbeError.failed(nativeError()) }
        defer { kiwi_joiner_close(joiner) }
        let source = text as NSString
        var tokens: [[String: Any]] = []
        for i in 0..<kiwi_res_word_num(result, 0) {
            guard let form = kiwi_res_form(result, 0, i), let tag = kiwi_res_tag(result, 0, i) else {
                throw ProbeError.failed(nativeError())
            }
            let location = Int(kiwi_res_position(result, 0, i))
            let length = Int(kiwi_res_length(result, 0, i))
            // Virtual morphemes (for example an elided copula) have zero source length.
            // They are evidence of grammar, never an editable/underlined source target.
            try require(location >= 0 && length >= 0 && location <= source.length
                        && length <= source.length - location, "invalid native UTF-16 range")
            let range = NSRange(location: location, length: length)
            let original = source.substring(with: range)
            try require(Array(original.utf16) == Array(utf16[location..<(location + length)]),
                        "native token splits a surrogate pair")
            tokens.append(["form": String(cString: form), "tag": String(cString: tag),
                           "location": location, "length": length, "original": original,
                           "typoCost": Double(kiwi_res_typo_cost(result, 0, i))])
            try require(kiwi_joiner_add(joiner, form, tag, 0) == 0, "native joiner rejected token")
        }
        guard let joined = kiwi_joiner_get(joiner) else { throw ProbeError.failed(nativeError()) }
        return ["text": text, "joined": String(cString: joined), "tokens": tokens,
                "utf16RangesValid": true, "nativeCallNS": callNS]
    }
}

let fixtures: [(String, String)] = [
    ("typo", "그 일은 어제 됬다."),
    ("spacing", "나는 할수 있다."),
    ("ambiguous", "그의 장례희망에는 흰 꽃이 적혀 있었다."),
    ("mixed", "🙂 한글 English 42.\n다음 문장이다."),
    ("decomposed", "🙂 한글을 쓴다.\n다른 문장이다."),
    ("endings", "나는 밥을 먹었는데 비가 오는데 길이 어두운데 집으로 간다."),
    ("dialect", "\"혼저 옵서예.\" 라온이가 말했다."),
]

func fixtureResults(_ backend: Backend) throws -> [[String: Any]] {
    try fixtures.map { id, text in
        var row = try backend.analyze(text)
        row["id"] = id
        return row
    }
}

func performanceInput(_ count: Int) -> String {
    let phrase = "나는 원고를 쓰는데 창밖에는 비가 내리고 있었다. 다음 문장을 천천히 고친다. "
    let repeated = String(repeating: phrase, count: count / phrase.utf16.count + 1)
    return String(repeated.prefix(count))
}

final class CancellationState: @unchecked Sendable {
    let lock = NSLock()
    var cancelled = false
    var admittedCalls = 0
    var ended: UInt64 = 0
    var error: String?
}

func cancellationTrial(_ backend: Backend, cancel: Bool) throws -> (UInt64, Int) {
    let state = CancellationState(), started = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0), allowNext = DispatchSemaphore(value: 0)
    DispatchQueue(label: "mint.backend-probe.native").async {
        for index in 0..<2 {
            let admitted = state.lock.withLock {
                if state.cancelled { return false }
                state.admittedCalls += 1
                return true
            }
            guard admitted else { break }
            if index == 0 { started.signal() }
            do { _ = try backend.analyze(performanceInput(1024)) }
            catch { state.lock.withLock { state.error = String(describing: error) } }
            if index == 0 { allowNext.wait() }
        }
        state.lock.withLock { state.ended = nanoseconds() }
        finished.signal()
    }
    started.wait()
    let cancellationTime = nanoseconds()
    state.lock.withLock { state.cancelled = cancel }
    allowNext.signal()
    finished.wait()
    if let error = state.error { throw ProbeError.failed(error) }
    return (state.ended > cancellationTime ? state.ended - cancellationTime : 0, state.admittedCalls)
}

func cancellationSample(_ backend: Backend) throws -> [String: Any] {
    let (drain, cancelledCalls) = try cancellationTrial(backend, cancel: true)
    let (_, controlCalls) = try cancellationTrial(backend, cancel: false)
    try require(cancelledCalls == 1 && controlCalls == 2, "native admission control failed")
    return ["cancellationDrainNS": drain,
            "callsAfterCancellation": cancelledCalls - 1, "uncancelledControlCalls": controlCalls,
            "nativeCallInterruptible": false]
}

func measure(_ backend: Backend) throws -> [String: Any] {
    var rows: [[String: Any]] = []
    for size in [256, 1024, 4096] {
        let input = performanceInput(size)
        for _ in 0..<5 { _ = try backend.analyze(input) }
        var elapsed: [UInt64] = [], calls: [UInt64] = []
        for _ in 0..<30 {
            let start = nanoseconds(), result = try backend.analyze(input)
            elapsed.append(nanoseconds() - start)
            calls.append(result["nativeCallNS"] as! UInt64)
        }
        elapsed.sort()
        rows.append(["utf16": input.utf16.count, "iterations": 30, "warmups": 5,
                     "p50NS": elapsed[14], "p95NS": elapsed[28], "maxNS": elapsed.last!,
                     "nativeCallMaxNS": calls.max()!])
    }
    let cancellation = try cancellationSample(backend)
    var usage = rusage()
    try require(getrusage(RUSAGE_SELF, &usage) == 0, "cannot measure resident memory")
    return ["windows": rows, "peakResidentBytes": usage.ru_maxrss, "cancellation": cancellation]
}

do {
    let args = CommandLine.arguments
    let model: String
    if let index = args.firstIndex(of: "--model"), args.count > index + 1 {
        model = args[index + 1]
    } else {
        guard let resources = Bundle.main.resourceURL else { throw ProbeError.failed("missing bundle resources") }
        model = resources.appendingPathComponent("KoreanNLP.bundle/models/cong/base").path
    }
    let backend = try Backend(model: model)
    var output: [String: Any] = ["version": String(cString: kiwi_version()),
                               "initializationNS": backend.initializationNS,
                               "modelPath": model, "fixtures": try fixtureResults(backend)]
    if let index = args.firstIndex(of: "--expect-denied"), args.count > index + 1 {
        var denied = false
        do { try Data("must-not-write".utf8).write(to: URL(fileURLWithPath: args[index + 1])) }
        catch {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            denied = (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError)
                || (underlying?.domain == NSPOSIXErrorDomain
                    && [Int(EPERM), Int(EACCES)].contains(underlying!.code))
        }
        try require(denied, "external synthetic write was not denied by sandbox")
        output["sandboxOutsideWriteDenied"] = true
    }
    if args.contains("--measure") { output["performance"] = try measure(backend) }
    var peakUsage = rusage()
    try require(getrusage(RUSAGE_SELF, &peakUsage) == 0, "cannot measure process peak memory")
    output["peakResidentBytes"] = peakUsage.ru_maxrss
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data(("Backend probe failed: \(error)\n").utf8))
    exit(2)
}
