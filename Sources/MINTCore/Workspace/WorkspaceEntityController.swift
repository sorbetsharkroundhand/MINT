import AppKit
import Combine
import CryptoKit
import SwiftUI

@MainActor final class WorkspaceEntityController: ObservableObject {
    struct Peek: Equatable { let name: String; let note: String; let aliases: String; let reference: OriginalSourceReference }
    @Published private(set) var peek: Peek?
    private weak var session: ProjectSession?
    private weak var requests: ProjectEditorRequests?
    private var hideTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var records: [CharacterCard] = []
    private var cachedData: [String: Data] = [:]
    private var projectID: WritingProjectID?
    private var provenNativeRevision: UInt64?
    private var provenNativeRange: NSRange?
    private var subscriptions: Set<AnyCancellable> = []
    init(session: ProjectSession, requests: ProjectEditorRequests) {
        self.session = session; self.requests = requests
        session.$activeProject.sink { [weak self] project in
            guard let self else { return }
            self.hide()
            guard let project else { self.records = []; return }
            guard project.id != self.projectID || project.userData != self.cachedData else { return }
            self.projectID = project.id; self.cachedData = project.userData
            var seen: Set<UUID> = []
            self.records = project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }.flatMap { document in
                (try? WriterDocumentData.decode(project.userData[WriterDocumentData.key(for: document.id)], documentID: document.id).characters) ?? []
            }.filter { !$0.name.isEmpty && $0.autoRegistered != true && seen.insert($0.id).inserted }
        }.store(in: &subscriptions)
        requests.spatialWorkspace?.$whisperTyping.sink { [weak self] value in if value { self?.hide() } }.store(in: &subscriptions)
        requests.spatialWorkspace?.$isDragging.sink { [weak self] value in if value { self?.hide() } }.store(in: &subscriptions)
    }
    func hover(editor: BlockTextView, key: ProjectDocumentKey, nativeOffset: Int) {
        guard let session, session.isEditorEditable, session.activeProject?.id == key.projectID,
              requests?.spatialWorkspace?.whisperTyping != true, requests?.spatialWorkspace?.isDragging != true,
              !editor.hasMarkedText(), let document = session.document(key.documentID) else { scheduleHide(); return }
        let native = editor.string as NSString
        guard nativeOffset >= 0, nativeOffset < native.length else { scheduleHide(); return }
        let line = native.paragraphRange(for: .init(location: nativeOffset, length: 0))
        for card in records {
            for term in [card.name] + card.aliases.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !term.isEmpty && term.count <= 80 {
                var start = line.location
                while start < line.upperBound {
                    let range = native.range(of: term, range: .init(location: start, length: line.upperBound - start))
                    guard range.location != NSNotFound else { break }; start = range.upperBound
                    guard NSLocationInRange(nativeOffset, range) else { continue }
                    let original = document.body as NSString
                    if peek?.name == card.name && peek?.reference.key == key && provenNativeRevision == editor.writingNativeRevision && provenNativeRange == range {
                        keepAlive(); return
                    }
                    guard editor.serialize().utf16.elementsEqual(document.body.utf16) else { continue }
                    let start = editor.sourceCursorOffset(at: range.location), end = editor.sourceCursorOffset(at: range.upperBound)
                    let source = NSRange(location: start, length: end - start)
                    guard start >= 0, end > start, end <= original.length, source.length <= 2048,
                          original.rangeOfComposedCharacterSequences(for: source) == source else { continue }
                    provenNativeRevision = editor.writingNativeRevision; provenNativeRange = range
                    let reference = OriginalSourceReference(key: key, revision: SHA256.hash(data: Data(document.body.utf8)).map { String(format: "%02x", $0) }.joined(),
                        evidence: .init(documentID: key.documentID, quote: original.substring(with: source), utf16Hint: source.location), selection: .passage)
                    let next = Peek(name: card.name, note: card.note, aliases: card.aliases, reference: reference)
                    keepAlive(); requests?.spatialWorkspace?.resonatingTerm = term
                    if peek != next { peek = next; present(next, editor: editor, range: range) }
                    return
                }
            }
        }
        scheduleHide()
    }
    func keepAlive() { hideTask?.cancel(); hideTask = nil }
    func scheduleHide() {
        guard hideTask == nil, peek != nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(190)); guard !Task.isCancelled else { return }; self?.hide()
        }
    }
    func hide() {
        keepAlive(); peek = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.close() }
        panel = nil; requests?.spatialWorkspace?.resonatingTerm = nil
    }
    private func present(_ value: Peek, editor: BlockTextView, range: NSRange) {
        guard let parent = editor.window else { return }
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil); panel.close() }
        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 250, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = true
        let theme = editor.palette
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 8) {
            Text("인물").font(.system(size: 9)).foregroundStyle(theme.blueC)
            Text(value.name).font(.system(size: 16, weight: .semibold, design: .serif))
            if !value.note.isEmpty { Text(value.note).font(.system(size: 11)).lineLimit(4) }
            if !value.aliases.isEmpty { Text(value.aliases).font(.system(size: 10)).foregroundStyle(theme.ink3C) }
            Button("원문 보기") { [weak self] in
                guard let self, let session = self.session, let requests = self.requests else { return }
                let inspection = ProjectSourceInspection(session: session)
                if let token = inspection.capture() { requests.jump(to: value.reference, inspection: inspection, token: token, in: session) }
                self.hide()
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(theme.blueC)
        }.padding(14).frame(width: 250, alignment: .leading).foregroundStyle(theme.inkC).background(theme.cardSurfaceC)
            .onHover { [weak self] inside in if inside { self?.keepAlive() } else { self?.scheduleHide() } })
        let anchor = editor.firstRect(forCharacterRange: range, actualRange: nil)
        let visible = parent.screen?.visibleFrame ?? parent.frame
        panel.setFrameOrigin(.init(x: max(visible.minX, min(visible.maxX - 250, anchor.midX - 125)), y: max(visible.minY, anchor.minY - 156)))
        parent.addChildWindow(panel, ordered: .above); panel.orderFront(nil); self.panel = panel
    }
}
