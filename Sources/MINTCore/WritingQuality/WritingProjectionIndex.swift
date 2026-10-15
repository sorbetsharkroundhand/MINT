import CryptoKit
import Foundation

struct WritingAnalysisWindow: Sendable {
    let text: String
    let digest: String
    let coveredRange: WritingDiagnosticRange
    /// Source coordinates are absolute; prose coordinates are relative to this window.
    let segments: [WritingProseSegment]
    func contiguousSourceRange(for range: WritingDiagnosticRange) -> WritingDiagnosticRange? {
        guard let ranges = WritingRangeMapping.map(range.nsRange, length: text.utf16.count, segments: segments),
              ranges.count == 1 else { return nil }
        return ranges[0]
    }
}

struct WritingAnalysisWindows: Sequence, Sendable {
    private let factory: @Sendable () -> AnyIterator<WritingAnalysisWindow>
    init(_ factory: @escaping @Sendable () -> AnyIterator<WritingAnalysisWindow>) { self.factory = factory }
    func makeIterator() -> AnyIterator<WritingAnalysisWindow> { factory() }
    var first: WritingAnalysisWindow? { makeIterator().next() }
}

/// Immutable nodes share unchanged subtrees with already-issued window sequences.
private final class WritingProjectionNode: Sendable {
    let block: WritingProseBlock
    let priority: UInt64
    let left: WritingProjectionNode?, right: WritingProjectionNode?
    let count: Int, sourceLength: Int, proseLength: Int
    init(_ block: WritingProseBlock, priority: UInt64, left: WritingProjectionNode? = nil, right: WritingProjectionNode? = nil) {
        self.block = block; self.priority = priority; self.left = left; self.right = right
        count = 1 + (left?.count ?? 0) + (right?.count ?? 0)
        sourceLength = block.sourceLength + (left?.sourceLength ?? 0) + (right?.sourceLength ?? 0)
        proseLength = block.proseLength + (left?.proseLength ?? 0) + (right?.proseLength ?? 0)
    }
    func copy(left: WritingProjectionNode?, right: WritingProjectionNode?) -> WritingProjectionNode {
        WritingProjectionNode(block, priority: priority, left: left, right: right)
    }
    static func collect(_ node: WritingProjectionNode?, range: NSRange, source: Int = 0, prose: Int = 0,
                        body: (WritingProseBlock, Int, Int) -> Void) {
        guard let node, prose < range.upperBound, prose + node.proseLength > range.location else { return }
        let s = source + (node.left?.sourceLength ?? 0), p = prose + (node.left?.proseLength ?? 0)
        collect(node.left, range: range, source: source, prose: prose, body: body)
        if p < range.upperBound && p + node.block.proseLength > range.location { body(node.block, s, p) }
        collect(node.right, range: range, source: s + node.block.sourceLength,
                prose: p + node.block.proseLength, body: body)
    }
    static func segments(_ root: WritingProjectionNode?, range: NSRange) -> [WritingProseSegment] {
        var result: [WritingProseSegment] = []
        collect(root, range: range) { block, source, prose in
            for segment in block.segments {
                let global = NSRange(location: prose + segment.prose.location, length: segment.prose.length)
                let clipped = NSIntersectionRange(global, range)
                guard clipped.length > 0 else { continue }
                let original = segment.eligible
                    ? NSRange(location: source + segment.source.location + clipped.location - global.location, length: clipped.length)
                    : NSRange(location: source + segment.source.location, length: segment.source.length)
                result.append(WritingProseSegment(source: original,
                    prose: NSRange(location: clipped.location - range.location, length: clipped.length),
                    eligible: segment.eligible, unsupported: segment.unsupported))
            }
        }
        return result
    }
}

final class WritingProjectionIndex {
    struct Piece { let block: WritingProseBlock; let range: WritingDiagnosticRange; let proseOffset: Int }
    private var root: WritingProjectionNode?
    private var random: UInt64 = 0x6d696e742d70726f
    private(set) var resetCount = 0, lastMutationSourceUTF16 = 0, lastMutationVisits = 0
    var sourceLength: Int { root?.sourceLength ?? 0 }
    var proseLength: Int { root?.proseLength ?? 0 }

