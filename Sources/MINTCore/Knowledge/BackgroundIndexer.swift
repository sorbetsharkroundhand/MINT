import AppKit
import Foundation

/// 백그라운드 이해 파이프라인 (M6, PLAN §9) — 유휴 시간에 씬 요약을 만들고
/// 요약 피라미드를 상향 전파해, 예측이 조립만 하면 되는 지식을 준비한다
/// (CLAUDE.md §2-2 "백그라운드가 이해를 준비하고, 예측은 조립만 한다").
///
/// **트리거 2단** (PLAN §9): 타이핑 유휴 ~5s → 빠른 패스(더티 씬 요약,
/// LLM ≤ 2회) · 장기 유휴 ~60s 또는 앱 비활성 → 깊은 패스(남은 씬 전부 +
/// 장·작품 요약 전파).
///
/// **백그라운드 3요건** (CLAUDE.md §4):
/// - 선점: 키 입력(`noteChange`)마다 진행 중 패스를 즉시 취소한다. 생성 스트림은
///   다음 청크에서 협조 종료하고, 씬 단위 체크포인트라 다음 유휴에 이어서 한다.
/// - 게이트: 열 상태 `.serious` 이상이면 모든 패스 보류, 저전력 모드면 깊은
///   패스만 보류 (PLAN §9 시민의식).
/// - 메모: 요약 키는 씬 콘텐츠 해시 — 같은 입력은 절대 재요약하지 않는다.
///   메모 자체가 사이드카 파일(`KnowledgeSidecar`)이다.
///
/// 예측 경로와의 계약: 이 클래스는 패스가 끝날 때마다 `snapshot`(값 복사)을
/// 발행하고, 예측은 그것만 읽는다 — 예측 시점 디스크·LLM 접근 금지.
@MainActor
public final class BackgroundIndexer: ObservableObject {

    /// 최신 지식 스냅샷 — `CompletionController.knowledgeProvider`가 pull한다.
    @Published public private(set) var snapshot: KnowledgeSnapshot?
    /// 진행 중 패스 표시 (툴바 칩 등 UI 관찰용 — 조용한 UI 원칙상 필수는 아니다).
    @Published public private(set) var isIndexing = false
    /// 인물 감지 후보 (M6, PLAN §7) — 감지는 자동, **등록은 사용자 확인**
    /// (CLAUDE.md §3). 바이블 팝오버가 전부 나열해 검토받는다 (M6-8).
    @Published public private(set) var characterCandidates: [CharacterDetector.Candidate] = []
    /// 후보가 어느 문서 것인지 — 문서 전환 시 낡은 후보를 보여주지 않기 위한 짝.
    @Published public private(set) var candidatesEntryID: UUID?
    /// 패스 **완주** 신호 (MainActor) — 이해 경로의 마지막 단계인 A+B KV 프리웜을
    /// 여기 배선한다 (PLAN §12-1, ContentView → CompletionController.prewarmPrefix).
    /// 선점·게이트로 중단된 패스에는 쏘지 않는다 — 타이핑이 재개됐다는 뜻이므로
    /// 프리웜 GPU를 태울 자리가 아니다.
    public var onPassDidComplete: (() -> Void)?

    /// 빠른 패스 유휴 대기 — 예측 디바운스(수백 ms)와 별도 타이머 (PLAN §9).
    nonisolated static let fastPassIdle: Duration = .seconds(5)
    /// 깊은 패스 유휴 대기.
    nonisolated static let deepPassIdle: Duration = .seconds(60)
    /// 빠른 패스의 유휴당 LLM 호출 상한 (PLAN §9 예산).
    nonisolated static let fastPassCallBudget = 2
    /// 요약에 넣는 씬 원문 상한 — 프리필은 취소 불가 구간이라, 이 길이가
    /// "타이핑 재개 → 예측이 엔진을 기다리는" 최악 지연을 결정한다 (짧게 유지).
    nonisolated public static let maxSceneCharacters = 1_500

    private let engine: CompletionEngine
    private let settings: CompletionSettings
    private weak var store: EntryStore?

    private var fastTimer: Task<Void, Never>?
    private var deepTimer: Task<Void, Never>?
    private var passTask: Task<Void, Never>?

