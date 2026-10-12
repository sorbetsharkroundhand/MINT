import AppKit
import SwiftUI

struct WorkspaceFrame<Content: View>: View {
    let theme: MintTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(WorkspacePaperSurface(theme: theme))
            .overlay {
                RoundedRectangle(cornerRadius: MintRadius.lg, style: .continuous)
                    .strokeBorder(theme.sepC).allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mint.workspace.frame")
    }
}

/// The background is a sibling of the editor, so rounding never clips its transients.
private struct WorkspacePaperSurface: NSViewRepresentable {
    let theme: MintTheme
    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView(); view.wantsLayer = true
        view.setAccessibilityIdentifier("mint.workspace.frame")
        return view
    }
    func updateNSView(_ view: SurfaceView, context: Context) {
        view.layer?.backgroundColor = theme.editorSurface.cgColor
        view.layer?.cornerRadius = MintRadius.lg
        view.layer?.masksToBounds = false
    }
    final class SurfaceView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct WorkspaceWindowChrome: View {
    let projectTitle: String
    let theme: MintTheme
    @State private var trafficLightMaxX: CGFloat?

    var body: some View {
        WorkspaceProjectTitle(title: projectTitle, theme: theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, WindowChromeGeometry.leadingContentInset(trafficLightMaxX: trafficLightMaxX))
            .padding(.trailing, 16)
            .frame(height: WorkspaceLayoutPolicy.chromeHeight)
            .background(WorkspaceChromeSurface(theme: theme).allowsHitTesting(false))
            .background(WorkspaceWindowDragRegion())
            .background(WindowChromeProbe(trafficLightMaxX: $trafficLightMaxX))
    }
}

private struct WorkspaceProjectTitle: NSViewRepresentable {
    let title: String
    let theme: MintTheme
    func makeNSView(context: Context) -> NSTextField {
        let field = TitleField(labelWithString: title)
        field.font = MintFonts.ui(12, weight: .medium)
        field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingMiddle
        field.setAccessibilityIdentifier("mint.workspace.chrome.title")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = title; field.textColor = theme.ink2
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 18)
    }
    final class TitleField: NSTextField {
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

}

private struct WorkspaceWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        let view = DragView(); view.setAccessibilityIdentifier("mint.workspace.chrome")
        return view
    }
    func updateNSView(_ view: DragView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

/// Native actions preserve pointer-click caret state and remain keyboard accessible.
struct WorkspaceActionButton: NSViewRepresentable {
    let identifier: String
    let label: String
    let symbol: String
    let theme: MintTheme
    var selected: Bool? = nil
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.invokeAction))
        button.isBordered = false; button.refusesFirstResponder = true
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.contentTintColor = selected == true ? theme.blue : theme.ink2
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.setAccessibilityIdentifier(identifier)
        if let selected { button.setAccessibilityValue(NSNumber(value: selected)) }
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invokeAction() { action() }
    }
}
