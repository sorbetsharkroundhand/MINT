import Foundation
import MINTCore
import MLXLMCommon

/// 실제 앱 저장소를 읽는 벤치 전용 컨테이너. 쓰기는 하지 않는다.
private struct DongbaekLibrary: Decodable {
    var entries: [JournalEntry]
    var folders: [JournalFolder]
}

private struct DongbaekGoldCase {
    var label: String
    var request: String
    /// 각 그룹에서 하나 이상 적중해야 한 개 개념을 맞힌 것으로 본다.
    var requiredConcepts: [[String]]
    /// 사실을 뒤집는 문구. 단순 누락과 명시적 오답을 분리한다.
    var forbiddenPatterns: [String] = []
}

private struct DongbaekCaseScore {
    var hit: Int
    var total: Int
    var contradictions: [String]
}

/// 사용자의 실제 원고에 있는 큰따옴표 30개를 담화 순서대로 전수 대조한다.
/// 골드는 원문 주변의 명시적 주어·질문/응답·연속 발화를 사람이 읽어 확정했다.
/// 이름 없는 주변 인물은 임의 카드로 승격하지 않고 문맥 역할로 남긴다.
func runDongbaekDialogueEvaluation() async -> Bool {
    let fileURL = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
    ).first?.appendingPathComponent("MINT/entries.json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let fileURL,
          let data = try? Data(contentsOf: fileURL),
          let library = try? decoder.decode(DongbaekLibrary.self, from: data),
          let storedEntry = library.entries.first(where: { $0.title == "동백꽃" })
    else {
        print("❌ ~/Documents/MINT/entries.json에서 ‘동백꽃’을 찾지 못했습니다.")
        return false
    }

    var cards = storedEntry.characters ?? []
    let outline = DocumentOutline.parse(storedEntry.body)
    if let narrator = BackgroundIndexer.narratorCardIfNeeded(
        body: storedEntry.body, outline: outline, characters: cards,
        rejectedNames: Set(storedEntry.rejectedCharacterNames ?? [])
    ) {
        cards.append(narrator)
    }
    let dialogues = DialogueAttribution.dialogues(in: storedEntry.body, cards: cards)
    let gold = [
        "점순", "화자", "점순", "점순", "점순", "점순", "화자",
        "동리 어른(미등록)", "점순", "점순", "화자", "화자", "점순",
        "화자", "점순", "점순", "점순", "화자", "화자", "점순",
        "화자", "점순", "점순", "화자", "점순", "화자", "점순",
        "점순", "화자", "점순 어머니(미등록)"
    ]
    print("== 동백꽃 전체 대사 수집·화자 귀속 ==")
    print("큰따옴표 수집: \(dialogues.count)/\(gold.count) · 등록 카드: \(cards.map(\.name).joined(separator: ", "))")
    var correct = 0
    for (index, dialogue) in dialogues.enumerated() {
        let expected = gold.indices.contains(index) ? gold[index] : "(골드 없음)"
        let pass = dialogue.speakerLabel == expected
        if pass { correct += 1 }
        print(
            "\(pass ? "✅" : "❌") \(index + 1). \(dialogue.speakerLabel)"
                + " [정답 \(expected) · \(dialogue.attribution.rawValue)] \"\(dialogue.text)\""
        )
    }
    let unresolved = dialogues.count { $0.attribution == .unresolved }
    print("판정: 화자 \(correct)/\(gold.count) · 미상 \(unresolved) · 누락 \(max(0, gold.count - dialogues.count))")

    var evaluationEntry = storedEntry
    evaluationEntry.characters = cards
    let snapshot = KnowledgeSnapshot(
        entryID: evaluationEntry.id, outline: outline, summariesByHash: [:],
        dialogues: dialogues, characters: cards, body: evaluationEntry.body
    )
    let source = AgentSourceSnapshot(
        activeEntry: evaluationEntry, entries: [evaluationEntry], folders: [],
        knowledge: snapshot, caretUTF16: (evaluationEntry.body as NSString).length
    )
    let runtime = AgentRuntime(generator: DongbaekNoGeneration(), maxSteps: 1)
    let agentPassed: Bool
    do {
        let result = try await runtime.run(
            request: "큰따옴표 안의 모든 대사를 원문 순서대로 수집해서 누구의 대사인지 기록해 줘.",
            history: [], source: source, parameters: CompletionParameters(),
            onEvent: { _ in }
        )
        agentPassed = result.steps == 0
            && result.text.contains("큰따옴표 대사 30개")
            && dialogues.allSatisfy { result.text.contains($0.text) }
        print("\n== 동백꽃 Agent 결정적 답변 ==")
        print(result.text)
        print("Agent 판정: \(agentPassed ? "30개 전수 응답 · 모델 호출 0회" : "실패")")
    } catch {
        agentPassed = false
        print("Agent 판정: 실패 · \(error.localizedDescription)")
    }
    return dialogues.count == gold.count && correct == gold.count
        && unresolved == 0 && agentPassed
}

