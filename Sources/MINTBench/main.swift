import Foundation
import MINTCore

// MINT M2 — 추론 리스크 선검증 CLI (PLAN §6 M2, docs/m2-inference.md)
//
// 하드코딩된 한국어 이어쓰기 프롬프트로 모델을 로드해 생성 1회 이상을 돌리고,
// 출력·지연(로드 / 첫 청크 / 전체 / tok/s)을 로그로 남긴다.
// PLAN §2 목표(첫 제안 <~300–500ms) 충족 여부를 판정해 기본 모델을 확정한다.
//
// Mac(Apple Silicon)에서:
//   swift run -c release MINTBench
//   swift run -c release MINTBench --model mlx-community/Qwen2.5-3B-Instruct-4bit --style both

struct BenchOptions {
    var modelID = CompletionParameters().modelID
    var styles: [PromptStyle] = [.continuation, .instruct]
    var maxTokens = CompletionParameters().maxTokens
    var temperature = CompletionParameters().temperature
    var runs = 2
    var prompt = "오늘은 오랜만에 한강을 따라 오래 걸었다. 바람이 차가웠지만 기분이 좋았고,"
    // 리플레이 벤치 (PLAN §13) — 실제 원고를 컷포인트에서 잘라 제안 품질·지연 측정.
    var replayPath: String?
    var cuts = 12
    var truthChars = 40
    var contextChars = CompletionSettings.defaultNovelContextCharacters
    var title = ""
    var genre = ""
    /// 리플레이 전에 원고 전체를 요약(씬→장→작품)해 B 블록으로 주입 (M6, PLAN §11).
    var knowledge = false
    /// 모델 로드 없이 인물 감지기만 돌려 후보 전체를 출력 (정밀도 점검, PLAN §7).
    var detectOnly = false
    /// --detect-only 정밀도 채점용 정답 인물 (쉼표 구분).
    var truePeople = ""
    /// 실제 모델의 네이티브 tool call과 Agent loop를 짧게 검증 (PLAN §14 M10).
    var agentSmoke = false

    enum ParseResult {
        case options(BenchOptions)
        case help
        case failure(String)
    }

