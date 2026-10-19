import AppKit
import XCTest
@testable import MINTCore

@MainActor final class SpatialWorkspaceCaptureTests: XCTestCase {
    func testCaptureSyntheticNativeSpatialWorkspace() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MINT_WORKSPACE_CAPTURE_DIR"] else { throw XCTSkip("Native capture is opt-in") }
        let customPalette = PaletteSettings.shared.enabled
        PaletteSettings.shared.enabled = false
        defer { PaletteSettings.shared.enabled = customPalette }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let h = try await FramedWorkspaceHarness(width: 1440, appearance: dark ? .dark : .light, reduceMotion: true, mode: .fiction)
            defer { h.close() }
            let session = h.fixture.session
            let a = try XCTUnwrap(session.selectedDocumentID)
            session.updateSelectedDocumentBody("# 바람이 머무는 곳\n\n서연은 창문을 열었다. 밤새 비가 지나간 골목에는 젖은 나무 향이 남아 있었다.\n\n탁자 위의 편지는 아직 봉투 안에 있었다. 오늘은 읽어야겠다고, 서연은 생각했다.\n\n바깥에서 자전거 종소리가 들렸다. 긴 하루가 이제 막 시작되고 있었다.")
            try ProjectWriterEditing.perform(.character(CharacterCard(name: "서연", aliases: "편지를 기다리는 사람", note: "도시를 떠나기 전, 오래된 편지를 다시 읽는다.")), in: session, identity: XCTUnwrap(session.runtimeIdentity))
            let b = try XCTUnwrap(session.createDocument(title: "두 번째 장"))
            session.updateSelectedDocumentBody("# 두 번째 장\n\n기차가 역에 멈추자 사람들은 천천히 자리에서 일어났다.\n\n서연은 가방 안의 편지를 만졌다. 도착했다는 말을 누구에게 먼저 해야 할지 잠시 망설였다.")
            await h.layout(); session.selectDocument(a); await h.layout()
            let activeEditor = try await h.editor(); h.window.makeFirstResponder(activeEditor)
            let model = try XCTUnwrap(h.requests.spatialWorkspace)
            model.toggle(.characters); model.toggle(.narrative); model.toggle(.margin)
            await h.layout(); h.window.makeKeyAndOrderFront(nil); await h.layout()
            try await Task.sleep(for: .milliseconds(400)); await h.layout()
            try capture(h.host, path: directory + "/workspace-\(dark ? "dark" : "light").png")
            if let pouch = h.requests.pouch?.panel?.contentView { try capture(pouch, path: directory + "/pouch-\(dark ? "dark" : "light").png") }
            let canvas = try XCTUnwrap(descendant(h.host, SpatialWorkspaceCanvasView.self))
            let header = try XCTUnwrap(h.element("mint.tile.header.document.\(a.rawValue.uuidString)") as? NSView)
            let source = try XCTUnwrap(canvas.geometry.tiles[.document(a)])
            let target = try XCTUnwrap(canvas.geometry.tiles[.document(b)])
            func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                    windowNumber: h.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            let origin = model.layout
            header.mouseDown(with: try event(.leftMouseDown, CGPoint(x: source.midX, y: source.minY + 12)))
            header.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: target.midX, y: target.minY + 10)))
            await h.layout(); XCTAssertTrue(model.isDragging)
            try capture(h.host, path: directory + "/drag-preview-\(dark ? "dark" : "light").png")
            header.cancelOperation(nil); await h.layout(); XCTAssertEqual(model.layout, origin)
            let editor = try await h.editor(); h.window.makeFirstResponder(editor)
            model.typewriter = true; model.focusDimming = true; await h.layout()
            try capture(h.host, path: directory + "/writing-focus-\(dark ? "dark" : "light").png")
            h.requests.pouch?.collapse(); await h.layout()
            if let orb = h.requests.pouch?.panel?.contentView { try capture(orb, path: directory + "/collapsed-orb-\(dark ? "dark" : "light").png") }
            h.requests.pouch?.restore(); await h.layout()
            let retained = try await h.editor(); XCTAssertTrue(retained === editor)
            try capture(h.host, path: directory + "/restored-workspace-\(dark ? "dark" : "light").png")
        }
    }
    private func descendant<T: NSView>(_ root: NSView, _ type: T.Type) -> T? {
        (root as? T) ?? root.subviews.compactMap { descendant($0, type) }.first
    }
    private func capture(_ view: NSView, path: String) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
