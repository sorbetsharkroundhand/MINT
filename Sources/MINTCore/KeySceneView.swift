import SwiftUI

/// 작가가 직접 관리하는 sparse 핵심 장면 패널 (PLAN §14 M11 P0-A).
/// 분석 청크 수와 무관하며, AI 후보는 승인 전까지 사용자 데이터가 되지 않는다.
struct KeySceneView: View {
    @ObservedObject var store: EntryStore
    let snapshot: KnowledgeSnapshot
    let theme: MintTheme

    @State private var showingAdd = false
    @State private var editingScene: KeyScene?
    @State private var draftTitle = ""
    @State private var draftSummary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("핵심 장면", systemImage: "star.square.on.square")
                    .font(MintFonts.uiFont(12, .semibold))
                    .foregroundStyle(theme.inkC)
                Spacer()
                Button {
                    editingScene = nil
                    draftTitle = ""
                    draftSummary = ""
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("계획 핵심 장면 추가")
            }

            if snapshot.keyScenes.isEmpty {
                Text("작가가 선택한 핵심 장면이 아직 없어요. 원문 전체를 자동으로 장면 목록으로 만들지 않습니다.")
                    .font(MintFonts.uiFont(10.5))
                    .foregroundStyle(theme.ink3C)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(snapshot.keyScenes.enumerated()), id: \.element.id) { index, scene in
                    row(scene, previous: index > 0 ? snapshot.keyScenes[index - 1] : nil)
                }
            }

            if !snapshot.keySceneCandidates.isEmpty {
                DisclosureGroup("AI 후보 \(snapshot.keySceneCandidates.count)개") {
                    ForEach(snapshot.keySceneCandidates.prefix(5)) { candidate in
                        HStack(alignment: .top, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.proposedTitle)
                                    .font(MintFonts.uiFont(10.5, .medium))
                                    .foregroundStyle(theme.inkC)
                                Text(candidate.importanceSignals.joined(separator: " · "))
                                    .font(MintFonts.uiFont(9.5))
                                    .foregroundStyle(theme.ink3C)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Button("무시") {
                                    store.rejectKeySceneCandidate(
                                        inputHash: candidate.inputHash, in: store.activeID)
                                }
                                Button("등록") { accept(candidate) }
                            }
                            .font(MintFonts.uiFont(10, .medium))
                        }
                        .padding(.top, 4)
                    }
                }
                .font(MintFonts.uiFont(10.5, .medium))
                .foregroundStyle(theme.ink2C)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.chipC))
        .alert(editingScene == nil ? "핵심 장면 추가" : "핵심 장면 수정", isPresented: $showingAdd) {
            TextField("제목", text: $draftTitle)
            TextField("요약", text: $draftSummary)
            Button(editingScene == nil ? "추가" : "저장") { saveDraft() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(editingScene == nil
                ? "아직 쓰지 않은 계획 장면으로 추가합니다. 원문은 바뀌지 않아요."
                : "안정 UUID와 원문 연결은 유지됩니다.")
        }
    }

    private func row(_ scene: KeyScene, previous: KeyScene?) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: scene.status == .confirmed ? "checkmark.seal.fill" : "star")
                .foregroundStyle(scene.status == .confirmed ? theme.novelC : theme.ink3C)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(scene.title.isEmpty ? "제목 없는 핵심 장면" : scene.title)
                        .font(MintFonts.uiFont(10.5, .medium))
                        .foregroundStyle(theme.inkC)
                    Text(scene.status.label)
                        .font(MintFonts.uiFont(9))
                        .foregroundStyle(theme.ink3C)
                    if snapshot.staleKeySceneIDs.contains(scene.id) {
                        Text("근거 잃음")
                            .font(MintFonts.uiFont(9, .medium))
                            .foregroundStyle(theme.novelC)
                    }
                }
                if !scene.summary.isEmpty {
                    Text(scene.summary)
                        .font(MintFonts.uiFont(9.5))
                        .foregroundStyle(theme.ink2C)
                        .lineLimit(2)
                }
            }
            Spacer()
            if !scene.authorConfirmed {
                Button("확정") { store.confirmKeyScene(id: scene.id, in: store.activeID) }
                    .font(MintFonts.uiFont(9.5, .medium))
                    .buttonStyle(.plain)
            }
            Menu {
                Button("수정") {
                    editingScene = scene
                    draftTitle = scene.title
                    draftSummary = scene.summary
                    showingAdd = true
                }
                if let previous {
                    Button("이전 핵심 장면과 병합") {
                        store.mergeKeyScenes(
                            keeping: previous.id, removing: scene.id, in: store.activeID)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
            Button(role: .destructive) {
                store.removeKeyScene(id: scene.id, in: store.activeID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }

    private func saveDraft() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if var scene = editingScene {
            scene.title = title
            scene.summary = draftSummary
            store.upsertKeyScene(scene, in: store.activeID)
        } else {
            store.upsertKeyScene(
                KeyScene(title: title, summary: draftSummary, status: .planned),
                in: store.activeID)
        }
        editingScene = nil
    }

    private func accept(_ candidate: StoryEventCandidate) {
        let chapter = candidate.proposedRange.flatMap { range in
            snapshot.outline.scenes.first { $0.utf16Range.overlaps(range) }?.headingPath
        } ?? []
        store.upsertKeyScene(
            KeyScene(
                chapterAnchor: chapter, title: candidate.proposedTitle,
                summary: candidate.proposedSummary, sourceRange: candidate.proposedRange,
                status: .drafted,
                importance: candidate.importanceSignals.contains(where: { $0.contains("5") }) ? 5 : 4),
            in: store.activeID)
    }
}
