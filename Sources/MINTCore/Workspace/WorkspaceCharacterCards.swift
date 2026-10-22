import SwiftUI

struct WorkspaceCharacterCards: View {
    @ObservedObject var session: ProjectSession
    @ObservedObject var requests: ProjectEditorRequests
    @ObservedObject var completion: CompletionController
    @ObservedObject var model: SpatialWorkspaceController
    let theme: MintTheme
    private struct Record: Identifiable {
        let documentID: WritingDocumentID
        let card: CharacterCard
        var id: UUID { card.id }
    }
    private var records: [Record] {
        guard let project = session.activeProject else { return [] }
        var seen: Set<UUID> = []
        return project.documents.filter { !project.trashedDocumentIDs.contains($0.id) }.flatMap { document in
            let writer = try? WriterDocumentData.decode(project.userData[WriterDocumentData.key(for: document.id)], documentID: document.id)
            return (writer?.characters ?? []).filter { seen.insert($0.id).inserted }.map { Record(documentID: document.id, card: $0) }
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(records) { record in
                    let card = record.card
                    WorkspaceCompactCard(model: model, id: card.id.uuidString, title: card.name.isEmpty ? "새 인물" : card.name,
                        detail: card.note, term: card.name, theme: theme, initial: String(card.name.prefix(1)),
                        role: card.role ?? "", sourceDocumentID: record.documentID) {
                        Text(card.note.isEmpty ? "아직 적은 소개가 없어요." : card.note).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 4) {
                            Text((card.traits ?? []).map { "#\($0)" }.joined(separator: "  "))
                                .mintUIFont(9.5).foregroundStyle(theme.workspaceMutedC)
                            Spacer(minLength: 4)
                            if let reference = reference(for: record) {
                                Button("본문 이동 →") { jump(reference) }.buttonStyle(.plain).mintUIFont(10, .medium).foregroundStyle(theme.novelC)
                            }
                        }
                    }
                    .contextMenu {
                        Button("인물 편집…") { session.selectDocument(record.documentID); model.selectTile(.characters); model.pouchSection = .object }
                        Button("작품 정보 편집…") { model.selectTile(.characters); model.pouchSection = .object }
                    }
                    .accessibilityAction(named: Text("인물 편집")) { session.selectDocument(record.documentID); model.selectTile(.characters); model.pouchSection = .object }
                }
                if records.isEmpty {
                    Text("아직 등록한 인물이 없어요. 주머니의 인물·작품 라벨에서 추가할 수 있어요.")
                        .mintUIFont(11).foregroundStyle(theme.workspaceMutedC).padding(2)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { Button("작품 정보 편집…") { model.selectTile(.characters); model.pouchSection = .object } }

    }
    private func reference(for record: Record) -> OriginalSourceReference? {
        guard let project = session.activeProject, let document = project.documents.first(where: { $0.id == record.documentID }), !record.card.name.isEmpty else { return nil }
        let source = document.body as NSString, name = source.range(of: record.card.name)
        guard name.location != NSNotFound else { return nil }
        let paragraph = source.paragraphRange(for: name)
        return .exact(.init(documentID: document.id, quote: source.substring(with: paragraph), utf16Hint: paragraph.location), in: project)
    }
    private func jump(_ reference: OriginalSourceReference) {
        let inspection = ProjectSourceInspection(session: session)
        if let token = inspection.capture() { requests.jump(to: reference, inspection: inspection, token: token, in: session) }
    }
}
