import AppKit
import Combine

@MainActor final class WorkspaceQuickCommandPanel: NSWindowController, NSWindowDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var active: WorkspaceQuickCommandPanel?
    let searchField = NSSearchField()
    private let table = WorkspaceCommandTable()
    private let session: ProjectSession
    private let requests: ProjectEditorRequests
    private let inspection: ProjectSourceInspection
    private let token: ProjectSourceInspection.Token
    private let toggleTheme: () -> Void
    private var items: [WorkspaceCommandItem] = []
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var closing = false

    @discardableResult static func present(session: ProjectSession, requests: ProjectEditorRequests, theme: MintTheme, toggleTheme: @escaping () -> Void) -> WorkspaceQuickCommandPanel? {
        guard requests.captureSourcePosition(in: session) != nil, let parent = requests.nativeEditor?.window else { return nil }
        active?.close()
        let inspection = ProjectSourceInspection(session: session)
        guard let token = inspection.capture() else { return nil }
        let panel = WorkspaceQuickCommandPanel(session: session, requests: requests, inspection: inspection, token: token, toggleTheme: toggleTheme)
        active = panel
        let width = min(500, max(300, parent.frame.width - 48)), height: CGFloat = 400
        panel.window?.setContentSize(NSSize(width: width, height: height))
        panel.window?.setFrameOrigin(.init(x: parent.frame.midX - width / 2, y: parent.frame.maxY - height - 80))
        panel.window?.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        if let window = panel.window { parent.addChildWindow(window, ordered: .above) }
        panel.window?.makeKeyAndOrderFront(nil); panel.window?.makeFirstResponder(panel.searchField)
        return panel
    }
    private init(session: ProjectSession, requests: ProjectEditorRequests, inspection: ProjectSourceInspection,
                 token: ProjectSourceInspection.Token, toggleTheme: @escaping () -> Void) {
        self.session = session; self.requests = requests; self.inspection = inspection; self.token = token; self.toggleTheme = toggleTheme
        let window = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.title = "빠른 검색 및 명령"
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = true
        super.init(window: window); window.delegate = self
        searchField.placeholderString = "명령, 문서, 인물 또는 원문 검색…"
        searchField.maximumRecents = 0; searchField.sendsSearchStringImmediately = true; searchField.delegate = self
        searchField.setAccessibilityIdentifier("mint.commands.query"); searchField.setAccessibilityLabel("빠른 검색 및 명령")
        table.addTableColumn(NSTableColumn(identifier: .init("command"))); table.headerView = nil
        table.rowHeight = 35; table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(activateSelected)
        table.setAccessibilityIdentifier("mint.commands.results")
        table.hover = { [weak self] row in self?.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let help = NSTextField(labelWithString: "↑↓ 이동     ↵ 실행     Esc 닫기")
        help.font = .systemFont(ofSize: 10); help.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [searchField, scroll, help]); stack.orientation = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView?.addSubview(stack)
        if let content = window.contentView { NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)]) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let self, event.window !== self.window { self.close() }; return event
        }) { monitors.append(monitor) }
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification).sink { [weak self] notification in
            guard let self, let parent = notification.object as? NSWindow, parent === self.window?.parent else { return }
            self.close()
        }.store(in: &subscriptions)
        session.$activeProject.dropFirst().sink { [weak self] _ in self?.close() }.store(in: &subscriptions)
        session.$isTransitioning.dropFirst().sink { [weak self] value in if value { self?.close() } }.store(in: &subscriptions)
        reload()
    }
    required init?(coder: NSCoder) { nil }
    private func reload() {
        guard let project = session.activeProject else { return }
        items = WorkspaceCommandSearch.items(in: project, query: searchField.stringValue,
            typewriter: requests.spatialWorkspace?.typewriter == true, focus: requests.spatialWorkspace?.focusDimming == true)
        table.reloadData(); if !items.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }
    func controlTextDidChange(_ obj: Notification) {
        guard (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }; reload()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch command {
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        case #selector(NSResponder.insertNewline(_:)): activateSelected(); return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !items.isEmpty else { return true }
            let delta = command == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = (table.selectedRow + delta + items.count) % items.count
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row); return true
        default: return false
        }
    }
    @objc private func activateSelected() {
        guard inspection.isCurrent(token, in: session), items.indices.contains(table.selectedRow),
            (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        let action = items[table.selectedRow].action
        switch action {
        case .typewriter: requests.spatialWorkspace?.typewriter.toggle()
        case .focus: requests.spatialWorkspace?.focusDimming.toggle()
        case .openAll: requests.spatialWorkspace?.openAll()
        case .theme: toggleTheme()
        case .document(let id): session.selectDocument(id); requests.spatialWorkspace?.open(id)
        case .character(let id, let card):
            session.selectDocument(id)
            if requests.spatialWorkspace?.layout.contains(.characters) == false { requests.spatialWorkspace?.toggle(.characters) }
            requests.spatialWorkspace?.expandedItem = card.uuidString
        case .source(let reference):
            guard requests.jump(to: reference, inspection: inspection, token: token, in: session) else { return }
        }
        close()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row], title = NSTextField(labelWithString: item.title), kind = NSTextField(labelWithString: item.kind.rawValue)
        title.font = .systemFont(ofSize: 12); title.lineBreakMode = .byTruncatingTail
        kind.font = .systemFont(ofSize: 10); kind.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, kind]); stack.spacing = 8
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }
    override func close() { if !closing { window?.close() } }
    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }; closing = true
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); subscriptions.removeAll()
        if let window { window.parent?.removeChildWindow(window) }
        if Self.active === self { Self.active = nil }
        requests.focusEditor()
    }
}

@MainActor private final class WorkspaceCommandTable: NSTableView {
    var hover: ((Int) -> Void)?
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea); super.updateTrackingAreas()
        addTrackingArea(.init(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil)); if row >= 0 { hover?(row) }
    }
}
