import Foundation

struct WritingSerializedBlockStyle: Sendable, Equatable {
    let block: String
    let alignment: String?
    let checked: Bool
    let marker: String?
    let mathRole: String?
    init(_ attributes: [NSAttributedString.Key: Any] = [:]) {
        block = attributes[.mintBlock] as? String ?? "p"
        alignment = attributes[.mintAlign] as? String
        checked = attributes[.mintChecked] as? Bool ?? false
        marker = attributes[.mintMarker] as? String
        mathRole = attributes[.mintMathDelim] as? String
    }
}

struct WritingSerializedRow: Sendable {
    let text: String
    let textLength: Int
    let nativeContentLength: Int
    let hasLineFeed: Bool
    var isCode = false
    var eligible = true
    var prefix = ""
    var suffix = ""
    var blockStyle = WritingSerializedBlockStyle()
    /// Source ranges address text; native ranges are relative to this row.
    let spans: [InlineMarkdown.SerializedSpan]
    var nativeLength: Int { nativeContentLength + (hasLineFeed ? 1 : 0) }
    var baseSourceLength: Int { textLength + (hasLineFeed ? 1 : 0) }
}

/// Prefix totals include all native text, including opaque media/code, and source-only fences.
final class WritingNativeRowIndex {
    struct Located {
        let row: WritingSerializedRow
        let nativeRange: NSRange
        let sourceStart: Int
        let textStart: Int
    }
    private final class Node {
        let row: WritingSerializedRow
        let priority: UInt64
        let left: Node?, right: Node?
        let count: Int, nativeLength: Int, coreSourceLength: Int
        let firstCode: Bool, lastCode: Bool
        init(_ row: WritingSerializedRow, priority: UInt64, left: Node? = nil, right: Node? = nil) {
            self.row = row; self.priority = priority; self.left = left; self.right = right
            count = 1 + (left?.count ?? 0) + (right?.count ?? 0)
            nativeLength = row.nativeLength + (left?.nativeLength ?? 0) + (right?.nativeLength ?? 0)
            coreSourceLength = row.baseSourceLength + (left?.coreSourceLength ?? 0) + (right?.coreSourceLength ?? 0)
                + (left.map { $0.lastCode != row.isCode ? 4 : 0 } ?? 0)
                + (right.map { row.isCode != $0.firstCode ? 4 : 0 } ?? 0)
            firstCode = left?.firstCode ?? row.isCode; lastCode = right?.lastCode ?? row.isCode
        }
        func copy(left: Node?, right: Node?) -> Node { Node(row, priority: priority, left: left, right: right) }
        func sourceLength(previousCode: Bool) -> Int { coreSourceLength + (previousCode != firstCode ? 4 : 0) }
    }
    private var root: Node?
    private var random: UInt64 = 0x6d696e742d6e6174
    var nativeLength: Int { root?.nativeLength ?? 0 }
    var sourceLength: Int {
        guard let root else { return 0 }
        return root.sourceLength(previousCode: false) + (root.lastCode ? 4 : 0)
    }
    func snapshot() -> WritingNativeRowIndex {
        let copy = WritingNativeRowIndex()
        copy.root = root; copy.random = random
        return copy
    }
    func sourceOffset(forNative offset: Int) -> Int? {
        guard offset >= 0, offset <= nativeLength else { return nil }
        if nativeLength == 0 { return offset == 0 ? 0 : nil }
        guard let located = row(containingNative: offset) else { return nil }
        let relative = offset - located.nativeRange.location
        for span in located.row.spans where relative >= span.native.location && relative <= span.native.upperBound {
            if let body = span.body, body.length == span.native.length {
                return located.textStart + body.location + relative - span.native.location
            }
            if relative == span.native.location { return located.textStart + span.source.location }
            if relative == span.native.upperBound { return located.textStart + span.source.upperBound }
        }
        if relative == located.row.nativeContentLength { return located.textStart + located.row.textLength }
        if relative == located.row.nativeLength { return located.textStart + located.row.baseSourceLength }
        return nil
    }
    func sourceCoverage(of nativeRange: NSRange) -> NSRange? {
        guard nativeRange.length > 0, valid(nativeRange, length: nativeLength),
              let first = row(containingNative: nativeRange.location),
              let last = row(containingNative: nativeRange.upperBound - 1) else { return nil }
        let end: Int
        if nativeRange.upperBound == nativeLength { end = sourceLength }
        else if let next = row(containingNative: last.nativeRange.upperBound) { end = next.textStart }
        else { return nil }
        return NSRange(location: first.sourceStart, length: end - first.sourceStart)
    }
    func reset(rows: [WritingSerializedRow]) {
        root = nil
        for row in rows where row.nativeLength > 0 { root = merge(root, node(row)) }
    }
    @discardableResult
    func replace(_ nativeRange: NSRange, with rows: [WritingSerializedRow]) -> Bool {
        guard valid(nativeRange, length: nativeLength), rows.allSatisfy({ $0.nativeLength >= 0 }),
              let first = rank(nativeRange.location), let end = rank(nativeRange.upperBound) else { return false }
        let (before, remaining) = split(root, count: first)
        let (_, after) = split(remaining, count: end - first)
        var replacement: Node?
        for row in rows where row.nativeLength > 0 { replacement = merge(replacement, node(row)) }
        root = merge(merge(before, replacement), after)
        return true
    }
    func row(containingNative offset: Int) -> Located? {
        guard nativeLength > 0, offset >= 0, offset <= nativeLength else { return nil }
        let point = min(offset, nativeLength - 1)
        var next = root, source = 0, native = 0, previousCode = false
        while let current = next {
            let leftNative = current.left?.nativeLength ?? 0
            let leftSource = current.left?.sourceLength(previousCode: previousCode) ?? 0
            let rowNative = native + leftNative, rowSource = source + leftSource
            let previous = current.left?.lastCode ?? previousCode
            let textStart = rowSource + (previous != current.row.isCode ? 4 : 0)
            if point < rowNative { next = current.left }
            else if point < rowNative + current.row.nativeLength {
                return Located(row: current.row, nativeRange: NSRange(location: rowNative, length: current.row.nativeLength),
                               sourceStart: rowSource, textStart: textStart)
            } else {
                source = textStart + current.row.baseSourceLength; native = rowNative + current.row.nativeLength
                previousCode = current.row.isCode; next = current.right
            }
        }
        return nil
    }
    func row(containingSource point: Int) -> Located? {
        guard point >= 0, point < sourceLength else { return nil }
        var next = root, source = 0, native = 0, previousCode = false
        while let current = next {
            let leftSource = current.left?.sourceLength(previousCode: previousCode) ?? 0
            let leftNative = current.left?.nativeLength ?? 0
            let rowSource = source + leftSource, rowNative = native + leftNative
            let previous = current.left?.lastCode ?? previousCode
            let textStart = rowSource + (previous != current.row.isCode ? 4 : 0)
            if point < rowSource { next = current.left }
            else if point < textStart + current.row.baseSourceLength {
                return Located(row: current.row, nativeRange: NSRange(location: rowNative, length: current.row.nativeLength),
                               sourceStart: rowSource, textStart: textStart)
            } else {
                source = textStart + current.row.baseSourceLength; native = rowNative + current.row.nativeLength
                previousCode = current.row.isCode; next = current.right
            }
        }
        return nil
    }
    func sourceIntervals(in range: NSRange) -> (eligible: [NSRange], blocked: [NSRange]) {
        var cursor = range.location, eligible: [NSRange] = [], blocked: [NSRange] = []
        while cursor < range.upperBound, let located = row(containingSource: cursor) {
            if located.row.eligible && !located.row.isCode {
                for span in located.row.spans {
                    let local = span.body != nil && !span.style.code ? span.body! : span.source
                    let global = NSRange(location: located.textStart + local.location, length: local.length)
                    let clipped = NSIntersectionRange(global, range)
                    if clipped.length > 0 {
                        if span.body != nil && !span.style.code { eligible.append(clipped) }
                        else { blocked.append(clipped) }
                    }
                }
                if located.row.hasLineFeed {
                    let newline = NSIntersectionRange(NSRange(location: located.textStart + located.row.textLength, length: 1), range)
                    if newline.length > 0 { eligible.append(newline) }
                }
            } else {
                let opaque = NSIntersectionRange(NSRange(location: located.textStart, length: located.row.baseSourceLength), range)
                if opaque.length > 0 { blocked.append(opaque) }
            }
            let end = located.textStart + located.row.baseSourceLength
            guard end > cursor else { break }
            cursor = end
        }
        return (eligible, blocked)
    }
    func nativeRange(forSource range: NSRange) -> NSRange? {
        guard range.length > 0, valid(range, length: sourceLength), let located = row(containingSource: range.location),
              located.row.eligible, !located.row.isCode, range.location >= located.textStart,
              range.upperBound <= located.textStart + located.row.textLength else { return nil }
        let relative = NSRange(location: range.location - located.textStart, length: range.length)
        var cursor = relative.location, result: NSRange?
        for span in located.row.spans {
            guard let body = span.body else { continue }
            let clipped = NSIntersectionRange(body, relative)
            guard clipped.length > 0 else { continue }
            guard !span.style.code, body.length == span.native.length, clipped.location == cursor else { return nil }
            let native = NSRange(location: located.nativeRange.location + span.native.location + clipped.location - body.location,
                                 length: clipped.length)
            if let previous = result {
                guard previous.upperBound == native.location else { return nil }
                result = NSRange(location: previous.location, length: previous.length + native.length)
            } else { result = native }
            cursor = clipped.upperBound
        }
        return cursor == relative.upperBound ? result : nil
    }
    private func valid(_ range: NSRange, length: Int) -> Bool {
        range.location >= 0 && range.location <= length && range.length >= 0 && range.length <= length - range.location
    }
    private func node(_ row: WritingSerializedRow) -> Node {
        random ^= random << 13; random ^= random >> 7; random ^= random << 17
        return Node(row, priority: random)
    }
    private func rank(_ offset: Int) -> Int? {
        if offset == nativeLength { return root?.count ?? 0 }
        var next = root, remaining = offset, rank = 0
        while let current = next {
            let leftLength = current.left?.nativeLength ?? 0, leftCount = current.left?.count ?? 0
            if remaining < leftLength { next = current.left }
            else if remaining == leftLength { return rank + leftCount }
            else if remaining < leftLength + current.row.nativeLength { return nil }
            else { remaining -= leftLength + current.row.nativeLength; rank += leftCount + 1; next = current.right }
        }
        return nil
    }
    private func split(_ node: Node?, count: Int) -> (Node?, Node?) {
        guard let node else { return (nil, nil) }
        let left = node.left?.count ?? 0
        if count <= left {
            let (before, after) = split(node.left, count: count)
            return (before, node.copy(left: after, right: node.right))
        }
        let (before, after) = split(node.right, count: count - left - 1)
        return (node.copy(left: node.left, right: before), after)
    }
    private func merge(_ left: Node?, _ right: Node?) -> Node? {
        guard let left else { return right }; guard let right else { return left }
        if left.priority < right.priority { return left.copy(left: left.left, right: merge(left.right, right)) }
        return right.copy(left: merge(left, right.left), right: right.right)
    }
}