private struct DongbaekNoGeneration: AgentTurnGenerating {
    func generateAgentTurn(
        messages _: [AgentChatMessage], tools _: [ToolSpec],
        parameters _: CompletionParameters,
        onChunk _: @Sendable @escaping (String) -> Void
    ) async throws -> AgentModelTurn {
        throw CancellationError()
    }
}

/// 사용자의 「동백꽃」을 직접 묻는 실모델 평가. 답변 원문·도구 trace·지연을
/// 전부 출력해 자동 점수만으로 가려지는 뉘앙스를 사람이 함께 검토할 수 있다.
func runDongbaekAgentEvaluation(
    engine: CompletionEngine, options: BenchOptions
) async -> Bool {
    let fileURL = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
    ).first?
        .appendingPathComponent("MINT/entries.json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let fileURL,
          let data = try? Data(contentsOf: fileURL),
          let library = try? decoder.decode(DongbaekLibrary.self, from: data),
          let entry = library.entries.first(where: { $0.title == "동백꽃" })
    else {
        print("❌ ~/Documents/MINT/entries.json에서 ‘동백꽃’을 찾지 못했습니다.")
        return false
    }

    var sidecar = KnowledgeSidecar.load(entryID: entry.id)
    sidecar = await prepareDongbaekKnowledgeIfNeeded(
        entry: entry, sidecar: sidecar, engine: engine, options: options
    )
    var evaluationEntry = entry
    var evaluationCards = entry.characters ?? []
    if let narrator = BackgroundIndexer.narratorCardIfNeeded(
        body: entry.body, outline: .parse(entry.body), characters: evaluationCards,
        rejectedNames: Set(entry.rejectedCharacterNames ?? [])
    ) {
        evaluationCards.append(narrator)
        evaluationEntry.characters = evaluationCards
    }
    let snapshot = makeDongbaekSnapshot(entry: evaluationEntry, sidecar: sidecar)
    let source = AgentSourceSnapshot(
        activeEntry: evaluationEntry, entries: library.entries, folders: library.folders,
        knowledge: snapshot, caretUTF16: (evaluationEntry.body as NSString).length
    )
    let profile = snapshot.narrationProfile
    let quotedEvents = snapshot.events.count(where: { $0.quote != nil })
    let duplicateEvents = snapshot.events.count - Set(snapshot.events.map {
        "\($0.sceneHash)|\($0.stableKey)"
    }).count

    print("\n== 동백꽃 Story Intelligence 실데이터 ==")
    print("원문: \(entry.body.count)자 · 분석 청크: \(snapshot.outline.scenes.count)개")
    print("캐시: v\(sidecar.schemaVersion) · 세대 \(sidecar.generation)")
    print(
        "서술: \(profile.displayText) · 등록 인물: "
            + "\((evaluationEntry.characters ?? []).map(\.name).joined(separator: ", "))"
    )
    print(
        "장면 요약 \(sidecar.sceneSummaries.count) · 사건 \(snapshot.events.count)"
            + "(직접 근거 \(quotedEvents), 중복 \(duplicateEvents))"
            + " · 전체 대사 \(snapshot.dialogues.count)"
            + "(등록 귀속 \(snapshot.utterances.count), 미상 \(snapshot.dialogues.count { $0.attribution == .unresolved }))"
            + " · 회상 구간 "
            + "\(snapshot.segmentsByScene.values.flatMap { $0 }.count)"
            + " · 플롯 \(snapshot.plotThreads.count)"
    )
    if let work = snapshot.workSummary { print("작품 요약: \(work)") }
    for (index, event) in snapshot.events.enumerated() {
        print(
            "  사건 \(index + 1). \(event.summary)"
                + " [\(event.quote == nil ? "추론" : "직접")]"
        )
    }
    for thread in snapshot.plotThreads {
        print("  플롯. \(thread.title) — \(thread.summary) [\(thread.status.rawValue)]")
    }

    let cases: [DongbaekGoldCase] = [
        .init(
            label: "서술 시점",
            request: "이 작품의 서술 시점과 화자가 누구인지, 점순이와 같은 사람인지 구분해서 알려 줘.",
            requiredConcepts: [
                ["1인칭"],
                [
                    "이름이 밝혀지지", "이름 미상", "익명", "이름은 나오지",
                    "이름이 언급되지", "이름이 명시되지"
                ],
                [
                    "점순이와 다른", "점순과 다른", "점순이가 화자가 아니",
                    "점순이와 같은 사람이 아니", "점순이는 타인",
                    "서로 다른 인물", "서로 다른 존재"
                ]
            ],
            forbiddenPatterns: [
                "점순(이|이가)? (자신이 )?직접 자신의 이야기",
                "점순(이|이가)? 바로 (이 작품의 )?(화자|1인칭 서술자)",
                "화자는[^.\\n]{0,30}(중년 여성|여성으로 추정)",
                "대강이[^.\\n]{0,15}(자녀|아이)"
            ]
        ),
        .init(
            label: "감자의 의미",
            request: "점순이가 화자에게 감자를 준 이유와 거절당한 뒤의 행동을 원문 근거에 맞춰 설명해 줘.",
            requiredConcepts: [
                ["호감", "애정", "관심", "마음", "구애", "친밀"], ["거절"],
                ["얼굴", "붉", "빨개"], ["눈물"], ["달아", "논둑", "도주"]
            ],
            forbiddenPatterns: [
                "괴롭히려고 감자", "적대감.*감자", "자원을 나누",
                "경제[^.\\n]{0,20}감자", "가난[^.\\n]{0,20}감자",
                "권위[^.\\n]{0,30}(과시|우위)", "모욕하려", "굴복시키려"
            ]
        ),
        .init(
            label: "수탉의 죽음",
            request: "마지막에 누가 누구의 수탉을 죽였는지 단정적으로 답하고, 직전 상황도 한 문장으로 설명해 줘.",
            requiredConcepts: [
                ["화자", "나"], ["점순네", "점순이의", "점순의"],
                ["수탉"], ["때려", "단매"], ["죽"]
            ],
            forbiddenPatterns: [
                "점순이에게 의해 수탉이 죽",
                "점순[^.\\n]{0,25}가 점순[^.\\n]{0,20}수탉을 죽",
                "직전 상황[^.\\n]{0,80}닭 죽은 건",
                "점순이가 자신의 수탉을 해치",
                "화자[^.\\n]{0,30}우리 수탉[^.\\n]{0,30}(때려|죽)",
                "화자[^.\\n]{0,60}(자신|자기)의 수탉[^.\\n]{0,30}(때려|죽)",
                "점순의 수탉이 아닌[^.\\n]{0,20}(자신|자기)의 수탉"
            ]
        ),
        .init(
            label: "시간 구조",
            request: "이 작품의 현재-회상-현재 구조를 나누고, 회상이 시작하고 끝나는 원문 표지를 짚어 줘.",
            requiredConcepts: [
                ["현재"], ["회상"], ["나흘 전"],
                ["그랬던 걸 이렇게", "그랬던 것을 이렇게"]
            ]
        ),
        .init(
            label: "신분과 관계",
            request: "점순이와 화자의 관계가 왜 단순한 적대가 아닌지, 두 집안의 신분 차이까지 포함해 설명해 줘.",
            requiredConcepts: [
                ["마름"], ["땅", "집", "소작", "배재", "세입자", "농가", "농민"],
                ["호감", "애정", "구애", "마음", "친밀"],
                ["갈등", "도발", "닭싸움", "적대"],
                ["동백꽃"]
            ],
            forbiddenPatterns: [
                "점순[^.\\n]{0,40}(지배하려|계급 지배)",
                "(위계 재확립|지배와 복종)",
                "서로의 고독", "점순이의 위로"
            ]
        ),
        .init(
            label: "점순의 말투",
            request: "점순이의 말투를 보여 주는 실제 대사 두 개를 원문에서 골라 인용해 줘.",
            requiredConcepts: [
                ["염려 마서유", "갈 때 되면 어련히 갈라구"],
                [
                    "내 안 이를 테니", "느 집엔 이거 없지",
                    "이담부텀 안 그럴 테냐", "요담부터 또 그래 봐라",
                    "이놈의 씨닭"
                ]
            ],
            forbiddenPatterns: ["이놈의 계집애! 남의 닭"]
        ),
        .init(
            label: "전체 플롯",
            request: "작품의 사건을 실제 시간 순서대로 핵심 5단계로 요약해 줘. 감자, 고추장, 닭싸움, 결말을 빠뜨리지 마.",
            requiredConcepts: [
                ["감자"], ["씨암탉"], ["고추장"], ["수탉"], ["동백꽃"]
            ],
            forbiddenPatterns: [
                "점순네 씨암탉", "우리 수탉[^.\\n]{0,30}이겼",
                "점순이[^.\\n]{0,30}화자의 닭을 훔쳐[^.\\n]{0,20}의심",
                "점순이 화자에게 맞고", "점순이[^.\\n]{0,20}감자를 밀어",
                "화자가[^.\\n]{0,30}암탉을 때리",
                "고추장[^.\\n]{0,50}(수탉|자신의 닭)[^.\\n]{0,20}죽",
                "고추장[^.\\n]{0,50}이기게 했", "단도(로|하에)",
                "점순이가[^.\\n]{0,30}(모방|화자의 수탉을 죽)"
            ]
        )
    ]

    let parameters = CompletionParameters(
        modelID: options.modelID, promptStyle: .instruct, maxTokens: 512,
        temperature: min(0.3, options.temperature), topP: 0.9,
        maxPromptTokens: 3072, kvCacheEnabled: true
    )
    var totalHit = 0
    var totalConcepts = 0
    var contradictionCount = 0
    var completed = 0

    print("\n== 동백꽃 Agent 골드 질의 ==")
    for (index, test) in cases.enumerated() {
        let runtime = AgentRuntime(generator: engine, maxSteps: 6)
        let recorder = DongbaekTraceRecorder()
        let started = Date()
        do {
            let result = try await runtime.run(
                request: test.request, history: [], source: source,
                parameters: parameters, onEvent: recorder.record
            )
            let score = scoreDongbaek(result.text, against: test)
            totalHit += score.hit
            totalConcepts += score.total
            contradictionCount += score.contradictions.count
            completed += 1
            let trace = result.toolTrace.map(\.toolName).joined(separator: " → ")
            print(
                "\n[\(index + 1)/\(cases.count)] \(test.label) · 개념 "
                    + "\(score.hit)/\(score.total) · 모순 \(score.contradictions.count)"
                    + " · \(format(Date().timeIntervalSince(started)))"
            )
            print("도구: \(trace.isEmpty ? "없음" : trace)")
            print("답변: \(result.text)")
            if !score.contradictions.isEmpty {
                print("금지 주장: \(score.contradictions.joined(separator: ", "))")
            }
        } catch {
            print("\n[\(index + 1)/\(cases.count)] \(test.label) ❌ \(error.localizedDescription)")
        }
    }

    let accuracy = totalConcepts == 0 ? 0 : Double(totalHit) / Double(totalConcepts)
    print("\n== 동백꽃 Agent 판정 ==")
    print(
        String(
            format: "완료 %d/%d · 골드 개념 %d/%d (%.0f%%) · 명시적 모순 %d",
            completed, cases.count, totalHit, totalConcepts, accuracy * 100,
            contradictionCount
        )
    )
    // 골드 벤치는 품질 회귀 게이트다. 답변 누락은 80% 아래, 사실 역전은 한 건도
    // 허용하지 않는다. 출력 원문은 임계 통과 여부와 별개로 항상 사람이 검토한다.
    return completed == cases.count && accuracy >= 0.8 && contradictionCount == 0
}