    func reset(source: String) {
        root = nil; resetCount += 1
        for block in WritingProseProjection.blocks(source: source) { root = merge(root, node(block)) }
        lastMutationSourceUTF16 = source.utf16.count; lastMutationVisits = 0
    }
    /// The caller supplies complete affected pieces, with captured Markdown/native state.
    /// Reject an unknown edit rather than silently rebuilding the document on typing.
    @discardableResult
    func apply(_ patch: WritingProjectionPatch) -> Bool {
        let range = patch.oldSourceRange.nsRange
        lastMutationVisits = 0; lastMutationSourceUTF16 = 0
        guard WritingRangeMapping.valid(range, in: sourceLength),
              patch.replacement.allSatisfy({ !$0.sourceText.isEmpty && $0.hasValidMap }),
              let first = rank(range.location), let end = rank(range.upperBound) else { return false }
        let (before, remaining) = split(root, count: first)
        let (_, after) = split(remaining, count: end - first)
        var replacement: WritingProjectionNode?
        for block in patch.replacement {
            lastMutationSourceUTF16 += block.sourceLength
            replacement = merge(replacement, node(block))
        }
        root = merge(merge(before, replacement), after)
        return true
    }
    func sourcePiece(containing offset: Int) -> Piece? {
        guard sourceLength > 0, offset >= 0, offset <= sourceLength else { return nil }
        var next = root, source = 0, prose = 0
        let point = min(offset, sourceLength - 1)
        while let node = next {
            let s = source + (node.left?.sourceLength ?? 0), p = prose + (node.left?.proseLength ?? 0)
            if point < s { next = node.left }
            else if point < s + node.block.sourceLength {
                return Piece(block: node.block, range: .init(location: s, length: node.block.sourceLength), proseOffset: p)
            } else {
                source = s + node.block.sourceLength; prose = p + node.block.proseLength; next = node.right
            }
        }
        return nil
    }
    func windows(intersecting range: WritingDiagnosticRange) -> WritingAnalysisWindows {
        guard WritingRangeMapping.valid(range.nsRange, in: sourceLength),
              var first = sourcePiece(containing: range.location),
              var last = sourcePiece(containing: range.location + max(0, range.length - 1)) else {
            return WritingAnalysisWindows { AnyIterator { nil } }
        }
        if first.range.location > 0, let previous = sourcePiece(containing: first.range.location - 1) { first = previous }
        let lastEnd = last.range.location + last.range.length
        if lastEnd < sourceLength, let next = sourcePiece(containing: lastEnd) { last = next }
        let frozen = root, start = first.proseOffset, limit = last.proseOffset + last.block.proseLength
        return WritingAnalysisWindows {
            var cursor = start
            return AnyIterator {
                while cursor < limit {
                    // Read whole bounded pieces at the trailing edge to retain grapheme context.
                    var buffer = ""
                    WritingProjectionNode.collect(frozen, range: NSRange(location: cursor, length: min(4096, limit - cursor))) { block, _, prose in
                        let text = block.proseText as NSString, lower = max(0, cursor - prose)
                        buffer += text.substring(from: lower)
                    }
                    guard let local = WritingWindowSplitter.ranges(in: buffer).makeIterator().next() else { cursor = limit; return nil }
                    let text = (buffer as NSString).substring(with: local.nsRange), location = cursor + local.location
                    let end = location + local.length
                    cursor = end >= limit ? limit : end - WritingWindowSplitter.overlapUTF16(in: text)
                    let covered = NSRange(location: location, length: local.length)
                    return WritingAnalysisWindow(text: text, digest: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
                        coveredRange: .init(covered), segments: WritingProjectionNode.segments(frozen, range: covered))
                }
                return nil
            }
        }
    }
    func sourceRanges(for range: WritingDiagnosticRange, in window: WritingAnalysisWindow) -> [WritingDiagnosticRange]? {
        WritingRangeMapping.map(range.nsRange, length: window.text.utf16.count, segments: window.segments)
    }
    func sourceRanges(forProse range: WritingDiagnosticRange) -> [WritingDiagnosticRange]? {
        guard WritingRangeMapping.valid(range.nsRange, in: proseLength) else { return nil }
        return WritingRangeMapping.map(NSRange(location: 0, length: range.length), length: range.length,
                                       segments: WritingProjectionNode.segments(root, range: range.nsRange))
    }
    private func node(_ block: WritingProseBlock) -> WritingProjectionNode {
        random ^= random << 13; random ^= random >> 7; random ^= random << 17
        return WritingProjectionNode(block, priority: random)
    }
    private func rank(_ offset: Int) -> Int? {
        if offset == sourceLength { return root?.count ?? 0 }
        var next = root, offset = offset, rank = 0
        while let node = next {
            lastMutationVisits += 1
            let left = node.left?.sourceLength ?? 0, count = node.left?.count ?? 0
            if offset < left { next = node.left }
            else if offset == left { return rank + count }
            else if offset < left + node.block.sourceLength { return nil }
            else { offset -= left + node.block.sourceLength; rank += count + 1; next = node.right }
        }
        return nil
    }
    private func split(_ node: WritingProjectionNode?, count: Int) -> (WritingProjectionNode?, WritingProjectionNode?) {
        guard let node else { return (nil, nil) }
        lastMutationVisits += 1
        let left = node.left?.count ?? 0
        if count <= left {
            let (before, after) = split(node.left, count: count)
            return (before, node.copy(left: after, right: node.right))
        }
        let (before, after) = split(node.right, count: count - left - 1)
        return (node.copy(left: node.left, right: before), after)
    }
    private func merge(_ left: WritingProjectionNode?, _ right: WritingProjectionNode?) -> WritingProjectionNode? {
        guard let left else { return right }; guard let right else { return left }
        lastMutationVisits += 1
        if left.priority < right.priority { return left.copy(left: left.left, right: merge(left.right, right)) }
        return right.copy(left: merge(left, right.left), right: right.right)
    }
}

private enum WritingRangeMapping {
    static func valid(_ range: NSRange, in length: Int) -> Bool {
        range.location >= 0 && range.location <= length && range.length >= 0 && range.length <= length - range.location
    }
    static func map(_ range: NSRange, length: Int, segments: [WritingProseSegment]) -> [WritingDiagnosticRange]? {
        guard range.length > 0, valid(range, in: length) else { return nil }
        var cursor = range.location, result: [WritingDiagnosticRange] = []
        for segment in segments {
            let overlap = NSIntersectionRange(segment.prose, range)
            guard overlap.length > 0 else { continue }
            guard segment.eligible, segment.source.length == segment.prose.length, overlap.location == cursor else { return nil }
            let source = NSRange(location: segment.source.location + overlap.location - segment.prose.location, length: overlap.length)
            if let last = result.last, last.location + last.length == source.location {
                result[result.count - 1].length += source.length
            } else { result.append(.init(source)) }
            cursor = overlap.upperBound
        }
        return cursor == range.upperBound ? result : nil
    }
}