    public init(
        engine: CompletionEngine,
        settings: CompletionSettings = .shared
    ) {
        self.engine = engine
        self.settings = settings
        // 앱 비활성 = 장기 유휴와 같은 신호 — 곧바로 깊은 패스 (PLAN §9).
        // 앱 수명 싱글턴이라 옵저버를 해제하지 않는다 (weak self라 누수 없음).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.startPass(deep: true) }
        }
    }

    /// ContentView가 1회 배선 — 패스 시점에 활성 문서를 pull하기 위한 약참조.
    public func attach(store: EntryStore) {
        self.store = store
    }

    // MARK: - 트리거

    /// 본문 편집·문서 전환 알림 (EntryStore 훅) — 진행 중 패스를 선점하고
    /// 유휴 타이머를 다시 감는다.
    public func noteChange(entryID: UUID) {
        // 선점: 백그라운드 생성은 예측(그리고 그 앞의 타이핑)에 항상 진다 (CLAUDE.md §2-6).
        passTask?.cancel()
        passTask = nil
        isIndexing = false

        fastTimer?.cancel()
        deepTimer?.cancel()
        fastTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.fastPassIdle)
            guard !Task.isCancelled else { return }
            self?.startPass(deep: false)
        }
        deepTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.deepPassIdle)
            guard !Task.isCancelled else { return }
            self?.startPass(deep: true)
        }
    }

    // MARK: - 패스 실행

    private func startPass(deep: Bool) {
        guard passTask == nil else { return }  // 이미 도는 중 — 중복 금지
        // 자동완성이 꺼져 있으면 지식도 만들지 않는다 — 백그라운드 이해가
        // 대용량 모델 다운로드를 유발해서는 안 된다 (폴더 명명과 같은 규칙).
        guard settings.autocompleteEnabled else { return }
        guard let entry = store?.activeEntry, entry.resolvedKind == .novel else { return }
        let body = entry.body
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let entryID = entry.id
        var parameters = settings.parameters
        // 요약은 낮은 온도로 결정성 우선 — 같은 씬이 패스마다 다른 요약을 얻으면
        // B 블록이 흔들려 KV 프리픽스가 식는다 (PLAN §12).
        parameters.temperature = min(parameters.temperature, 0.3)
        let liveEntryIDs = Set(store?.entries.map(\.id) ?? [])
        // 사건의 참여자로 링크할 수 있는 인물 = 등록된 카드뿐 (CLAUDE.md §3).
        let characters = entry.characters ?? []
        // 인물 감지 제외 목록 — 이미 등록된 이름·별칭 + 사용자가 무시한 이름.
        let knownNames = Set(
            (entry.characters ?? []).flatMap { card in
                [card.name] + card.aliases.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }.filter { !$0.isEmpty })
        let rejectedNames = Set(entry.rejectedCharacterNames ?? [])

        isIndexing = true
        // 파싱·디스크 IO·프롬프트 준비를 메인에서 떼어낸다 — 생성 자체는 엔진
        // actor에서 돌므로, 여기서 중요한 건 30만 자 파싱이 메인을 막지 않는 것.
        // self는 앱 수명 객체라 패스 동안의 강참조가 수명을 늘리지 않는다.
        passTask = Task.detached(priority: .utility) { [engine, self] in
            // 인물 감지 — 결정적·LLM 없음이라 게이트·예산 밖에서 먼저 (PLAN §7).
            let outline = DocumentOutline.parse(body)
            let candidates = CharacterDetector.detect(
                body: body, outline: outline,
                known: knownNames, rejected: rejectedNames)
            await MainActor.run {
                self.characterCandidates = candidates
                self.candidatesEntryID = entryID
            }
            let completed = await Self.runPass(
                deep: deep, entryID: entryID, body: body,
                parameters: parameters, engine: engine,
                liveEntryIDs: liveEntryIDs, characters: characters
            ) { snapshot in
                Task { @MainActor in self.snapshot = snapshot }
            }
            await MainActor.run {
                self.passTask = nil
                self.isIndexing = false
                if completed { self.onPassDidComplete?() }
            }
        }
    }

    // MARK: - 인물 후보 확인 (등록은 사용자, CLAUDE.md §3)

    /// 후보 등록 — 카드를 즉시 만들고, 소개는 백그라운드 LLM 프로파일링이
    /// 채운다 (PLAN §7 깔때기 3단). 프로파일링 실패 시 이름만 남는다 —
    /// 이름만으로도 카드 선택(§11)에는 충분하다.
    public func approveCandidate(_ candidate: CharacterDetector.Candidate) {
        guard let store, let entry = store.activeEntry else { return }
        let card = CharacterCard(name: candidate.name)
        store.upsertCharacter(card, in: entry.id)
        characterCandidates.removeAll { $0.name == candidate.name }

        let body = entry.body
        let parameters = settings.parameters
        let entryID = entry.id
        Task { [engine, weak store] in
            let note = await Self.profileCharacter(
                named: candidate.name, in: body,
                engine: engine, parameters: parameters)
            guard let note, let store else { return }
            // 그 사이 사용자가 직접 소개를 썼거나 카드를 잠갔다면 그쪽이 이긴다
            // (CLAUDE.md §1-5 — locked는 자동 추출이 덮지 못한다, PLAN §6.2).
            guard
                var current = store.entries.first(where: { $0.id == entryID })?
                    .characters?.first(where: { $0.id == card.id }),
                current.note.isEmpty, current.locked != true
            else { return }
            current.note = note
            store.upsertCharacter(current, in: entryID)
        }
    }

    /// 후보 무시 — 거부 목록에 저장, 같은 이름은 다시 묻지 않는다 (PLAN §7).
    public func rejectCandidate(_ candidate: CharacterDetector.Candidate) {
        guard let store, let id = store.activeEntry?.id else { return }
        store.rejectCharacterName(candidate.name, in: id)
        characterCandidates.removeAll { $0.name == candidate.name }
    }

    /// 등록 직후의 인물 프로파일링 — 이름이 등장하는 문장들만 모아 한 번의
    /// instruct로 성격·말투 초안을 뽑는다 (PLAN §7, `generateFolderName` 규율).
    nonisolated private static func profileCharacter(
        named name: String, in body: String,
        engine: CompletionEngine, parameters: CompletionParameters
    ) async -> String? {
        // 언급 문장 수집 (결정적) — 앞에서부터 최대 8문장·1000자.
        var snippets: [String] = []
        var total = 0
        for line in body.split(separator: "\n") where line.contains(name) {
            let sentence = line.trimmingCharacters(in: .whitespaces)
            snippets.append(sentence)
            total += sentence.count
            if snippets.count >= 8 || total > 1_000 { break }
        }
        guard !snippets.isEmpty else { return nil }
        let note =
            (try? await engine.generateOneShot(
                system: """
                    너는 소설 인물 카드를 쓰는 도우미다. 발췌에 근거해 인물의 \
                    성격·말투·관계를 한국어 1~2문장(최대 140자)으로 쓴다. \
                    발췌에 없는 내용은 지어내지 않는다. 설명·머리말 없이 본문만 출력한다.
                    """,
                user: """
                    인물 '\(name)'에 대한 발췌다. 이 인물의 카드 소개를 써라.

                    \(snippets.joined(separator: "\n"))
                    """,
                maxTokens: 96,
                parameters: parameters)) ?? ""
        let collapsed = note
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : String(collapsed.prefix(140))
    }

    /// 한 번의 이해 패스 — 값 입력만 받아 detached에서 돈다.
    /// 반환값은 **완주 여부** — 선점·게이트로 중단되면 false. 완주 시에만
    /// 호출부가 KV 프리웜을 쏜다 (PLAN §12-1).
    nonisolated private static func runPass(
        deep: Bool,
        entryID: UUID,
        body: String,
        parameters: CompletionParameters,
        engine: CompletionEngine,
        liveEntryIDs: Set<UUID>,
        characters: [CharacterCard],
        publish: @Sendable @escaping (KnowledgeSnapshot) -> Void
    ) async -> Bool {
        guard gateAllows(deep: deep) else { return false }

        let outline = DocumentOutline.parse(body)
        guard !outline.scenes.isEmpty else { return false }
        var sidecar = KnowledgeSidecar.load(entryID: entryID)
        let text = body as NSString
        // 대화 귀속 (PLAN §7·§6.4) — 결정적·LLM 없음이라 패스마다 재계산.
        // 사이드카에 저장하지 않는 파생 — 스냅샷에만 실린다.
        let utterances = DialogueAttribution.utterances(in: body, cards: characters)

        // ① 더티 씬 요약 — 해시 메모에 없는 씬만, 문서 순서대로.
        var callBudget = deep ? Int.max : fastPassCallBudget
        for scene in outline.scenes {
            guard callBudget > 0 else { break }
            guard sidecar.sceneSummaries[scene.contentHash] == nil else { continue }
            guard !Task.isCancelled, gateAllows(deep: deep) else { return false }

            let sceneText = String(
                text.substring(
                    with: NSRange(
                        location: scene.utf16Range.lowerBound,
                        length: scene.utf16Range.count)
                ).prefix(maxSceneCharacters))
            guard sceneText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
            else { continue }  // 요약할 내용이 없는 토막은 건너뛴다

            let summary = await summarizeScene(
                sceneText, engine: engine, parameters: parameters)
            callBudget -= 1
            guard let summary else { continue }  // 실패는 다음 패스가 재시도

            sidecar.sceneSummaries[scene.contentHash] = .init(
                contentHash: scene.contentHash,
                headingPath: scene.headingPath,
                summary: summary,
                updatedAt: .now)
            // 씬 단위 체크포인트 — 선점당해도 여기까지의 이해는 살아남는다.
            sidecar.save()
            publish(
                makeSnapshot(
                    entryID: entryID, outline: outline, sidecar: sidecar,
                    utterances: utterances))
        }

        // ② 사건 추출 (깊은 패스 전용, PLAN §6.3) — 요약이 끝난 씬만.
        // 요약보다 뒤에 두는 이유: 빠른 패스의 LLM 예산은 요약이 먼저 쓴다
        // (docs/m6-events.md 결정 3).
        if deep, !Task.isCancelled {
            relinkParticipants(sidecar: &sidecar, characters: characters)
            for scene in outline.scenes {
                guard !Task.isCancelled, gateAllows(deep: true) else { return false }
                // 키 존재 = 추출 완료(빈 배열이면 "사건 없음") — 메모 적중은 건너뛴다.
                guard sidecar.events[scene.contentHash] == nil else { continue }
                let sceneText = String(
                    text.substring(
                        with: NSRange(
                            location: scene.utf16Range.lowerBound,
                            length: scene.utf16Range.count)
                    ).prefix(maxSceneCharacters))
                let extracted = await extractEvents(
                    sceneText, sceneHash: scene.contentHash,
                    characters: characters, engine: engine, parameters: parameters)
                guard let extracted else { continue }  // 실패·인물 미등록 — 재시도 여지
                sidecar.events[scene.contentHash] = extracted
                sidecar.save()  // 씬 단위 체크포인트 — 선점당해도 여기까지는 남는다
            }
        }

        // ③ 상향 전파 (깊은 패스 전용) — 장 → 작품, 더티 경로만 (PLAN §6.1).
        if deep, !Task.isCancelled {
            await propagate(
                outline: outline, sidecar: &sidecar,
                parameters: parameters, engine: engine)
            // 어떤 저널도 참조하지 않는 사이드카 정리 (삭제된 작품의 파생물).
            pruneOrphans(keeping: liveEntryIDs)
        }

        guard !Task.isCancelled else { return false }
        sidecar.save(pruningTo: Set(outline.scenes.map(\.contentHash)))
        publish(
                makeSnapshot(
                    entryID: entryID, outline: outline, sidecar: sidecar,
                    utterances: utterances))
        return true
    }

    /// 장·작품 요약 상향 전파 — 하위 요약이 전부 준비된 노드만, 결합 해시가
    /// 바뀐(더티) 노드만 다시 만든다.
    nonisolated private static func propagate(
        outline: DocumentOutline,
        sidecar: inout KnowledgeSidecar,
        parameters: CompletionParameters,
        engine: CompletionEngine
    ) async {
        // 장 = 연속된 씬들의 레벨 1–2 헤딩 경로 그룹.
        var chapters: [(path: [String], scenes: [DocumentOutline.Scene])] = []
        for scene in outline.scenes {
            let key = Array(scene.headingPath.prefix(2))
            if let last = chapters.indices.last, chapters[last].path == key {
                chapters[last].scenes.append(scene)
            } else {
                chapters.append((key, [scene]))
            }
        }

        var freshChapters: [KnowledgeSidecar.ChapterSummary] = []
        for chapter in chapters {
            guard !Task.isCancelled, gateAllows(deep: true) else { return }
            let childSummaries = chapter.scenes.compactMap {
                sidecar.sceneSummaries[$0.contentHash]?.summary
            }
            // 하위가 다 준비되지 않았거나, 씬 하나뿐이면(씬 요약으로 충분) 건너뛴다.
            guard childSummaries.count == chapter.scenes.count,
                chapter.scenes.count >= 2
            else { continue }
            let childrenHash = combinedHash(chapter.scenes.map(\.contentHash))
            if let existing = sidecar.chapterSummaries.first(where: {
                $0.headingPath == chapter.path && $0.childrenHash == childrenHash
            }) {
                freshChapters.append(existing)  // 메모 적중 — 재요약 금지
                continue
            }
            let summary = await rollup(
                childSummaries, level: .chapter, engine: engine, parameters: parameters)
            guard let summary else { continue }
            freshChapters.append(
                .init(
                    headingPath: chapter.path, childrenHash: childrenHash,
                    summary: summary, updatedAt: .now))
        }
        sidecar.chapterSummaries = freshChapters

        // 작품 요약 — 장 요약(없으면 씬 요약)에서. 씬 3개 미만이면 만들지 않는다
        // (C 창이 이미 전부를 본다 — 토큰당 품질, CLAUDE.md §5-1).
        guard outline.scenes.count >= 3, !Task.isCancelled else { return }
        let sources =
            freshChapters.count >= 2
            ? freshChapters.map(\.summary)
            : outline.scenes.compactMap { sidecar.sceneSummaries[$0.contentHash]?.summary }
        guard sources.count >= 2 else { return }
        let childrenHash = combinedHash(outline.scenes.map(\.contentHash))
        if sidecar.workSummary?.childrenHash == childrenHash { return }  // 메모 적중
        let summary = await rollup(
            sources, level: .work, engine: engine, parameters: parameters)
        guard let summary else { return }
        sidecar.workSummary = .init(
            childrenHash: childrenHash, summary: summary, updatedAt: .now)
    }

    // MARK: - 요약 호출 (공용 — 인덱서 본 경로 + MINTBench 리플레이 측정)

    /// 씬 하나를 요약한다. 실패·빈 결과는 nil — 호출부가 무시한다 (PLAN §9).
    /// public인 이유: 벤치가 **완전히 같은 프롬프트·규격**으로 지식을 만들어야
    /// 측정이 본 경로를 대표한다 (CLAUDE.md §2-7).
    nonisolated public static func summarizeScene(
        _ text: String, engine: CompletionEngine, parameters: CompletionParameters
    ) async -> String? {
        // 헤딩 한 줄뿐인 초미니 씬은 요약할 내용이 없다 — 모델에 넣으면 환각
        // 요약이 생긴다 (벤치에서 확인). 인덱서·벤치 공용 가드.
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            return nil
        }
        let summary =
            (try? await engine.generateOneShot(
                system: Prompts.sceneSystem,
                user: Prompts.sceneUser(text),
                maxTokens: 64,
                parameters: parameters)) ?? ""
        return summary.isEmpty ? nil : clamp(summary, to: 120)
    }

    /// 등록 인물 ↔ 과거 사건 참여자 소급 연결 (결정적·LLM 없음, CLAUDE.md §2-5).
    ///
    /// 왜 필요한가: 추출은 **그 시점에 등록된 카드만** 참여자로 링크한다
    /// (CLAUDE.md §3). 그래서 나중에 등록된 인물은 이미 메모된 과거 사건에
    /// 영영 연결되지 못하고, 역색인이 빈 채로 남아 카드의 "최근" 줄이 나오지
    /// 않는다. 등록 때마다 전 씬을 재추출하면 LLM 비용이 등록 횟수만큼 곱해지므로,
    /// 사건 요약문의 이름 매칭으로 잇는다.
    ///
    /// 트레이드오프: 요약에 이름이 있지만 실제 참여자가 아닌 경우("서연이 민준의
    /// 편지를 읽었다"의 민준)까지 링크된다. 이름이 언급된 사건은 그 인물의
    /// 맥락으로서 여전히 유효하다고 보고 받아들인다 — 역색인에 구멍이 남는 쪽이
    /// 더 나쁘다. 기존 참여자는 지우지 않는다(추출 당시의 판단을 신뢰).
    nonisolated private static func relinkParticipants(
        sidecar: inout KnowledgeSidecar, characters: [CharacterCard]
    ) {
        guard !characters.isEmpty else { return }
        let nameIndex = EventParser.nameIndex(characters)
        for (hash, events) in sidecar.events {
            var updated = events
            for offset in updated.indices {
                let summary = updated[offset].summary
                var participants = Set(updated[offset].participants)
                for (name, id) in nameIndex where summary.contains(name) {
                    participants.insert(id)
                }
                guard participants.count != updated[offset].participants.count else { continue }
                updated[offset].participants = Array(participants)
            }
            if updated != events { sidecar.events[hash] = updated }
        }
    }

    /// 씬 하나에서 사건을 뽑는다 (PLAN §6.3, M6-5) — 깊은 패스 전용.
    ///
    /// 요약과 **별도 호출**인 이유: 요약 경로는 이미 측정·출시됐고, 사건 파싱
    /// 실패가 요약까지 죽이면 회귀다 (docs/m6-events.md 결정 3).
    /// 등록 카드가 없으면 호출 자체를 건너뛴다 — 참여자를 링크할 수 없는 사건은
    /// 역색인에 들어가지 못해 토큰만 태운다 (CLAUDE.md §5-1).
    /// 벤치가 같은 프롬프트를 쓰도록 public (요약 경로와 같은 이유).
    nonisolated public static func extractEvents(
        _ text: String, sceneHash: String, characters: [CharacterCard],
        engine: CompletionEngine, parameters: CompletionParameters
    ) async -> [StoryEvent]? {
        let nameIndex = EventParser.nameIndex(characters)
        guard !nameIndex.isEmpty else { return nil }
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            return []  // 요약과 같은 초미니 씬 가드 — 뽑을 사건이 없다(환각 방지)
        }
        let output =
            (try? await engine.generateOneShot(
                system: Prompts.eventSystem,
                user: Prompts.eventUser(text, names: nameIndex.keys.sorted()),
                // 5b에서 줄마다 `상태:` 필드가 붙어 길어졌다 — 마지막 줄이
                // 중간에서 잘리면 그 사건·델타를 통째로 잃는다.
                maxTokens: 256,
                parameters: parameters)) ?? ""
        guard !output.isEmpty else { return nil }  // 실패 — 다음 패스가 재시도
        return EventParser.parse(output, sceneHash: sceneHash, nameIndex: nameIndex)
    }

    /// 하위 요약 묶음 → 상위 요약 (장 ≤300자 · 작품 ≤500자).
    nonisolated public enum RollupLevel { case chapter, work }

    nonisolated public static func rollup(
        _ summaries: [String], level: RollupLevel,
        engine: CompletionEngine, parameters: CompletionParameters
    ) async -> String? {
        let summary =
            (try? await engine.generateOneShot(
                system: level == .chapter ? Prompts.chapterSystem : Prompts.workSystem,
                user: Prompts.rollupUser(summaries),
                maxTokens: level == .chapter ? 128 : 160,
                parameters: parameters)) ?? ""
        return summary.isEmpty ? nil : clamp(summary, to: level == .chapter ? 300 : 500)
    }

    // MARK: - 보조

    /// 열·전력 시민의식 (PLAN §9) — `.serious` 이상이면 전부, 저전력이면 깊은
    /// 패스만 보류한다.
    nonisolated private static func gateAllows(deep: Bool) -> Bool {
        let process = ProcessInfo.processInfo
        switch process.thermalState {
        case .serious, .critical: return false
        default: break
        }
        if deep, process.isLowPowerModeEnabled { return false }
        return true
    }

    nonisolated private static func makeSnapshot(
        entryID: UUID, outline: DocumentOutline, sidecar: KnowledgeSidecar,
        utterances: [Utterance]
    ) -> KnowledgeSnapshot {
        KnowledgeSnapshot(
            entryID: entryID,
            outline: outline,
            summariesByHash: sidecar.sceneSummaries.mapValues(\.summary),
            chapterSummariesByPath: Dictionary(
                uniqueKeysWithValues: sidecar.chapterSummaries.map {
                    ($0.headingPath.joined(separator: " > "), $0.summary)
                }),
            workSummary: sidecar.workSummary?.summary,
            events: sidecar.events,
            utterances: utterances
        )
    }

    /// 하위 해시들의 결합 해시 — 장·작품 노드의 더티 판정 키.
    nonisolated private static func combinedHash(_ hashes: [String]) -> String {
        DocumentOutline.stableHash(hashes.joined(separator: "|"))
    }

    /// 요약 길이 상한 (PLAN §6.1) — 모델이 상한을 어겨도 저장은 규격대로.
    nonisolated private static func clamp(_ text: String, to limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(limit))
    }

    /// 삭제된 저널의 사이드카 정리 — 깊은 패스 끝에서만 (디렉터리 스캔은 싸지만
    /// 매 패스마다 할 일은 아니다).
    nonisolated private static func pruneOrphans(keeping liveEntryIDs: Set<UUID>) {
        let directory = KnowledgeSidecar.directory()
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "json" {
            let stem = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: stem), !liveEntryIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - 프롬프트 (요약 피라미드, PLAN §6.1)

    nonisolated private enum Prompts {
        static let sceneSystem = """
            너는 소설 장면을 요약하는 도우미다. 주어진 장면에서 일어난 일을 \
            인물 이름을 유지한 채 한국어 1~2문장(최대 120자)으로 요약한다. \
            설명·머리말·따옴표 없이 요약문만 출력한다.
            """

        static func sceneUser(_ text: String) -> String {
            """
            다음 장면을 요약하라.

            \(text)
            """
        }

        static let chapterSystem = """
            너는 소설의 장(章)을 요약하는 도우미다. 주어진 장면 요약들을 묶어 \
            줄거리를 한국어 2~3문장(최대 300자)으로 요약한다. 인물 이름을 \
            유지하고, 설명·머리말 없이 요약문만 출력한다.
            """

        static let workSystem = """
            너는 소설 전체 줄거리를 요약하는 도우미다. 주어진 요약들을 묶어 \
            지금까지의 이야기를 한국어 3~4문장(최대 500자)으로 요약한다. 인물 \
            이름을 유지하고, 설명·머리말 없이 요약문만 출력한다.
            """

        static func rollupUser(_ summaries: [String]) -> String {
            """
            다음 요약들을 묶어 하나의 줄거리로 요약하라.

            \(summaries.map { "- \($0)" }.joined(separator: "\n"))
            """
        }

        // MARK: 사건 추출 (PLAN §6.3) — JSON 대신 줄 형식 (docs/m6-events.md 결정 4)

        static let eventSystem = """
            너는 소설 장면에서 사건을 뽑는 도우미다. 장면에서 실제로 일어난 일만 \
            중요한 순서로 최대 3개까지, 한 줄에 하나씩 아래 형식으로 출력한다.

            사건요약(최대 80자) | 참여: 인물이름들 | 중요도: 1~5 | 상태: 인물 필드=값; 인물 필드=값

            상태는 이 사건으로 실제로 **바뀐** 인물 상태만 쓴다. 필드는 위치, 감정, \
            관계, 목표, 생사 다섯 가지만 쓴다. 값은 40자 이내로 짧게 쓴다. \
            바뀐 상태가 없으면 상태 항목을 통째로 생략한다.

            규칙: 주어진 인물 목록에 있는 이름만 참여와 상태에 쓴다. 장면에 없는 \
            일을 지어내지 않는다. 설명·머리말 없이 사건 줄만 출력한다.
            """

        /// 등록 인물 목록을 함께 준다 — 모델이 지어낸 인물은 파서가 버리지만
        /// (EventParser.resolve), 목록을 미리 주면 애초에 덜 지어낸다.
        static func eventUser(_ text: String, names: [String]) -> String {
            """
            인물 목록: \(names.joined(separator: ", "))

            다음 장면에서 사건을 뽑아라.

            \(text)
            """
        }
    }
}
