import Foundation
import CKiwiBridge

/// All access, including close, belongs to the worker's utility thread.
final class KiwiNativeHandle: KoreanNativeHandle {
    private var analyzer: kiwi_h?
    private var typos: kiwi_prepared_typo_h?

    init(model: URL, admission: @Sendable () -> Bool) throws {
        guard admission() else { throw KoreanNativeError.cancelled }
        guard let version = mint_kiwi_bridge_version(), String(cString: version) == "0.24.0" else {
            throw KoreanNativeError.unavailable
        }
        guard admission() else { throw KoreanNativeError.cancelled }
        guard let builder = mint_kiwi_builder_init_fp32(model.path) else { throw KoreanNativeError.unavailable }
        defer { kiwi_builder_close(builder) }
        guard admission() else { throw KoreanNativeError.cancelled }
        guard let instance = kiwi_builder_build(builder, nil, 0) else { throw KoreanNativeError.unavailable }
        guard admission() else { kiwi_close(instance); throw KoreanNativeError.cancelled }
        guard let prepared = kiwi_typo_prepare(kiwi_typo_get_default(1)) else {
            kiwi_close(instance)
            throw KoreanNativeError.unavailable
        }
        analyzer = instance; typos = prepared
    }

    func analyze(_ text: String, admission: @Sendable () -> Bool) throws -> KoreanNativeAnalysis {
        guard let analyzer, let typos else { throw KoreanNativeError.unavailable }
        var options = kiwi_analyze_option_t()
        options.match_options = 0x80003f
        options.typo_threshold = 2.5
        options.dialect_cost = 3
        options.typo_transformer = typos
        let units = Array(text.utf16) + [0]
        guard admission() else { throw KoreanNativeError.cancelled }
        let result = units.withUnsafeBufferPointer {
            kiwi_analyze_w(analyzer, $0.baseAddress, 1, options, nil)
        }
        guard let result else { throw KoreanNativeError.unavailable }
        defer { kiwi_res_close(result) }
        guard admission() else { throw KoreanNativeError.cancelled }
        guard kiwi_res_size(result) > 0, let joiner = kiwi_new_joiner(analyzer, 1) else {
            throw KoreanNativeError.unavailable
        }
        defer { kiwi_joiner_close(joiner) }
        let source = text as NSString
        var tokens: [KoreanNativeToken] = []
        var sentences: [Int: NSRange] = [:]
        let count = kiwi_res_word_num(result, 0)
        guard count >= 0 else { throw KoreanNativeError.unavailable }
        for i in 0..<count {
            guard admission() else { throw KoreanNativeError.cancelled }
            guard let form = kiwi_res_form(result, 0, i), let tag = kiwi_res_tag(result, 0, i) else {
                throw KoreanNativeError.unavailable
            }
            let location = Int(kiwi_res_position(result, 0, i)), length = Int(kiwi_res_length(result, 0, i))
            guard location >= 0, length >= 0, location <= source.length, length <= source.length - location else {
                throw KoreanNativeError.unavailable
            }
            let range = NSRange(location: location, length: length)
            guard Array(source.substring(with: range).utf16) == Array(units[location..<(location + length)]) else {
                throw KoreanNativeError.unavailable
            }
            tokens.append(KoreanNativeToken(form: String(cString: form), tag: String(cString: tag), range: range))
            if length > 0 {
                let sentence = Int(kiwi_res_sent_position(result, 0, i))
                guard sentence >= 0 else { throw KoreanNativeError.unavailable }
                sentences[sentence] = sentences[sentence].map { NSUnionRange($0, range) } ?? range
            }
            guard kiwi_joiner_add(joiner, form, tag, 0) == 0 else { throw KoreanNativeError.unavailable }
        }
        guard admission() else { throw KoreanNativeError.cancelled }
        guard let joined = kiwi_joiner_get(joiner) else { throw KoreanNativeError.unavailable }
        let replacement = String(cString: joined)
        let candidates = replacement == text ? [] : [KoreanNativeCandidate(
            originalRange: NSRange(location: 0, length: source.length),
            replacement: replacement, origin: "kiwi.join")]
        return KoreanNativeAnalysis(tokens: tokens, sentences: sentences.keys.sorted().compactMap { sentences[$0] },
                                    candidates: candidates)
    }

    func close() {
        if let typos { kiwi_prepared_typo_close(typos); self.typos = nil }
        if let analyzer { kiwi_close(analyzer); self.analyzer = nil }
    }
}
