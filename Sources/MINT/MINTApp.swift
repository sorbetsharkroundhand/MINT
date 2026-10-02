import SwiftUI
import AppKit
import MINTCore

/// Local writing runtime with one shared inference engine and model-free editing.
@main
struct MINTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Completion, background preparation and pressure release own this same engine.
    static let sharedEngine = CompletionEngine()
    @StateObject private var completion = CompletionController(engine: MINTApp.sharedEngine)
    @StateObject private var livingMargin = LivingMarginModel()
    private static let projectStore = ProjectStore(root: MintStorageLocation.standard.projectsDirectory)
    private static let knowledgeSidecars = KnowledgeSidecarRepository(
        projectStore: MINTApp.projectStore)
    @StateObject private var indexer = BackgroundIndexer(
        engine: MINTApp.sharedEngine,
        sidecarPersistence: MINTApp.knowledgeSidecars)
    @StateObject private var projectSession: ProjectSession
    @StateObject private var legacyWorkspace: LegacyWorkspaceController
    @StateObject private var editorRequests = ProjectEditorRequests()

    init() {
        let session = ProjectSession(store: Self.projectStore, prepareProject: { project, store in
            try await ProjectWriterDataMigration.prepare(project, store: store)
        })
        _projectSession = StateObject(wrappedValue: session)
        _legacyWorkspace = StateObject(wrappedValue: LegacyWorkspaceController(session: session))
    }

    var body: some Scene {
        Window("MINT", id: "main") {
            ContentView(
                projectSession: projectSession,
                legacyWorkspace: legacyWorkspace,
                editorRequests: editorRequests,
                completion: completion,
                indexer: indexer,
                livingMargin: livingMargin,
                firstRunFlow: FirstRunFlow(
                    session: projectSession,
                    store: MINTApp.projectStore,
                    editorRequests: editorRequests))
                .onAppear {
                    appDelegate.configure(session: projectSession, legacyWorkspace: legacyWorkspace,
                        completion: completion, indexer: indexer)
                }
        }
        // 에디터 v3 — 타이틀 바를 숨기고 사이드바가 창 상단까지 차오르게 한다.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            MintCommands(
                session: projectSession,
                legacyWorkspace: legacyWorkspace,
                projectStore: MINTApp.projectStore,
                editorRequests: editorRequests)
        }

        // ⌘, — 자동완성 설정 (M4): 모델 · 프롬프트 방식 · 디바운스 · 토큰.
        // 컨트롤러를 함께 넘겨 설정 창의 스위치·모델 변경도 의유 API로 무효화를
        // 발화하게 한다 (이슈 #11).
        Settings {
            SettingsView(settings: completion.settings, completion: completion)
        }
    }
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var projectSession: ProjectSession?
    private weak var legacyWorkspace: LegacyWorkspaceController?
    private var termination: ProjectTerminationCoordinator?
    private var memoryPressure: MemoryPressureRuntime?
    private var backgroundFlush: Task<Void, Never>?

    func configure(session: ProjectSession, legacyWorkspace: LegacyWorkspaceController,
                   completion: CompletionController, indexer: BackgroundIndexer) {
        guard termination == nil else { return }
        projectSession = session
        self.legacyWorkspace = legacyWorkspace
        memoryPressure = MemoryPressureRuntime(completion: completion, indexer: indexer,
            engine: MINTApp.sharedEngine)
        termination = ProjectTerminationCoordinator(
            session: session, legacyWorkspace: legacyWorkspace,
            persistPositions: { WritingPositionStore.shared.persistNow() },
            shutdown: { [weak self] in
                self?.memoryPressure?.stop()
                completion.shutdown(); indexer.shutdown()
            },
            drain: { [weak self] in
                await self?.memoryPressure?.drain()
                // Yield the main actor until every engine operation has released its resources.
                while MINTApp.sharedEngine.pendingOperationCount > 0 {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            })
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Explicit archive smoke only; no model selection, download or AI authorization.
        if ProcessInfo.processInfo.environment["MINT_VERIFY_MLX_RESOURCES"] == "1" {
            let root = MintStorageLocation.standard.rootDirectory
            Task.detached(priority: .utility) {
                let result: String
                do {
                    let library = try MLXRuntimeResources.initialize()
                    result = "PASS\n\(library.path)\nMLX GPU result: 42\n"
                } catch { result = "FAIL\n\(error.localizedDescription)\n" }
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try Data(result.utf8).write(to: root.appendingPathComponent("mlx-runtime-verification.txt"), options: .atomic)
                } catch { NSLog("MLX archive diagnostic could not save its result: %@", error.localizedDescription) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let termination else { return .terminateNow }
        return termination.requestTermination { [weak self] success in
            sender.reply(toApplicationShouldTerminate: success)
            if !success, let message = self?.projectSession?.lastErrorMessage {
                let alert = NSAlert()
                alert.messageText = "저장하지 못해 종료를 취소했습니다"
                alert.informativeText = message
                alert.runModal()
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard backgroundFlush == nil, let legacyWorkspace, !legacyWorkspace.isTransitioning else { return }
        backgroundFlush = Task { @MainActor [weak self, weak legacyWorkspace] in
            defer { self?.backgroundFlush = nil }
            try? await legacyWorkspace?.flushActiveOwner()
        }
    }
}
