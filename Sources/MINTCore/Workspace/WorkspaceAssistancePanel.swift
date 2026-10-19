import AppKit
import SwiftUI

@MainActor final class WorkspaceAssistancePanel: NSWindowController, NSWindowDelegate {
    private static var active: WorkspaceAssistancePanel?
    private let model: WorkspaceAssistance
    private let requests: ProjectEditorRequests
    private var closing = false
    static func present(_ mode: WorkspaceAssistance.Mode, model: WorkspaceAssistance, requests: ProjectEditorRequests, theme: MintTheme) {
        guard let editor = requests.nativeEditor, let parent = editor.window else { return }
        active?.close()
        do { try model.capture(mode, editor: editor) } catch { return }
        let panel = WorkspaceAssistancePanel(model: model, requests: requests)
        active = panel
        panel.window?.title = mode.rawValue
        panel.window?.contentView = NSHostingView(rootView: WorkspaceAssistanceView(model: model, theme: theme, close: { [weak panel] in panel?.close() }))
        panel.window?.setContentSize(NSSize(width: min(480, max(320, parent.frame.width - 60)), height: 380))
        if let window = panel.window {
            window.setFrameOrigin(.init(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2))
            parent.addChildWindow(window, ordered: .above); window.makeKeyAndOrderFront(nil)
        }
    }
    private init(model: WorkspaceAssistance, requests: ProjectEditorRequests) {
        self.model = model; self.requests = requests
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        super.init(window: panel); panel.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    override func close() { if !closing { window?.close() } }
    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }; closing = true; model.cancel()
        if let window { window.parent?.removeChildWindow(window) }
        if Self.active === self { Self.active = nil }; requests.focusEditor()
    }
}

private struct WorkspaceAssistanceView: View {
    @ObservedObject var model: WorkspaceAssistance
    let theme: MintTheme
    let close: () -> Void
    @State private var prompt = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.mode.rawValue).font(.system(size: 18, weight: .semibold, design: .serif))
            if model.mode == .coauthor {
                TextField("어떤 방향으로 이어 쓸까요?", text: $prompt).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("mint.coauthor.prompt")
            }
            if model.generating { ProgressView("로컬 모델로 작성 중…").controlSize(.small) }
            ScrollView { Text(model.result.isEmpty ? "생성 결과를 확인한 뒤 원고에 적용할 수 있어요." : model.result)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            if let error = model.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(theme.dangerC) }
            HStack {
                Button("닫기", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                if model.generating { Button("중단") { model.cancel() } }
                else { Button("생성") { Task { await model.generate(prompt: prompt) } }.accessibilityIdentifier("mint.coauthor.generate") }
                Button(model.mode == .margin ? "노트 추가" : "원고에 적용") { if model.insert() { close() } }
                    .disabled(model.generating || model.result.isEmpty || model.errorMessage != nil)
                    .accessibilityIdentifier("mint.coauthor.insert")
            }
        }.padding(20).foregroundStyle(theme.inkC).background(theme.cardSurfaceC)
    }
}
