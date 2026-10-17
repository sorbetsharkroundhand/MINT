import Foundation

struct DocumentOutlineProjection: Equatable, Sendable {
    struct Heading: Equatable, Sendable, Identifiable {
        let id: Int
        let level: Int
        let title: String
        let quote: String
        let sourceRange: Range<Int>
    }
    let revision: String
    let headings: [Heading]
    /// Source preparation only. Scene segmentation and persistent identities are unrelated.
    static func build(_ source: String, revision: String? = nil) async throws -> Self {
        try Task.checkCancellation()
        var headings: [Heading] = []
        var fence: (marker: Unicode.Scalar, count: Int)?
        var math = false
        var lineStart = source.startIndex, lineOffset = 0, offset = 0, budget = 0
        func finishLine(at end: String.Index, offset endOffset: Int) {
            let line = source[lineStart..<end]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = trimmed.unicodeScalars.first
            let fenceCount = marker.map { character in trimmed.unicodeScalars.prefix { $0 == character }.count } ?? 0
            if let open = fence {
                if marker == open.marker, fenceCount >= open.count,
                   trimmed.unicodeScalars.dropFirst(fenceCount).allSatisfy({ CharacterSet.whitespaces.contains($0) }) {
                    fence = nil
                }
                return
            }
            if math {
                if trimmed.hasSuffix("$$") { math = false }
                return
            }
            if let marker, marker == "`" || marker == "~", fenceCount >= 3 {
                fence = (marker, fenceCount); return
            }
            if trimmed.hasPrefix("$$"), !trimmed.dropFirst(2).hasPrefix("$") {
                math = trimmed == "$$" || !trimmed.hasSuffix("$$")
                return
            }
            let quote = boundedPrefix(line)
            guard let (level, title) = DocumentOutline.headingLine(quote[...]), !title.isEmpty else { return }
            headings.append(Heading(id: lineOffset, level: level, title: boundedPrefix(title),
                quote: quote, sourceRange: lineOffset..<endOffset))
        }
        let scalars = source.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index], width = scalar.utf16.count
            if budget + width > 2048 {
                await Task.yield(); try Task.checkCancellation(); budget = 0
            }
            let next = scalars.index(after: index)
            if scalar == "\n" {
                finishLine(at: index, offset: offset)
                lineStart = next; lineOffset = offset + width
            }
            offset += width; budget += width; index = next
        }
        finishLine(at: source.endIndex, offset: offset)
        try Task.checkCancellation()
        return Self(revision: revision ?? DocumentOutline.stableHash(source), headings: headings)
    }
    private static func boundedPrefix(_ text: some StringProtocol) -> String {
        var result = "", length = 0
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            guard length + width <= 256 else { break }
            result.unicodeScalars.append(scalar); length += width
        }
        return result
    }
    func currentHeading(at sourceOffset: Int) -> Heading? {
        var low = 0, high = headings.count
        while low < high {
            let mid = low + (high - low) / 2
            if headings[mid].id <= sourceOffset { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? headings[low - 1] : nil
    }
}

/// Work and original-byte memoization stay on this background actor, never in a view callback.
actor DocumentOutlineProjector {
    private struct Cached {
        let key: ProjectDocumentKey
        let source: String
        let projection: DocumentOutlineProjection
    }
    private var cache: [Cached] = []
    private(set) var buildCount = 0
    var retainedCount: Int { cache.count }
    func project(_ snapshot: ProjectDocumentSnapshot) async throws -> DocumentOutlineProjection {
        try Task.checkCancellation()
        let revision = DocumentOutline.stableHash(snapshot.body)
        if let index = cache.firstIndex(where: {
            $0.key == snapshot.identity.key && $0.projection.revision == revision
                && $0.source.utf16.elementsEqual(snapshot.body.utf16)
        }) {
            let hit = cache.remove(at: index); cache.append(hit); return hit.projection
        }
        buildCount += 1
        let projection = try await DocumentOutlineProjection.build(snapshot.body, revision: revision)
        try Task.checkCancellation()
        cache.append(Cached(key: snapshot.identity.key, source: snapshot.body, projection: projection))
        if cache.count > 2 { cache.removeFirst(cache.count - 2) }
        return projection
    }
}
