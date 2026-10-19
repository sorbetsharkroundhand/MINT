import SwiftUI

/// Compact projections reuse the map's scoped, source-verified preparation and cancellation.
struct WorkspaceNarrativeCards: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var requests: ProjectEditorRequests
    @ObservedObject var indexer: BackgroundIndexer
    @ObservedObject var completion: CompletionController
    @ObservedObject var model: SpatialWorkspaceController
    let theme: MintTheme
    @StateObject private var controller: StoryMapController
    private struct RefreshID: Equatable { let identity: ProjectRuntimeIdentity?; let generation: Int }
    init(session: ProjectSession, requests: ProjectEditorRequests, indexer: BackgroundIndexer, completion: CompletionController, model: SpatialWorkspaceController, theme: MintTheme) {
        self.session = session; self.requests = requests; self.indexer = indexer; self.completion = completion; self.model = model; self.theme = theme
        _controller = StateObject(wrappedValue: StoryMapController(session: session, requiresMapMode: false))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let prepared = controller.prepared {
                    ForEach(Array(prepared.projection.rows.enumerated()), id: \.element.id) { order, row in
                        WorkspaceCompactCard(model: model, id: "narrative.\(row.id)", title: "\(order + 1)  \(row.title)", detail: row.evidence.quote, term: row.evidence.quote.trimmingCharacters(in: .whitespacesAndNewlines), theme: theme) {
                            Text(row.evidence.quote).mintUIFont(11).foregroundStyle(theme.ink2C).textSelection(.enabled)
                            Button("본문 이동 →") {
                                let inspection = ProjectSourceInspection(session: session)
                                let reference = OriginalSourceReference(key: prepared.identity.key, revision: prepared.projection.revision, evidence: row.evidence, selection: .passage)
                                if let token = inspection.capture() { requests.jump(to: reference, inspection: inspection, token: token, in: session) }
                            }.buttonStyle(.plain).mintUIFont(10).foregroundStyle(theme.blueC)
                        }
                    }
                }
                DisclosureGroup("작가 수정과 기록") {
                    ProjectWriterToolsView(session: session, completion: completion, editorRequests: requests, section: .narrative, theme: theme, spatial: model).frame(minHeight: 100, maxHeight: 280)
                }.mintUIFont(10).foregroundStyle(theme.ink3C)
            }.padding(12)
        }
        .task(id: RefreshID(identity: session.runtimeIdentity, generation: indexer.snapshotGeneration)) {
            controller.update(knowledge: indexer.snapshot, knowledgeOrigin: indexer.snapshotRuntimeIdentity, generation: indexer.snapshotGeneration)
        }
        .onAppear { completion.observeForegroundCompletion(owner: controller) { [weak controller] busy in controller?.setForegroundBusy(busy) } }
        .onReceive(completion.$isMemoryPressurePaused) { controller.setPolicyPaused($0) }
        .onDisappear { controller.stop() }
    }
}
