import AppKit

struct SourceWritingPosition: Equatable, Sendable {
    let key: ProjectDocumentKey
    let manuscript: String
    let nativeText: String
    let selection: NSRange
    let scrollOrigin: NSPoint
    let sourceCursor: Int
}

enum SourceNavigationIntent: Equatable, Sendable {
    case passage(SourceSearchHit)
    case returnTo(SourceWritingPosition)
    var key: ProjectDocumentKey {
        switch self {
        case .passage(let hit): ProjectDocumentKey(projectID: hit.projectID, documentID: hit.documentID)
        case .returnTo(let point): point.key
        }
    }
}

@MainActor
extension ProjectEditorRequests {
    func captureSourcePosition(in session: ProjectSession) -> SourceWritingPosition? {
        guard session.isEditorEditable, let key = session.runtimeIdentity?.key,
            nativeEditorKey == key, let view = nativeEditor, !view.hasMarkedText(),
            let manuscript = session.selectedDocument?.body, view.serialize() == manuscript else { return nil }
        return SourceWritingPosition(key: key, manuscript: manuscript, nativeText: view.string,
            selection: view.selectedRange(), scrollOrigin: view.enclosingScrollView?.contentView.bounds.origin ?? .zero,
            sourceCursor: view.sourceCursorOffset())
    }

    @discardableResult
    func jump(to hit: SourceSearchHit, in session: ProjectSession) -> Bool {
        guard let point = captureSourcePosition(in: session),
            let project = session.activeProject, project.id == hit.projectID,
            !project.trashedDocumentIDs.contains(hit.documentID),
            let document = project.documents.first(where: { $0.id == hit.documentID }),
            SourceAnchor.exactRange(for: hit.evidence, in: document.body, revision: hit.revision) != nil else {
            sourceNavigationError = "원문이 변경되었습니다. 다시 검색하세요."
            return false
        }
        if sourceReturnPoint?.key.projectID != point.key.projectID { sourceReturnPoint = point }
        sourceNavigationError = nil
        session.selectDocument(hit.documentID)
        issueSourceNavigation(.passage(hit))
        return true
    }

    @discardableResult
    func returnToWriting(in session: ProjectSession) -> Bool {
        guard session.isEditorEditable, nativeEditor?.hasMarkedText() == false,
            let point = sourceReturnPoint, let project = session.activeProject,
            point.key.projectID == project.id, !project.trashedDocumentIDs.contains(point.key.documentID),
            project.documents.first(where: { $0.id == point.key.documentID })?.body == point.manuscript else {
            sourceNavigationError = "이전 집필 위치의 문서가 변경되었습니다."
            return false
        }
        session.selectDocument(point.key.documentID)
        sourceNavigationError = nil
        issueSourceNavigation(.returnTo(point))
        return true
    }

    private func issueSourceNavigation(_ source: SourceNavigationIntent) {
        searchJump = EditorSearchJump(documentID: source.key.documentID, query: "",
            sequence: (searchJump?.sequence ?? 0) + 1, source: source)
        focusEditor()
    }

    func didNavigateSource(_ succeeded: Bool, jump: EditorSearchJump) {
        guard searchJump == jump else { return }
        if !succeeded { sourceNavigationError = "원문 위치를 확인할 수 없습니다. 다시 검색하세요." }
        else if case .returnTo = jump.source { sourceReturnPoint = nil }
    }
}

@MainActor
extension BlockTextView {
    /// Markdown offsets never become TextKit offsets. Match occurrence order only when
    /// all original occurrences are also present in the rendered native text.
    @discardableResult
    func applySourceNavigation(_ intent: SourceNavigationIntent) -> Bool {
        guard !hasMarkedText() else { return false }
        switch intent {
        case .returnTo(let point):
            guard serialize() == point.manuscript, string == point.nativeText else { return false }
            restoreSelection(to: point.selection)
            if let scroll = enclosingScrollView {
                var bounds = scroll.contentView.bounds; bounds.origin = point.scrollOrigin
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        case .passage(let hit):
            let manuscript = serialize()
            guard let quote = SourceAnchor.exactRange(for: hit.evidence, in: manuscript, revision: hit.revision),
                let oldQuoteStart = hit.evidence.utf16Hint else { return false }
            let location = quote.location + hit.matchedRange.location - oldQuoteStart
            func matches(_ text: String) -> [NSRange] {
                let ns = text as NSString; var ranges: [NSRange] = [], start = 0
                while start < ns.length {
                    let range = ns.range(of: hit.matchedText, options: .caseInsensitive,
                        range: NSRange(location: start, length: ns.length - start))
                    guard range.location != NSNotFound else { break }
                    ranges.append(range); start = NSMaxRange(range)
                }
                return ranges
            }
            let originals = matches(manuscript), native = matches(string)
            guard originals.count == native.count,
                let index = originals.firstIndex(where: { $0.location == location }) else { return false }
            restoreSelection(to: native[index])
        }
        window?.makeFirstResponder(self)
        refreshActiveLineHighlight()
        return true
    }
}
