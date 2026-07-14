import SwiftUI
import AppKit
import MINTCore

/// MINT — 한글 장편 소설을 위한 온디바이스 예측 글쓰기 엔진의 진입점.
/// (저널·일반 문서는 같은 엔진의 가벼운 모드 — CLAUDE.md §1.)
@main
struct MINTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 저장소·자동완성은 앱 수명 동안 하나만 — 예전 WindowGroup은 ⌘N마다 새 창을
    // 열고 각 창이 같은 entries.json에 별도 EntryStore로 써서 저장이 충돌했다.
    // 단일 Window로 바꿔 그 위험을 없애고, ⌘N을 "새 저널"로 되돌린다(MintCommands).
    @StateObject private var store = EntryStore()
    @StateObject private var completion = CompletionController()

    var body: some Scene {
        Window("MINT", id: "main") {
            ContentView(store: store, completion: completion)
        }
        // 에디터 v3 — 타이틀 바를 숨기고 사이드바가 창 상단까지 차오르게 한다.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands { MintCommands(store: store) }

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

    // 입력 직후 ⌘Q·앱 전환으로 마지막 문장을 잃지 않도록 디바운스 저장을 즉시 비운다.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { EntryStore.current?.flush() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        MainActor.assumeIsolated { EntryStore.current?.flush() }
    }
}
