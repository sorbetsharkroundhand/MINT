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
    // 단일 모델 원칙 (CLAUDE.md §2-6) — 예측과 백그라운드 이해가 같은 엔진
    // (같은 상주 모델)을 쓴다. 인덱서는 예측에 항상 양보한다 (PLAN §9 선점).
    // 종료 훅(AppDelegate)에서도 접근하므로 internal.
    static let sharedEngine = CompletionEngine()
    @StateObject private var completion = CompletionController(engine: MINTApp.sharedEngine)
    @StateObject private var indexer = BackgroundIndexer(engine: MINTApp.sharedEngine)

    var body: some Scene {
        Window("MINT", id: "main") {
            ContentView(store: store, completion: completion, indexer: indexer)
        }
        // 에디터 v3 — 타이틀 바를 숨기고 사이드바가 창 상단까지 차오르게 한다.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands { MintCommands(store: store) }

        // ⌘, — 자동완성 설정 (M4): 모델 · 프롬프트 방식 · 디바운스 · 토큰.
        // 컨트롤러를 함께 넘겨 설정 창의 스위치·모델 변경도 의유 API로 무효화를
        // 발화하게 한다 (이슈 #11).
        Settings {
            SettingsView(settings: completion.settings, completion: completion)
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
        MainActor.assumeIsolated {
            EntryStore.current?.flush()
            WritingPositionStore.shared.persistNow()  // 집필 위치 영속 (#36)
            // 진행 중 생성의 부모 태스크부터 접는다 — 이 순서라 엔진 드레인은
            // 밀리초 단위다. 취소 없이 기다리면 생성이 끝날 때까지 종료가 막힌다.
            CompletionController.current?.shutdown()
            BackgroundIndexer.current?.shutdown()
        }
        // 남은 GPU 연산(프리필·토큰 루프)이 완전히 물러난 뒤 프로세스를 내려보낸다.
        // 이 대기가 없으면 teardown이 mlx eval 스레드와 경합해 종료 세그폴트가
        // 난다 — 앱 번들 스모크에서 3/3 재현 후 수정 (이슈 #65 Gate 0).
        //
        // 종료 컨텍스트에선 Swift 동시성 스케줄링이 보장되지 않는다 — detached
        // 태스크가 액터 진입 전에 정지하는 것을 스모크로 확인했다. 그래서 액터를
        // 거치지 않는 잠금 기반 카운터를 짧게 폴링한다 (50ms × 100 = 최대 5초).
        var polls = 0
        while polls < 100 {
            if MINTApp.sharedEngine.pendingOperationCount == 0 { break }
            usleep(50_000)
            polls += 1
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        MainActor.assumeIsolated { EntryStore.current?.flush() }
    }
}
