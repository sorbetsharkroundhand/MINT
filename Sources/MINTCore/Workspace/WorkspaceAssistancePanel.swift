import AppKit
import Combine
import SwiftUI

@MainActor final class WorkspaceAssistancePanel: NSWindowController, NSWindowDelegate {
    private static var active: WorkspaceAssistancePanel?
    private let model: WorkspaceAssistance
    private let requests: ProjectEditorRequests
    private let backdrop = WorkspaceModalBackdrop()
    private var closing = false
    private var monitor: Any?
    private var subscriptions: Set<AnyCancellable> = []
    static func present(_ mode: WorkspaceAssistance.Mode, model: WorkspaceAssistance, requests: ProjectEditorRequests, theme: MintTheme) {
        guard let editor = requests.nativeEditor, let parent = editor.window else { return }
        active?.close()
        do { try model.capture(mode, editor: editor) } catch { return }
        let panel = WorkspaceAssistancePanel(model: model, requests: requests)
        active = panel
        let width = min(460, max(300, parent.frame.width - 32))
        panel.window?.title = mode.rawValue
        panel.window?.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        panel.window?.contentView = NSHostingView(rootView: WorkspaceAssistanceView(model: model, theme: theme, close: { [weak panel] in panel?.close() }).frame(width: width))
        panel.window?.setContentSize(NSSize(width: width, height: mode == .coauthor ? 210 : 150))
        panel.backdrop.show(over: parent, opacity: 0.5)
        if let window = panel.window {
            window.setFrameOrigin(.init(x: parent.frame.midX - width / 2, y: parent.frame.midY - window.frame.height / 2))
            parent.addChildWindow(window, ordered: .above); window.makeKeyAndOrderFront(nil)
        }
        panel.fit()
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: parent)
            .sink { [weak panel] _ in panel?.close() }.store(in: &panel.subscriptions)
    }
    private init(model: WorkspaceAssistance, requests: ProjectEditorRequests) {
        self.model = model; self.requests = requests
        let panel = WorkspaceModalPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        super.init(window: panel); panel.delegate = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown, event.window !== self.window { self.close(); return nil }
            if event.type == .keyDown, event.keyCode == 53,
               (self.window?.firstResponder as? NSTextView)?.hasMarkedText() != true { self.close(); return nil }
            return event
        }
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.fit() }
        }.store(in: &subscriptions)
        model.$contextVersion.dropFirst().sink { [weak self] _ in self?.close() }.store(in: &subscriptions)
    }
    private func fit() {
        guard !closing, let window, let content = window.contentView, let parent = window.parent else { return }
        content.layoutSubtreeIfNeeded()
        let height = max(140, min(parent.frame.height - 64, content.fittingSize.height))
        let frame = CGRect(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - height / 2,
                           width: window.frame.width, height: height)
        window.setFrame(frame, display: true)
    }
    required init?(coder: NSCoder) { nil }
    override func close() { if !closing { window?.close() } }
    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }; closing = true; model.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; subscriptions.removeAll()
        backdrop.close()
        if let window { window.parent?.removeChildWindow(window) }
        if Self.active === self { Self.active = nil }; requests.focusEditor()
    }
}

struct WorkspaceAssistanceView: View {
    @ObservedObject var model: WorkspaceAssistance
    let theme: MintTheme
    let close: () -> Void
    @FocusState private var promptFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                WorkspaceIcon(name: "sparkles", size: 14).foregroundStyle(theme.novelC)
                Text(model.mode.rawValue).mintUIFont(12, .semibold)
                Spacer()
                Button(action: close) { WorkspaceIcon(name: "xmark", size: 14).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(theme.ink2C).accessibilityLabel("닫기")
            }.padding(.horizontal, 16).padding(.vertical, 10).background(theme.toolbarC)
            VStack(alignment: .leading, spacing: 12) {
                if model.mode == .coauthor {
                    ZStack(alignment: .topLeading) {
                        if model.coauthorPrompt.isEmpty { Text("어떤 장면을 이어 쓸까요?").mintUIFont(12).foregroundStyle(theme.workspaceMutedC).padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false) }
                        TextEditor(text: $model.coauthorPrompt).font(MintFonts.uiFont(12)).scrollContentBackground(.hidden)
                            .focused($promptFocused).accessibilityIdentifier("mint.coauthor.prompt")
                    }.padding(7).frame(height: 76).background(theme.chipC, in: RoundedRectangle(cornerRadius: 8))
                }
                if model.generating || !model.result.isEmpty {
                    ScrollView {
                        Text(model.result.isEmpty ? "문장을 짓는 중…" : model.result)
                            .font(MintFonts.serifUI(12)).lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 176).fixedSize(horizontal: false, vertical: true)
                        .padding(12).background(theme.novelBgC, in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = model.errorMessage { Text(error).mintUIFont(11).foregroundStyle(theme.dangerC).fixedSize(horizontal: false, vertical: true) }
            }.padding(16)
            HStack(spacing: 8) {
                Spacer()
                if !model.generating && !model.result.isEmpty && model.errorMessage == nil {
                    Button(model.mode == .margin ? "노트 추가" : (model.mode == .polish ? "다듬은 문장 적용" : "본문에 넣기")) { if model.insert() { close() } }
                        .buttonStyle(.plain).mintUIFont(12, .semibold).foregroundStyle(theme.novelC)
                        .padding(.horizontal, 12).padding(.vertical, 4).background(theme.chipC, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("mint.coauthor.insert")
                }
                Button(model.generating ? "중단" : "생성") {
                    if model.generating { model.cancel() } else { Task { await model.generate(prompt: model.coauthorPrompt) } }
                }.buttonStyle(.plain).mintUIFont(12, .semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4).background(theme.novelC, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(model.mode == .coauthor && model.coauthorPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("mint.coauthor.generate")
            }.padding(.horizontal, 16).padding(.vertical, 10).background(theme.statusbarC)
        }.foregroundStyle(theme.inkC).background(theme.editorSurfaceC)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear { promptFocused = model.mode == .coauthor }
    }
}