/// 스키마가 바뀌었거나 인덱싱이 중단된 경우에만 실제 제품 추출기를 재생한다.
/// 원문은 읽기 전용이며, 결과는 버려도 복구되는 지식 사이드카에만 저장한다.
private func prepareDongbaekKnowledgeIfNeeded(
    entry: JournalEntry, sidecar loaded: KnowledgeSidecar,
    engine: CompletionEngine, options: BenchOptions
) async -> KnowledgeSidecar {
    let outline = DocumentOutline.parse(entry.body)
    let liveHashes = Set(outline.scenes.map(\.contentHash))
    let complete = outline.scenes.allSatisfy { scene in
        loaded.sceneSummaries[scene.contentHash] != nil
            && loaded.events[scene.contentHash] != nil
            && loaded.insights[scene.contentHash] != nil
            && loaded.segments[scene.contentHash] != nil
    } && loaded.workSummary != nil
    guard !complete else { return loaded }

    print("\n== 동백꽃 지식 캐시 재구축 ==")
    print("원문은 변경하지 않고 v\(KnowledgeSidecar.currentSchemaVersion) 파생 캐시만 갱신합니다.")
    var sidecar = loaded
    let cards = entry.characters ?? []
    let source = entry.body as NSString
    let narration = NarrationAnalyzer.analyze(
        body: entry.body, outline: outline, characters: cards
    )
    let context = BackgroundIndexer.StoryAnalysisContext(
        narration: narration, characters: cards
    )
    let explicitFlashbacks = TemporalShiftDetector.explicitFlashbackSegments(
        in: entry.body, outline: outline, narration: narration
    )
    let parameters = CompletionParameters(
        modelID: options.modelID, promptStyle: .instruct, maxTokens: 384,
        temperature: min(0.3, options.temperature), topP: 0.9,
        maxPromptTokens: 3072, kvCacheEnabled: true
    )

    for (offset, scene) in outline.scenes.enumerated() {
        let hash = scene.contentHash
        let text = source.substring(
            with: NSRange(
                location: scene.utf16Range.lowerBound,
                length: scene.utf16Range.count
            )
        )
        print("  [\(offset + 1)/\(outline.scenes.count)] 분석 청크")
        if sidecar.sceneSummaries[hash] == nil,
           let analysis = await BackgroundIndexer.analyzeScene(
               text, context: context, engine: engine, parameters: parameters
           ) {
            sidecar.sceneSummaries[hash] = .init(
                contentHash: hash, headingPath: scene.headingPath,
                summary: analysis.summary, title: analysis.title,
                narrativeType: analysis.narrativeType, pov: analysis.pov,
                location: analysis.location
            )
        }
        if sidecar.events[hash] == nil,
           let events = await BackgroundIndexer.extractEvents(
               text, sceneHash: hash, characters: cards, context: context,
               engine: engine, parameters: parameters
           ) {
            sidecar.events[hash] = events
        }
        if sidecar.insights[hash] == nil,
           let insights = await BackgroundIndexer.extractInsights(
               text, sceneHash: hash, characters: cards, context: context,
               engine: engine, parameters: parameters
           ) {
            sidecar.insights[hash] = insights
        }
        if let explicit = explicitFlashbacks[hash] {
            sidecar.segments[hash] = SceneSegmentation(segments: explicit)
        } else if sidecar.segments[hash] == nil {
            if TemporalShiftDetector.hasCandidate(in: text) {
                if let segments = await BackgroundIndexer.analyzeSegments(
                    text, sceneHash: hash, context: context,
                    engine: engine, parameters: parameters
                ) {
                    sidecar.segments[hash] = SceneSegmentation(segments: segments)
                }
            } else {
                sidecar.segments[hash] = SceneSegmentation()
            }
        }
        sidecar.save(pruningTo: liveHashes)
    }

    var chapterGroups: [(path: [String], scenes: [DocumentOutline.Scene])] = []
    for scene in outline.scenes {
        let path = Array(scene.headingPath.prefix(2))
        if let last = chapterGroups.indices.last, chapterGroups[last].path == path {
            chapterGroups[last].scenes.append(scene)
        } else {
            chapterGroups.append((path, [scene]))
        }
    }
    var chapters: [KnowledgeSidecar.ChapterSummary] = []
    for chapter in chapterGroups where chapter.scenes.count >= 2 {
        let summaries = chapter.scenes.compactMap {
            sidecar.sceneSummaries[$0.contentHash]?.summary
        }
        guard summaries.count == chapter.scenes.count,
              let summary = await BackgroundIndexer.rollup(
                  summaries, level: .chapter, engine: engine, parameters: parameters
              )
        else { continue }
        chapters.append(.init(
            headingPath: chapter.path,
            childrenHash: dongbaekCombinedHash(chapter.scenes.map(\.contentHash)),
            summary: summary
        ))
    }
    sidecar.chapterSummaries = chapters

    let sceneSummaries = outline.scenes.compactMap {
        sidecar.sceneSummaries[$0.contentHash]?.summary
    }
    if sceneSummaries.count >= 2,
       let summary = await BackgroundIndexer.rollup(
           sceneSummaries, level: .work, engine: engine, parameters: parameters
       ) {
        sidecar.workSummary = .init(
            childrenHash: dongbaekCombinedHash(outline.scenes.map(\.contentHash)),
            summary: summary
        )
    }

    let orderedEvents = outline.scenes.flatMap { sidecar.events[$0.contentHash] ?? [] }
    let eventMemo = dongbaekCombinedHash(orderedEvents.map(\.stableKey))
    if let graph = await BackgroundIndexer.analyzeEventGraph(
        events: orderedEvents, characters: cards,
        engine: engine, parameters: parameters
    ) {
        sidecar.eventGraph = .init(
            causalLinks: graph.causalLinks, identities: graph.identities,
            chronoEdges: graph.chronoEdges, memoHash: eventMemo
        )
    }
    if let threads = await BackgroundIndexer.analyzePlotThreads(
        events: orderedEvents, characters: cards,
        causalLinks: sidecar.eventGraph?.causalLinks ?? [],
        engine: engine, parameters: parameters
    ) {
        sidecar.plotThreads = .init(
            threads: PlotThreadParser.reconcile(
                new: threads, previous: sidecar.plotThreads?.threads ?? []
            ),
            memoHash: dongbaekCombinedHash(orderedEvents.map(\.stableKey) + ["plot"])
        )
    }
    sidecar.save(pruningTo: liveHashes)
    print("  완료: 요약 \(sidecar.sceneSummaries.count) · 사건 \(orderedEvents.count)")
    return sidecar
}