    static func parse(_ arguments: [String]) -> ParseResult {
        var options = BenchOptions()
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--help", "-h":
                return .help
            case "--model":
                guard let value = iterator.next() else { return .failure("--model 값 누락") }
                options.modelID = value
            case "--style":
                guard let value = iterator.next() else { return .failure("--style 값 누락") }
                switch value {
                case "both":
                    options.styles = [.continuation, .instruct]
                case let raw:
                    guard let style = PromptStyle(rawValue: raw) else {
                        return .failure("알 수 없는 스타일: \(raw) (continuation|instruct|both)")
                    }
                    options.styles = [style]
                }
            case "--max-tokens":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    return .failure("--max-tokens 는 양의 정수여야 함")
                }
                options.maxTokens = parsed
            case "--temperature":
                guard let value = iterator.next(), let parsed = Double(value), parsed >= 0 else {
                    return .failure("--temperature 는 0 이상의 실수여야 함")
                }
                options.temperature = parsed
            case "--runs":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    return .failure("--runs 는 양의 정수여야 함")
                }
                options.runs = parsed
            case "--prompt":
                guard let value = iterator.next(), !value.isEmpty else {
                    return .failure("--prompt 값 누락")
                }
                options.prompt = value
            case "--replay":
                guard let value = iterator.next(), !value.isEmpty else {
                    return .failure("--replay 파일 경로 누락")
                }
                options.replayPath = value
            case "--cuts":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    return .failure("--cuts 는 양의 정수여야 함")
                }
                options.cuts = parsed
            case "--truth-chars":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    return .failure("--truth-chars 는 양의 정수여야 함")
                }
                options.truthChars = parsed
            case "--context":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    return .failure("--context 는 양의 정수여야 함")
                }
                options.contextChars = parsed
            case "--title":
                guard let value = iterator.next() else { return .failure("--title 값 누락") }
                options.title = value
            case "--genre":
                guard let value = iterator.next() else { return .failure("--genre 값 누락") }
                options.genre = value
            case "--knowledge":
                options.knowledge = true
            case "--detect-only":
                options.detectOnly = true
            case "--true-people":
                guard let value = iterator.next() else { return .failure("--true-people 값 누락") }
                options.truePeople = value
            case "--agent-smoke":
                options.agentSmoke = true
            default:
                return .failure("알 수 없는 옵션: \(flag)")
            }
        }
        return .options(options)
    }

    static let usage = """
        사용법: swift run -c release MINTBench [옵션]
          --model <hf-id>      Hugging Face 저장소 id (기본: \(CompletionParameters().modelID))
          --style <s>          continuation | instruct | both (기본: both — PLAN §9-4 비교 실험)
          --max-tokens <n>     생성 토큰 상한 (기본: \(CompletionParameters().maxTokens))
          --temperature <x>    샘플링 온도 (기본: \(CompletionParameters().temperature))
          --runs <n>           스타일별 반복 횟수 (기본: 2 — 1회차는 워밍업 포함)
          --prompt <text>      이어쓸 한국어 앞부분 (하드코딩 기본값 있음)
          --agent-smoke       실제 모델로 Agent 네이티브 tool call 3종과 전체 loop 검증
          --help               이 도움말

        리플레이 벤치 (PLAN §13 — 실제 원고로 수락 프록시·TTFC·KV 효과 측정):
          --replay <파일>      원고 텍스트 파일 — 문장 경계 컷포인트마다 제안을
                               생성해 정답(이어지는 원문)과 비교. 컷마다 2회 실행:
                               1회차 콜드, 2회차 웜(KV 프리필 재사용 검증)
          --cuts <n>           컷포인트 수 (기본: 12)
          --truth-chars <n>    정답으로 비교할 이어지는 원문 길이 (기본: 40자)
          --context <n>        컷 앞에서 읽는 컨텍스트 길이 (기본: 4000자)
          --title <text>       작품 제목 — 지정 시 소설 헤더(A)를 조립에 포함
          --genre <text>       작품 장르 — 위와 동일
          --knowledge          리플레이 전에 원고를 요약(씬→장→작품)해 B 블록으로
                               주입 — 인덱서(M6)와 같은 프롬프트·규격 (PLAN §11)

        모델 대안(가벼운 순): \(ModelPresets.qwen2_5_1_5B)
                              \(ModelPresets.qwen2_5_3B)
                              \(ModelPresets.qwen3_30B_A3B)
        """
}

/// 다운로드 진행률을 10% 단위로만 찍는 리포터 (progressHandler는 아무 스레드에서나 옴).
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTenth = -1

    func report(_ fraction: Double) {
        let tenth = Int(fraction * 10)
        lock.lock()
        defer { lock.unlock() }
        guard tenth > lastTenth else { return }
        lastTenth = tenth
        print(String(format: "  모델 다운로드/준비 %3.0f%%", fraction * 100))
    }
}

func format(_ interval: TimeInterval?) -> String {
    guard let interval else { return "—" }
    return String(format: "%.2fs", interval)
}

/// 두 텍스트가 2자 이상 어절(문장부호 제거)을 공유하는가 — 리플레이 보조 지표.
func sharesWord(_ a: String, _ b: String) -> Bool {
    func words(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 2 })
    }
    return !words(a).isDisjoint(with: words(b))
}

// MARK: - 실행

let parseResult = BenchOptions.parse(Array(CommandLine.arguments.dropFirst()))
let options: BenchOptions
switch parseResult {
case .help:
    print(BenchOptions.usage)
    exit(0)
case .failure(let message):
    print("오류: \(message)\n")
    print(BenchOptions.usage)
    exit(2)
case .options(let parsed):
    options = parsed
}

