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
            LazyVStack(alignment: .leading, spacing: 6) {
                if let prepared = controller.prepared {
                    ForEach(Array(prepared.projection.rows.enumerated()), id: \.element.id) { order, row in
                        WorkspaceCompactCard(model: model, id: "narrative.\(row.id)", title: row.title, detail: row.evidence.quote, term: row.evidence.quote.trimmingCharacters(in: .whitespacesAndNewlines), theme: theme, order: String(format: "%02d", order + 1), sourceDocumentID: prepared.identity.key.documentID) {
                            Text(row.evidence.quote).mintUIFont(11).foregroundStyle(theme.ink2C).textSelection(.enabled)
                            Button("본문 이동 →") {
                                let inspection = ProjectSourceInspection(session: session)
                                let reference = OriginalSourceReference(key: prepared.identity.key, revision: prepared.projection.revision, evidence: row.evidence, selection: .passage)
                                if let token = inspection.capture() { requests.jump(to: reference, inspection: inspection, token: token, in: session) }
                            }.buttonStyle(.plain).mintUIFont(10).foregroundStyle(theme.blueC)
                        }
                    }
                }
            }.padding(8)
        }
        .contextMenu { Button("작가 수정과 기록…") { model.narrativeDetailsVisible = true } }
        .sheet(isPresented: $model.narrativeDetailsVisible) {
            VStack(spacing: 0) {
                HStack { Text("작가 수정과 기록").mintUIFont(12, .semibold); Spacer(); Button("닫기") { model.narrativeDetailsVisible = false }.keyboardShortcut(.cancelAction) }.padding(14)
                ProjectWriterToolsView(session: session, completion: completion, editorRequests: requests, section: .narrative, theme: theme).frame(minHeight: 100)
            }.frame(width: 540, height: 460).background(theme.editorSurfaceC)
        }
        .task(id: RefreshID(identity: session.runtimeIdentity, generation: indexer.snapshotGeneration)) {
            controller.update(knowledge: indexer.snapshot, knowledgeOrigin: indexer.snapshotRuntimeIdentity, generation: indexer.snapshotGeneration)
        }
        .onChange(of: controller.prepared) { _, prepared in
            model.entityEvents = prepared.map { prepared in
                prepared.projection.rows.filter { $0.kind == .event }.map { row in
                    WorkspaceEntityEvent(name: row.title, note: row.evidence.quote,
                        reference: .init(key: prepared.identity.key, revision: prepared.projection.revision, evidence: row.evidence, selection: .passage))
                }
            } ?? []
        }
        .onChange(of: model.narrativeDetailsVisible) { _, visible in
            if !visible { requests.focusEditor() }
        }
        .onAppear { completion.observeForegroundCompletion(owner: controller) { [weak controller] busy in controller?.setForegroundBusy(busy) } }
        .onReceive(completion.$isMemoryPressurePaused) { controller.setPolicyPaused($0) }
        .onDisappear { controller.stop() }
    }
}