private func dongbaekCombinedHash(_ hashes: [String]) -> String {
    DocumentOutline.stableHash(hashes.joined(separator: "|"))
}

private func makeDongbaekSnapshot(
    entry: JournalEntry, sidecar: KnowledgeSidecar
) -> KnowledgeSnapshot {
    let outline = DocumentOutline.parse(entry.body)
    let cards = entry.characters ?? []
    let dialogues = DialogueAttribution.dialogues(in: entry.body, cards: cards)
    return KnowledgeSnapshot(
        entryID: entry.id,
        outline: outline,
        summariesByHash: sidecar.sceneSummaries.mapValues(\.summary),
        chapterSummariesByPath: Dictionary(
            uniqueKeysWithValues: sidecar.chapterSummaries.map {
                ($0.headingPath.joined(separator: " > "), $0.summary)
            }
        ),
        workSummary: sidecar.workSummary?.summary,
        events: sidecar.events,
        dialogues: dialogues,
        utterances: DialogueAttribution.utterances(from: dialogues),
        sceneSummaries: sidecar.sceneSummaries,
        insights: sidecar.insights,
        segments: sidecar.segments,
        eventGraph: sidecar.eventGraph,
        plotThreadAnalysis: sidecar.plotThreads,
        recordedConversations: entry.recordedConversations ?? [],
        conversationMeta: sidecar.conversationMeta,
        characters: cards,
        keyScenes: entry.keyScenes ?? [],
        rejectedKeySceneCandidateHashes: Set(entry.rejectedKeySceneCandidateHashes ?? []),
        overrides: NarrativeOverrides(entry.narrativeOverrides ?? []),
        body: entry.body
    )
}

private func scoreDongbaek(
    _ answer: String, against test: DongbaekGoldCase
) -> DongbaekCaseScore {
    let normalized = answer.folding(
        options: [.caseInsensitive, .diacriticInsensitive], locale: .current
    )
    let hit = test.requiredConcepts.count { alternatives in
        alternatives.contains { normalized.localizedCaseInsensitiveContains($0) }
    }
    let contradictions = test.forbiddenPatterns.filter { pattern in
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return false }
        return expression.firstMatch(
            in: answer, range: NSRange(location: 0, length: (answer as NSString).length)
        ) != nil
    }
    return DongbaekCaseScore(
        hit: hit, total: test.requiredConcepts.count,
        contradictions: contradictions
    )
}

private final class DongbaekTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AgentRuntimeEvent] = []

    func record(_ event: AgentRuntimeEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
}
