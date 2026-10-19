import AppKit
import Combine

/// Workspace-owned gestures/decorations. The editor exposes only native presentation hooks.
@MainActor final class WorkspaceEditorInteraction: EditorWorkspaceInteraction {
    let key: ProjectDocumentKey
    func polishSelection() { if let editor { requests?.workspacePolish?(editor) } }
    func excerptSelection() { if let editor { requests?.workspaceExcerpt?(editor) } }
    private weak var editor: BlockTextView?
    private weak var session: ProjectSession?
    private weak var requests: ProjectEditorRequests?
    private weak var model: SpatialWorkspaceController?
    private var subscription: AnyCancellable?
    private var hovered: Int?
    private var drag: (source: WorkspaceParagraphAnchor, start: CGPoint, active: Bool)?
    private var target: WorkspaceParagraphAnchor?
    private var after = false
    private weak var targetEditor: BlockTextView?
    private var pill: NSPanel?
    private var flashRange: NSRange?
    private var flashTask: Task<Void, Never>?
    func flash(_ range: NSRange) {
        flashTask?.cancel(); flashRange = range; editor?.needsDisplay = true
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900)); guard !Task.isCancelled else { return }
            self?.flashRange = nil; self?.editor?.needsDisplay = true
        }
    }
    private let pointerSpring = WorkspacePointerSpring()
    private var preview: (range: NSRange, style: NSParagraphStyle, text: String, after: Bool)?
    private var centering = false

    init(editor: BlockTextView, key: ProjectDocumentKey, session: ProjectSession,
         requests: ProjectEditorRequests, model: SpatialWorkspaceController) {
        self.editor = editor; self.key = key; self.session = session; self.requests = requests; self.model = model
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.layoutDidChange(); self?.editor?.needsDisplay = true }
        }
        layoutDidChange()
    }

    func paragraphRect(at offset: Int) -> CGRect? {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return nil }
        manager.ensureLayout(for: container)
        let native = nativeParagraph(at: offset)
        var rect: CGRect
        if native.length == 0 { rect = manager.extraLineFragmentUsedRect }
        else {
            let glyphs = manager.glyphRange(forCharacterRange: native, actualCharacterRange: nil)
            rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        }
        rect = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        rect.origin.x = editor.textContainerOrigin.x
        rect.size.width = max(10, editor.bounds.width - editor.textContainerOrigin.x * 2)
        if rect.height < 10 { rect.size.height = editor.baseFontSize * 1.72 + editor.lineSpacing }
        return rect
    }
    func paragraphGrip(at offset: Int) -> CGRect? {
        guard let editor, let rect = paragraphRect(at: offset) else { return nil }
        return CGRect(x: editor.textContainerOrigin.x - 22, y: rect.midY - 11, width: 16, height: 22)
    }
    func paragraphOpacity(at offset: Int) -> CGFloat {
        guard let editor, model?.focusDimming == true else { return 1 }
        let range = nativeParagraph(at: offset)
        if session?.selectedDocumentID == key.documentID,
           nativeParagraph(at: editor.selectedRange().location).location == range.location { return 1 }
        return hovered.map { nativeParagraph(at: $0).location == range.location } == true ? 0.68 : 0.24
    }
    private func nativeParagraph(at offset: Int) -> NSRange {
        guard let editor else { return NSRange(location: 0, length: 0) }
        let ns = editor.string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        var range = ns.paragraphRange(for: NSRange(location: min(max(0, offset), ns.length - 1), length: 0))
        let block = editor.blockInfo(in: range).block
        if block == .code || block == .math {
            while range.location > 0 {
                let previous = ns.paragraphRange(for: NSRange(location: range.location - 1, length: 0))
                guard editor.blockInfo(in: previous).block == block else { break }
                range = NSUnionRange(previous, range)
            }
            while range.upperBound < ns.length {
                let next = ns.paragraphRange(for: NSRange(location: range.upperBound, length: 0))
                guard editor.blockInfo(in: next).block == block else { break }
                range = NSUnionRange(range, next)
            }
        }
        return range
    }
    private func offset(at point: CGPoint) -> Int {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return 0 }
        // Gutter grips are outside the text container. Hit the same visual line at
        // its leading glyph instead of asking TextKit to resolve an out-of-bounds X.
        let translated = CGPoint(x: max(1, point.x - editor.textContainerOrigin.x), y: point.y - editor.textContainerOrigin.y)
        return min(editor.string.utf16.count, manager.characterIndex(for: translated, in: container, fractionOfDistanceBetweenInsertionPoints: nil))
    }
    private func anchor(at offset: Int) -> WorkspaceParagraphAnchor? {
        guard let editor, !editor.hasMarkedText(), let body = session?.document(key.documentID)?.body else { return nil }
        // Explicit user drag, outside the typing/prediction path. Prove the native source once.
        guard editor.serialize().utf16.elementsEqual(body.utf16) else { return nil }
        let native = nativeParagraph(at: offset)
        let range = native.length == 0 ? NSRange(location: 0, length: 0)
            : editor.originalParagraphRange(forNative: native)
        guard let range else { return nil }
        return WorkspaceParagraphAnchor(key: key, body: body, range: range)
    }

    func mouseDown(_ event: NSEvent) -> Bool {
        guard let editor, let session, event.buttonNumber == 0, !editor.hasMarkedText(),
              model?.isDragging != true, model?.whisperTyping != true else { return false }
        let point = editor.convert(event.locationInWindow, from: nil), position = offset(at: point)
        guard let grip = paragraphGrip(at: position), grip.contains(point) else { return false }
        session.selectDocument(key.documentID); editor.window?.makeFirstResponder(editor)
        guard let anchor = anchor(at: position), anchor.range.length > 0 else { return false }
        drag = (anchor, event.locationInWindow, false)
        requests?.workspaceHoverEnd?(); editor.hideSelectionToolbar()
        return true
    }
    func mouseDragged(_ event: NSEvent) -> Bool {
        guard var drag, let editor, let requests else { return false }
        editor.enclosingSpatialCanvas?.autoscroll(with: event)
        if !drag.active {
            guard hypot(event.locationInWindow.x - drag.start.x, event.locationInWindow.y - drag.start.y) > 6 else { return true }
            drag.active = true; NSCursor.closedHand.push()
        }
        self.drag = drag
        var nextEditor: BlockTextView?, nextAnchor: WorkspaceParagraphAnchor?, nextAfter = false
        for (candidateKey, candidate) in requests.registeredEditors where candidateKey.projectID == key.projectID && candidate.window === editor.window {
            let point = candidate.convert(event.locationInWindow, from: nil)
            guard candidate.visibleRect.contains(point), !candidate.hasMarkedText(),
                  let interaction = candidate.workspaceInteraction as? WorkspaceEditorInteraction else { continue }
            candidate.autoscroll(with: event)
            let position = interaction.offset(at: point)
            guard let rect = interaction.paragraphRect(at: position), let anchor = interaction.anchor(at: position) else { continue }
            if anchor.key == drag.source.key && NSIntersectionRange(anchor.range, drag.source.range).length > 0 { break }
            nextEditor = candidate; nextAnchor = anchor; nextAfter = point.y > rect.midY
            if targetEditor !== candidate || target?.range != anchor.range || after != nextAfter {
                clearTargetPreview(); interaction.showDropPreview(at: position, after: nextAfter)
            }
            break
        }
        if nextEditor == nil { clearTargetPreview() }
        targetEditor = nextEditor; target = nextAnchor; after = nextAfter
        showPill(event, copying: event.modifierFlags.contains(.option))
        return true
    }
    func mouseUp(_ event: NSEvent) -> Bool {
        guard let drag else { return false }
        let target = target
        clearTargetPreview(); self.drag = nil; self.target = nil; targetEditor = nil
        pointerSpring.stop(); pill?.orderOut(nil); pill?.close(); pill = nil
        if drag.active { NSCursor.pop() }
        guard drag.active, let target, let session, let requests else { return true }
        do {
            try WorkspaceParagraphTransfer.perform(source: drag.source, target: target, after: after,
                copy: event.modifierFlags.contains(.option), session: session, requests: requests,
                undoManager: requests.editor(for: target.key)?.undoManager)
        } catch { session.reportError(error) }
        editor?.needsDisplay = true
        return true
    }
    func mouseMoved(_ event: NSEvent) {
        guard let editor else { return }
        model?.notePointer(at: editor.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow)
        hovered = offset(at: editor.convert(event.locationInWindow, from: nil)); editor.needsDisplay = true
        if model?.whisperTyping != true, drag == nil, model?.isDragging != true, let hovered {
            requests?.workspaceHover?(editor, key, hovered)
        }
    }
    func mouseExited() { hovered = nil; editor?.needsDisplay = true; requests?.workspaceHoverEnd?() }
    func keyDown(_ event: NSEvent) {
        if event.keyCode == 53, drag != nil { cancelDrag(); return }
        guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option), !(event.characters ?? "").isEmpty else { return }
        model?.noteTyping(at: NSEvent.mouseLocation); requests?.workspaceHoverEnd?()
    }
    func selectionDidChange() {
        editor?.needsDisplay = true; centerTypewriter()
        if let editor, session?.selectedDocumentID == key.documentID, !editor.hasMarkedText() {
            let range = nativeParagraph(at: editor.selectedRange().location)
            model?.activeParagraph = (editor.string as NSString).substring(with: range)
        }
    }
    func layoutDidChange() {
        guard let editor else { return }
        if let scroll = editor.enclosingScrollView as? WritingScrollView {
            scroll.workspacePresentationEnabled = true; scroll.workspaceTypewriter = model?.typewriter == true
            scroll.updateWorkspaceInsets()
        }
        if editor.textContainerInset.height != 32 {
            editor.textContainerInset = CGSize(width: max(editor.bounds.width < 640 ? 28 : 48, (editor.bounds.width - 680) / 2), height: 32)
        }
        centerTypewriter()
    }
    private func centerTypewriter() {
        guard !centering, model?.typewriter == true, let editor, !editor.hasMarkedText(),
              session?.selectedDocumentID == key.documentID, let scroll = editor.enclosingScrollView,
              let rect = paragraphRect(at: editor.selectedRange().location) else { return }
        centering = true; defer { centering = false }
        let clip = scroll.contentView
        let minimum = -scroll.contentInsets.top
        let maximum = max(minimum, editor.bounds.height - clip.bounds.height + scroll.contentInsets.bottom)
        let y = min(maximum, max(minimum, rect.midY - clip.bounds.height / 2))
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y)); scroll.reflectScrolledClipView(clip)
    }

    private func visibleParagraphs() -> [NSRange] {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return [] }
        let rect = editor.visibleRect.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var seen: Set<Int> = []
        return editor.indexedMediaParagraphs(in: characters).compactMap {
            let range = nativeParagraph(at: $0.range.location)
            return seen.insert(range.location).inserted ? range : nil
        }
    }
    func drawBackground(_ dirtyRect: CGRect) {
        if let editor, let flashRange, let rect = paragraphRect(at: flashRange.location), rect.intersects(dirtyRect) {
            editor.palette.activeBg.setFill(); NSBezierPath(roundedRect: rect.insetBy(dx: -12, dy: -3), xRadius: 8, yRadius: 8).fill()
        }
        guard let editor, let term = model?.resonatingTerm, !term.isEmpty else { return }
        for range in visibleParagraphs() {
            guard (editor.string as NSString).substring(with: range).contains(term), let rect = paragraphRect(at: range.location), rect.intersects(dirtyRect) else { continue }
            editor.palette.hover.setFill(); NSBezierPath(roundedRect: rect.insetBy(dx: -12, dy: -3), xRadius: 8, yRadius: 8).fill()
        }
    }
    func draw(_ dirtyRect: CGRect) {
        guard let editor else { return }
        for range in visibleParagraphs() {
            guard let rect = paragraphRect(at: range.location), rect.intersects(dirtyRect) else { continue }
            let opacity = paragraphOpacity(at: range.location)
            if opacity < 1 {
                editor.palette.editorSurface.withAlphaComponent(1 - opacity).setFill()
                rect.insetBy(dx: -12, dy: -3).fill()
            }
            if model?.whisperTyping != true, hovered.map({ nativeParagraph(at: $0).location == range.location }) == true,
               let grip = paragraphGrip(at: range.location) {
                editor.palette.ink3.withAlphaComponent(0.45).setFill()
                for row in 0..<3 { for column in 0..<2 {
                    NSBezierPath(ovalIn: CGRect(x: grip.midX - 4 + CGFloat(column) * 5,
                        y: grip.midY - 5 + CGFloat(row) * 4, width: 1.7, height: 1.7)).fill()
                } }
            }
        }
        if let preview, let rect = paragraphRect(at: preview.range.location) {
            editor.palette.ink3.withAlphaComponent(0.32).setFill()
            CGRect(x: rect.minX, y: (preview.after ? rect.maxY + 12 : rect.minY - 12), width: rect.width, height: 1.5).fill()
        }
    }
    private func showDropPreview(at position: Int, after: Bool) {
        guard let editor, !editor.hasMarkedText(), let storage = editor.textStorage else { return }
        clearDropPreview()
        let range = nativeParagraph(at: position)
        guard range.length > 0, range.location < storage.length else { return }
        let original = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
        let changed = original.mutableCopy() as! NSMutableParagraphStyle
        if after { changed.paragraphSpacing += 26 } else { changed.paragraphSpacingBefore += 26 }
        preview = (range, original, editor.string, after)
        storage.addAttribute(.paragraphStyle, value: changed, range: range); editor.needsDisplay = true
    }
    private func clearDropPreview() {
        guard let preview, let editor else { return }
        self.preview = nil
        if editor.string.utf16.elementsEqual(preview.text.utf16), preview.range.upperBound <= editor.string.utf16.count {
            editor.textStorage?.addAttribute(.paragraphStyle, value: preview.style, range: preview.range)
        }
        editor.needsDisplay = true
    }
    private func clearTargetPreview() { (targetEditor?.workspaceInteraction as? WorkspaceEditorInteraction)?.clearDropPreview() }
    private func showPill(_ event: NSEvent, copying: Bool) {
        guard let editor, let drag else { return }
        if pill == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 58),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.ignoresMouseEvents = true; panel.level = .floating
            pill = panel
        }
        let text = (drag.source.body as NSString).substring(with: drag.source.range)
        let label = NSTextField(wrappingLabelWithString: (copying ? "문단 복제" : "문단 이동 · ⌥ 복제") + "\n" + String(text.prefix(120)))
        label.font = MintFonts.ui(11); label.textColor = editor.palette.ink; label.maximumNumberOfLines = 3
        label.frame = CGRect(x: 12, y: 6, width: 296, height: 46)
        let surface = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 58)); surface.wantsLayer = true
        surface.layer?.cornerRadius = 10; surface.layer?.backgroundColor = editor.palette.pill.cgColor
        surface.addSubview(label); pill?.contentView = surface
        let point = editor.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        if let pill { pointerSpring.move(pill, to: CGPoint(x: point.x + 14, y: point.y - 40), reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        pill?.orderFrontRegardless()
    }
    private func cancelDrag() {
        clearTargetPreview(); clearDropPreview()
        if drag?.active == true { NSCursor.pop() }
        drag = nil; target = nil; targetEditor = nil
        pointerSpring.stop(); pill?.orderOut(nil); pill?.close(); pill = nil
    }
    func detach() { cancelDrag(); flashTask?.cancel(); flashTask = nil; subscription?.cancel(); subscription = nil }
}
