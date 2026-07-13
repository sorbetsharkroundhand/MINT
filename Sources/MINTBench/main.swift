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

print("== MINT M2 추론 선검증 ==")
print("모델     : \(options.modelID)")
print("스타일   : \(options.styles.map(\.rawValue).joined(separator: ", "))")
print("토큰 상한: \(options.maxTokens) · 온도: \(options.temperature) · 반복: \(options.runs)")
print("프롬프트 : \(options.prompt)")
print("")

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

    print("\n== 리플레이 벤치 ==")
    print("원고: \(path) (\(text.count)자) · 컷 \(cuts.count)개 · 컨텍스트 \(options.contextChars)자")
    print("스타일: \(style.rawValue) · 헤더: \(document == nil ? "없음" : "소설(제목/장르)")\n")

    struct Row {
        let cut: Int
        let accepted: Int
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
        let prompt = ContextAssembler.assemble(
            prefix: context, document: document, style: style)
        do {
            let cold = try await engine.complete(prompt: prompt, parameters: parameters)
            let warm = try await engine.complete(prompt: prompt, parameters: parameters)
            // 수락 프록시: 제안과 정답의 문자 단위 공통 접두 길이.
            var accepted = 0
            for (a, b) in zip(cold.text, truth) {
                guard a == b else { break }
                accepted += 1
            }
            rows.append(
                Row(
                    cut: cut, accepted: accepted,
                    suggestionLength: cold.text.count,
                    coldTTFC: cold.timeToFirstChunk, warmTTFC: warm.timeToFirstChunk,
                    promptTokens: cold.promptTokenCount,
                    warmReused: warm.reusedPromptTokens))
            print(
                "[\(index + 1)/\(cuts.count)] @\(cut)자"
                    + " · 일치 \(accepted)자/\(cold.text.count)자"
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
    let coldTTFC = mean(rows.compactMap { $0.coldTTFC })
    let warmTTFC = mean(rows.compactMap { $0.warmTTFC })
    let meanPromptTokens = mean(rows.map { Double($0.promptTokens) })
    let meanReused = mean(rows.map { Double($0.warmReused) })

    print("\n== 리플레이 요약 (커밋·PR에 남길 수치, CLAUDE.md §6) ==")
    print(String(format: "수락 프록시  : 평균 %.1f자 일치 · 적중률(≥2자) %.0f%%", meanAccepted, hitRate * 100))
    print(String(format: "TTFC        : 콜드 %.2fs → 웜 %.2fs", coldTTFC, warmTTFC))
    print(String(format: "프롬프트     : 평균 %.0f tok · 웜 재사용 평균 %.0f tok", meanPromptTokens, meanReused))
    if meanReused < 1 {
        print("⚠️ 웜 재사용 0 — KV 캐시(PLAN §12)가 작동하지 않고 있다. kvCache 설정·trim 경로 확인.")
    }
    return true
}
