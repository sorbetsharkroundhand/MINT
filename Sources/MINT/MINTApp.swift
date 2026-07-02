import SwiftUI
import AppKit
import MINTCore

/// MINT — Mac INtelligent note Taker
/// 온디바이스 한글 자동완성 저널 에디터의 진입점.
@main
struct MINTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MINT") {
            ContentView()
        }
        .defaultSize(width: 760, height: 580)

        // ⌘, — 자동완성 설정 (M4): 모델 · 프롬프트 방식 · 디바운스 · 토큰.
        Settings {
            SettingsView()
        }
    }
}


final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