// 인물 감지 정밀도 점검 — 모델 로드 없이 감지기만 (결정적이라 GPU 불필요, PLAN §7).
if options.detectOnly {
    guard let replayPath = options.replayPath,
        let raw = try? String(contentsOfFile: replayPath, encoding: .utf8)
    else {
        print("❌ --detect-only 는 --replay <원고 파일>이 필요하다.")
        exit(2)
    }
    let outline = DocumentOutline.parse(raw)
    let candidates = CharacterDetector.detect(
        body: raw, outline: outline, known: [], rejected: [])
    let truth = Set(
        options.truePeople.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    print("== 인물 감지 정밀도 (씬 \(outline.scenes.count) · 후보 \(candidates.count)) ==")
    var tp = 0
    for c in candidates {
        let mark = truth.isEmpty ? "•" : (truth.contains(c.name) ? "✅인물" : "❌오탐")
        if truth.contains(c.name) { tp += 1 }
        print(
            "  \(mark) \(c.name) — 언급\(c.mentions)·씬\(c.sceneCount)·유정\(c.animacyHits)·격\(c.caseRoleCount)")
    }
    if !truth.isEmpty {
        let precision = candidates.isEmpty ? 0 : Double(tp) / Double(candidates.count) * 100
        let recall = Double(tp) / Double(truth.count) * 100
        print(
            String(
                format: "Precision %.0f%% (%d/%d) · Recall %.0f%% (%d/%d)",
                precision, tp, candidates.count, recall, tp, truth.count))
    }
    exit(0)
}

if options.agentSmoke {
    print("== MINT Writing Agent 실모델 검증 ==")
    print("모델       : \(options.modelID)")
    print("응답 토큰 상한: \(max(256, options.maxTokens)) · 온도: \(options.temperature)")
    print("")
} else {
    print("== MINT M2 추론 선검증 ==")
    print("모델     : \(options.modelID)")
    print("스타일   : \(options.styles.map(\.rawValue).joined(separator: ", "))")
    print("토큰 상한: \(options.maxTokens) · 온도: \(options.temperature) · 반복: \(options.runs)")
    print("프롬프트 : \(options.prompt)")
    print("")
}

let engine = CompletionEngine()
let reporter = ProgressReporter()
let loadStart = Date()
do {
    var parameters = CompletionParameters()
    parameters.modelID = options.modelID
    try await engine.preload(parameters: parameters) { fraction in
        reporter.report(fraction)
    }
} catch {
    print("❌ 모델 로드 실패: \(error.localizedDescription)")
    print("   저장소 id가 존재하는지, 디스크/메모리 여유가 있는지 확인하세요.")
    print("   가벼운 대안: --model \(ModelPresets.qwen2_5_3B)")
    exit(1)
}
print(String(format: "✅ 모델 로드 완료: %.1fs (다운로드 캐시 포함)", Date().timeIntervalSince(loadStart)))

// Agent 실모델 스모크 — 자동완성 벤치와 섞지 않고 tool 형식 준수를 별도 판정한다.
if options.agentSmoke {
    let ok = await runAgentSmoke(engine: engine, options: options)
    exit(ok ? 0 : 1)
}

// 리플레이 모드 — 단발 측정 대신 원고 기반 품질 루프 (PLAN §13).
if let replayPath = options.replayPath {
    let ok = await runReplay(path: replayPath, engine: engine, options: options)
    exit(ok ? 0 : 1)
}

struct RunRecord {
    let style: PromptStyle
    let run: Int
    let completion: CompletionEngine.Completion
}

var records: [RunRecord] = []

for style in options.styles {
    print("\n-- 스타일: \(style.rawValue) --")
    let parameters = CompletionParameters(
        modelID: options.modelID,
        promptStyle: style,
        maxTokens: options.maxTokens,
        temperature: options.temperature
    )
    for run in 1...options.runs {
        do {
            let completion = try await engine.complete(
                prefix: options.prompt, parameters: parameters)
            records.append(RunRecord(style: style, run: run, completion: completion))
            let tps = completion.generationTokensPerSecond.map {
                String(format: "%.1f tok/s", $0)
            } ?? "—"
            print(
                "[\(run)] 첫청크 \(format(completion.timeToFirstChunk))"
                    + " · 전체 \(format(completion.totalTime))"
                    + " · \(tps)"
                    + (completion.stoppedAtSentenceBoundary ? " · 문장경계 stop" : "")
            )
            print("    제안: \"\(completion.text)\"")
        } catch {
            print("[\(run)] ❌ 생성 실패: \(error.localizedDescription)")
        }
    }
}

// MARK: - 판정 (PLAN §2: 첫 제안 <~300–500ms)

print("\n== 판정 ==")
if records.isEmpty {
    print("측정 결과 없음 — 생성이 모두 실패했습니다.")
    exit(1)
}
for style in options.styles {
    // 1회차는 워밍업이 섞이므로 마지막 run을 정상 상태로 본다.
    guard let steady = records.last(where: { $0.style == style }) else { continue }
    let first = steady.completion.timeToFirstChunk ?? steady.completion.totalTime
    let verdict: String
    switch first {
    case ..<0.3: verdict = "✅ 목표(300ms) 이내"
    case ..<0.5: verdict = "🟡 허용(500ms) 이내"
    default: verdict = "❌ 목표 초과 — 토큰 상한 축소 또는 더 작은 모델 검토"
    }
    print("\(style.rawValue): 첫청크 \(format(first)) → \(verdict)")
}
print("""

    다음 단계 (docs/m2-inference.md):
    · 두 스타일의 한국어 품질을 눈으로 비교해 PromptStyle 기본값 확정
    · 목표 초과 시 --max-tokens 축소(8) 또는 더 작은 모델로 재측정
    · 확정값은 Sources/MINTCore/Settings.swift 의 CompletionParameters 기본값에 반영
    """)

// MARK: - Agent 실모델 스모크 (PLAN §14 M10)

/// 세 개의 단일 도구 선택과 한 번의 실제 Agent loop를 재현한다. 네이티브
/// `.toolCall`과 폴백 호출을 구분해 양자화 모델의 형식 준수 위험을 드러낸다.
func runAgentSmoke(engine: CompletionEngine, options: BenchOptions) async -> Bool {
    let body = """
        # 1장 — 비 오는 병원
        서연은 병원 복도에서 민준을 만났다.
        “네가 편지를 가져갔어?” 서연이 물었다.
        “아니야. 난 어젯밤 내내 집에 있었어.” 민준이 말했다.

        # 2장 — 닫힌 서재
        서연은 책상 아래에서 젖은 편지를 발견했다.
        """
    let entry = JournalEntry(
        title: "젖은 편지", body: body, kind: .novel, genre: "미스터리",
        characters: [CharacterCard(name: "서연"), CharacterCard(name: "민준")])
    let source = AgentSourceSnapshot(
        activeEntry: entry, entries: [entry], folders: [], knowledge: nil,
        caretUTF16: (body as NSString).length)
    let registry = DefaultWritingTools.readOnlyMVP
    let parameters = CompletionParameters(
        modelID: options.modelID, promptStyle: .instruct,
        maxTokens: max(256, options.maxTokens),
        temperature: options.temperature)
    let system = AgentChatMessage(
        role: .system,
        content: "MINT 읽기 전용 집필 Agent다. 답을 추측하지 말고 요청에 가장 알맞은 도구 하나를 호출하라.")
    let cases: [(request: String, expected: String)] = [
        ("현재 문서의 제목과 종류를 확인해 줘.", "get_active_document"),
        ("본문에서 ‘병원’이라는 표현이 나온 위치를 찾아 줘.", "search_text"),
        ("현재 커서까지 장면 아웃라인을 확인해 줘.", "get_outline"),
    ]

    print("\n== Writing Agent 실모델 스모크 ==")
    print("도구: \(registry.names.count)개 · 단일 선택: \(cases.count)건")
    var correct = 0
    var native = 0
    for (index, test) in cases.enumerated() {
        let started = Date()
        do {
            let turn = try await engine.generateAgentTurn(
                messages: [system, AgentChatMessage(role: .user, content: test.request)],
                tools: registry.specs, parameters: parameters, onChunk: { _ in })
            let fallback = AgentToolCallParser.parse(turn.text).calls
            let calls = turn.toolCalls.isEmpty ? fallback : turn.toolCalls
            let origin = turn.toolCalls.isEmpty ? "폴백" : "네이티브"
            if !turn.toolCalls.isEmpty { native += 1 }
            let names = calls.map(\.name)
            let passed = names.first == test.expected
            if passed { correct += 1 }
            print(
                "[\(index + 1)] \(passed ? "✅" : "❌") \(test.expected) ← "
                    + "\(names.isEmpty ? "호출 없음" : names.joined(separator: ", "))"
                    + " · \(origin) · \(format(Date().timeIntervalSince(started)))")
        } catch {
            print("[\(index + 1)] ❌ 생성 실패: \(error.localizedDescription)")
        }
    }

    print("\n-- 전체 Agent loop --")
    let recorder = AgentSmokeRecorder()
    do {
        let runtime = AgentRuntime(generator: engine, registry: registry, maxSteps: 4)
        let started = Date()
        let result = try await runtime.run(
            request: "이 작품의 제목과 병원이 등장하는 대목을 확인해서 두 문장으로 알려 줘.",
            history: [], source: source, parameters: parameters
        ) { event in
            recorder.record(event)
        }
        let events = recorder.snapshot()
        print("도구 호출: \(events.toolNames.isEmpty ? "없음" : events.toolNames.joined(separator: " → "))")
        print("단계: \(result.steps) · 전체: \(format(Date().timeIntervalSince(started)))")
        print("답변: \(result.text)")
        let loopPassed = !events.toolNames.isEmpty && !result.text.isEmpty
        print("\n== Agent 판정 ==")
        print("단일 도구 정확도: \(correct)/\(cases.count) · 네이티브 호출: \(native)/\(cases.count)")
        print("전체 loop: \(loopPassed ? "✅ 통과" : "❌ 실패")")
        return correct == cases.count && loopPassed
    } catch {
        print("❌ 전체 Agent loop 실패: \(error.localizedDescription)")
        return false
    }
}

/// `@Sendable` 진행 콜백에서 벤치 결과만 안전하게 모은다.
final class AgentSmokeRecorder: @unchecked Sendable {
    struct Snapshot {
        let toolNames: [String]
    }

    private let lock = NSLock()
    private var toolNames: [String] = []

    func record(_ event: AgentRuntimeEvent) {
        guard case .toolStarted(let name, _) = event else { return }
        lock.lock()
        toolNames.append(name)
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(toolNames: toolNames)
    }
}

// MARK: - 리플레이 벤치 (PLAN §13)

/// 원고를 문장 경계 컷포인트에서 잘라, 컷 앞 컨텍스트로 제안을 만들고
/// 실제로 이어지는 원문(정답)과 비교한다. 컷마다 2회 실행:
/// 1회차는 콜드(캐시 무관), 2회차는 같은 프롬프트라 KV 프리필 재사용이
/// 일어나야 정상 — 웜 TTFC가 콜드보다 눈에 띄게 짧으면 PLAN §12가 작동하는 것.
func runReplay(path: String, engine: CompletionEngine, options: BenchOptions) async -> Bool {
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        print("❌ 리플레이 파일을 읽을 수 없음: \(path)")
        return false
    }
    let text = Array(raw)  // Character 배열 — 컷 계산 단순화 (벤치라 성능 무관)

    // 컷 후보: 문장 경계 문자 바로 뒤가 공백/줄바꿈인 위치 (문장이 막 끝난 순간).
    let boundaries: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "\n"]
    let minCut = max(200, options.truthChars)
    var candidates: [Int] = []
    for index in 0..<max(0, text.count - 1)
    where boundaries.contains(text[index])
        && (text[index + 1].isWhitespace || text[index + 1].isNewline)
    {
        let cut = index + 1
        if cut >= minCut, cut + options.truthChars <= text.count {
            candidates.append(cut)
        }
    }
    guard !candidates.isEmpty else {
        print("❌ 컷포인트 없음 — 문장 경계가 있는 더 긴 원고가 필요합니다.")
        return false
    }
    // 후보에서 균등 샘플.
    var cuts: [Int] = []
    if candidates.count <= options.cuts {
        cuts = candidates
    } else {
        for i in 0..<options.cuts {
            cuts.append(candidates[i * (candidates.count - 1) / max(1, options.cuts - 1)])
        }
    }

    // 소설 헤더(A) — 제목·장르가 주어졌을 때만 (없으면 Fast 모드 그대로).
    let document: DocumentContext? =
        (options.title.isEmpty && options.genre.isEmpty)
        ? nil
        : DocumentContext(
            title: options.title, kind: .novel,
            genre: options.genre.isEmpty ? nil : options.genre)
    // 리플레이 기본은 이어쓰기 — --style 로 하나만 고르면 그 스타일.
    let style: PromptStyle = options.styles.count == 1 ? options.styles[0] : .continuation
    var parameters = CompletionParameters()
    parameters.modelID = options.modelID
    parameters.promptStyle = style
    parameters.maxTokens = options.maxTokens
    parameters.temperature = options.temperature

    // B 블록 지식 (M6) — 인덱서와 같은 프롬프트·규격으로 사전 요약해 스냅샷을
    // 만든다. 출력을 그대로 찍는다 — 요약 품질 수동 검수가 M6 선결정 사항.
    var knowledge: KnowledgeSnapshot?
    if options.knowledge {
        guard document != nil else {
            print("❌ --knowledge 는 --title/--genre(소설 헤더)와 함께 써야 한다 — B는 소설 전용.")
            return false
        }
        let outline = DocumentOutline.parse(raw)
        let ns = raw as NSString
        print("\n== 지식 사전 구축 (씬 \(outline.scenes.count)개) ==")
        var byHash: [String: String] = [:]
        var ordered: [String] = []
        for (index, scene) in outline.scenes.enumerated() {
            let sceneText = String(
                ns.substring(
                    with: NSRange(
                        location: scene.utf16Range.lowerBound,
                        length: scene.utf16Range.count)
                ).prefix(BackgroundIndexer.maxSceneCharacters))
            guard
                let summary = await BackgroundIndexer.summarizeScene(
                    sceneText, engine: engine, parameters: parameters)
            else {
                print("[씬 \(index + 1)] ❌ 요약 실패")
                continue
            }
            byHash[scene.contentHash] = summary
            ordered.append(summary)
            print("[씬 \(index + 1)] \(scene.headingPath.joined(separator: " > ")): \(summary)")
        }
        var work: String?
        if ordered.count >= 2 {
            work = await BackgroundIndexer.rollup(
                ordered, level: .work, engine: engine, parameters: parameters)
            if let work { print("[작품] \(work)") }
        }
        knowledge = KnowledgeSnapshot(
            entryID: UUID(), outline: outline,
            summariesByHash: byHash, workSummary: work)

        // 인물 감지 깔때기 1단 점검 (M6, PLAN §7) — 결정적 후보를 그대로 찍는다.
        let candidates = CharacterDetector.detect(
            body: raw, outline: outline, known: [], rejected: [])
        print(
            "[인물 후보] "
                + (candidates.isEmpty
                    ? "없음"
                    : candidates.map {
                        "\($0.name)(언급\($0.mentions)·씬\($0.sceneCount)·유정\($0.animacyHits)·격\($0.caseRoleCount))"
                    }.joined(separator: " · ")))
    }

    print("\n== 리플레이 벤치 ==")
    print("원고: \(path) (\(text.count)자) · 컷 \(cuts.count)개 · 컨텍스트 \(options.contextChars)자")
    print(
        "스타일: \(style.rawValue) · 헤더: \(document == nil ? "없음" : "소설(제목/장르)")"
            + " · 지식(B): \(knowledge == nil ? "없음" : "요약 피라미드")\n")

    struct Row {
        let cut: Int
        let accepted: Int
        let sharedWord: Bool
        let suggestionLength: Int
        let coldTTFC: TimeInterval?
        let warmTTFC: TimeInterval?
        let promptTokens: Int
        let warmReused: Int
    }
    var rows: [Row] = []

    for (index, cut) in cuts.enumerated() {
        let contextStart = max(0, cut - options.contextChars)
        let context = String(text[contextStart..<cut])
        let truth = String(text[cut..<(cut + options.truthChars)])
        // B의 시점 차단 기준 — C 창이 시작하는 본문 위치 (utf16, 조립기 규격).
        let prefixStartUTF16 = String(text[0..<contextStart]).utf16.count
        let prompt = ContextAssembler.assemble(
            prefix: context, document: document,
            knowledge: knowledge, prefixStartUTF16: prefixStartUTF16,
            style: style)
        do {
            let cold = try await engine.complete(prompt: prompt, parameters: parameters)
            let warm = try await engine.complete(prompt: prompt, parameters: parameters)
            // 수락 프록시: 제안과 정답의 문자 단위 공통 접두 길이.
            var accepted = 0
            for (a, b) in zip(cold.text, truth) {
                guard a == b else { break }
                accepted += 1
            }
            // 보조 지표 — 정답과 어절(≥2자)을 공유하는가. 접두 일치가 0이어도
            // 방향이 맞는 제안(이름·소재 적중)을 잡는다 (docs/m5-replay-bench.md 후속).
            let sharedWord = sharesWord(cold.text, truth)
            rows.append(
                Row(
                    cut: cut, accepted: accepted, sharedWord: sharedWord,
                    suggestionLength: cold.text.count,
                    coldTTFC: cold.timeToFirstChunk, warmTTFC: warm.timeToFirstChunk,
                    promptTokens: cold.promptTokenCount,
                    warmReused: warm.reusedPromptTokens))
            print(
                "[\(index + 1)/\(cuts.count)] @\(cut)자"
                    + " · 일치 \(accepted)자/\(cold.text.count)자"
                    + (sharedWord ? " · 어절 적중" : "")
                    + " · 콜드 \(format(cold.timeToFirstChunk)) → 웜 \(format(warm.timeToFirstChunk))"
                    + " · 프롬프트 \(cold.promptTokenCount)tok (웜 재사용 \(warm.reusedPromptTokens)tok)")
            print("    제안: \"\(cold.text)\"")
            print("    정답: \"\(truth.prefix(cold.text.count + 10))\"")
        } catch {
            print("[\(index + 1)/\(cuts.count)] @\(cut)자 ❌ 생성 실패: \(error.localizedDescription)")
        }
    }

    guard !rows.isEmpty else {
        print("측정 결과 없음 — 생성이 모두 실패했습니다.")
        return false
    }

    func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    let meanAccepted = mean(rows.map { Double($0.accepted) })
    let hitRate = Double(rows.filter { $0.accepted >= 2 }.count) / Double(rows.count)
    let wordRate = Double(rows.filter(\.sharedWord).count) / Double(rows.count)
    let coldTTFC = mean(rows.compactMap { $0.coldTTFC })
    let warmTTFC = mean(rows.compactMap { $0.warmTTFC })
    let meanPromptTokens = mean(rows.map { Double($0.promptTokens) })
    let meanReused = mean(rows.map { Double($0.warmReused) })

    print("\n== 리플레이 요약 (커밋·PR에 남길 수치, CLAUDE.md §6) ==")
    print(String(format: "수락 프록시  : 평균 %.1f자 일치 · 적중률(≥2자) %.0f%%", meanAccepted, hitRate * 100))
    print(String(format: "어절 적중률  : %.0f%% (정답과 ≥2자 어절 공유)", wordRate * 100))
    print(String(format: "TTFC        : 콜드 %.2fs → 웜 %.2fs", coldTTFC, warmTTFC))
    print(String(format: "프롬프트     : 평균 %.0f tok · 웜 재사용 평균 %.0f tok", meanPromptTokens, meanReused))
    if meanReused < 1 {
        print("⚠️ 웜 재사용 0 — KV 캐시(PLAN §12)가 작동하지 않고 있다. kvCache 설정·trim 경로 확인.")
    }
    return true
}
