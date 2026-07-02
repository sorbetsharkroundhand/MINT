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
