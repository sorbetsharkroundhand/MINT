import AppKit
import CryptoKit

struct StoryMapSourceTarget: Equatable, Sendable {
    let identity: ProjectRuntimeIdentity
    let revision: String
    let row: StoryMapProjection.Row
    func matchesSource(_ source: String) -> Bool {
        let text = source as NSString, count = row.evidence.quote.utf16.count, offset = row.sourceRange.lowerBound
        guard row.evidence.documentID == identity.key.documentID, row.evidence.utf16Hint == offset,
              offset >= 0, row.sourceRange.upperBound <= text.length, (1...1024).contains(count),
              count <= row.sourceRange.count, row.kind == .scene || count == row.sourceRange.count,
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == revision else { return false }
        return text.substring(with: NSRange(location: offset, length: count)).utf16.elementsEqual(row.evidence.quote.utf16)
    }
}

@MainActor
extension BlockTextView {
    private func ownsStoryMapSource(_ identity: ProjectRuntimeIdentity) -> Bool {
        writingDocumentIdentity == .project(identity.key) && writingRuntimeIdentityProvider?() == identity
            && !hasMarkedText() && writingProjectionCapture.compositionDepth == 0
            && writingProjectionCapture.mappedIdentity == identity
            && writingProjectionCapture.mappedRevision == writingNativeRevision
    }
    func storyMapSourcePosition(identity: ProjectRuntimeIdentity) -> Int? {
        guard ownsStoryMapSource(identity) else { return nil }
        return writingProjectionCapture.nativeRows.sourceOffset(forNative: selectedRange().location)
    }
    func applyStoryMapSource(_ target: StoryMapSourceTarget) -> Bool {
        guard ownsStoryMapSource(target.identity), target.matchesSource(serialize()) else { return false }
        let source = target.row.sourceRange.lowerBound
        if target.row.kind == .event {
            guard let native = nativeRange(forSource: .init(location: source, length: target.row.evidence.quote.utf16.count), revision: writingNativeRevision) else { return false }
            restoreSelection(to: native.nsRange)
        } else if let row = writingProjectionCapture.nativeRows.row(containingSource: source), row.textStart == source {
            restoreSelection(to: NSRange(location: row.nativeRange.location, length: 0))
        } else {
            guard let first = target.row.evidence.quote.first,
                  let native = nativeRange(forSource: .init(location: source, length: String(first).utf16.count), revision: writingNativeRevision) else { return false }
            restoreSelection(to: NSRange(location: native.location, length: 0))
        }
        return true
    }
}
