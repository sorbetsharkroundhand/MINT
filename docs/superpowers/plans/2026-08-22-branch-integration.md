# Branch Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 분산 브랜치에서 검증 가치가 있는 세 수정만 현재 진행 중인 사용자 작업이 확정된 `main` 위에 독립적으로 재구현해 사건 분석, 대화 재앵커, MLX 생성 종료의 안정성을 높인다.

**Architecture:** 외부 브랜치는 merge/cherry-pick하지 않고 근거로만 읽는다. 현재 `main`을 정본으로 삼아 결정적 수정 두 개와 MLX 수명주기 수정 하나를 각각 테스트 우선으로 구현하고, 각 단계를 별도 커밋·검증 게이트로 격리한다.

**Tech Stack:** Swift 6, SwiftUI/AppKit, MLX Swift 0.31.4, mlx-swift-lm 3.31.3, XCTest, SwiftPM, MINTBench

**Spec:** `docs/superpowers/specs/2026-08-22-branch-integration-design.md`

## Global Constraints

- 원문과 현재 `main`이 정본이다. 외부 브랜치에 merge commit을 만들지 않는다.
- 현재 `6338676`의 KV 정책—협조 취소는 commit, 실제 오류는 abandon—을 유지한다.
- Agent, KeyScene, 자동 대화 기록, 서술 시점, 사이드카 스키마 변경은 이번 범위에서 제외한다.
- 주석과 사용자 문자열은 한국어로 작성하고 코드 주석은 `PLAN §N`을 앵커로 쓴다.
- 각 작업은 독립 커밋이며 `swift test`와 `swift build`를 통과하기 전 다음 작업으로 넘어가지 않는다.
- 실제 MLX 검증 전 `scripts/prepare-metallib.sh`가 현재 의존성용 metallib을 준비했는지 확인한다.
- 실행 시 현재 추적 소스의 미커밋 작업이 먼저 사용자 소유 커밋으로 확정돼야 한다. 그 뒤 `superpowers:using-git-worktrees`로 통합 작업을 격리한다.

---

### Task 1: 통합 작업 격리와 기준선 고정

**Files:**
- Read: `AGENTS.md`
- Read: `PLAN.md`
- Read: `Package.resolved`
- Read: `Sources/MINTCore/Editor/CompletionController.swift`
- Read: `Sources/MINTCore/SidebarView.swift`
- Read: `Sources/MINTCore/Storage/EntryStore.swift`
- Create through worktree workflow: isolated `fix/branch-integration-phase-1` worktree

**Interfaces:**
- Consumes: 현재 `main`의 커밋 `5147276` 이후 사용자 작업과 원격 추적 상태
- Produces: 사용자 미커밋 파일과 분리된 깨끗한 작업 트리, 기록된 기준선 테스트 결과

- [ ] **Step 1: 현재 작업 트리의 보호 대상 확인**

Run:

```bash
git status --short --branch
git diff -- PLAN.md Sources/MINTCore/Editor/CompletionController.swift Sources/MINTCore/SidebarView.swift Sources/MINTCore/Storage/EntryStore.swift
```

Expected: 사용자 변경 파일이 확인된다. 현재 관찰된 네 파일뿐 아니라 실행 시점에
새로 나타난 변경도 stash, reset, checkout하지 않는다. 계획 문서가 untracked인 것은
허용하지만 추적 소스가 수정 상태라면 다음 단계로 가지 않는다.

- [ ] **Step 2: 현재 사용자 작업의 기준 커밋 확정 대기**

사용자에게 현재 저장 비동기화·폴더 이름 생성 취소 작업을 먼저 검증하고 커밋하도록
요청한다. 이 계획의 실행자가 그 변경을 임의로 stage, commit, stash하지 않는다.

Run after the user confirms the work is committed:

```bash
git status --short --untracked-files=no
git log -1 --oneline
```

Expected: 첫 명령은 출력이 없고, 두 번째 명령은 사용자가 확정한 최신 기준 커밋을
보여준다.

- [ ] **Step 3: 실행용 격리 worktree 준비**

`superpowers:using-git-worktrees`를 적용해 현재 `main` HEAD에서
`fix/branch-integration-phase-1`을 만든다. 사용자 작업 트리가 깨끗하지 않다는 이유로
원래 트리의 파일을 이동하거나 삭제하지 않는다.

- [ ] **Step 4: 외부 브랜치가 읽기 전용 근거인지 확인**

Run:

```bash
git merge-base --is-ancestor mint-agentic claude/mint-scene-context-refactor-xtph5u
git cherry -v main mint-agentic
git cherry -v main claude/mint-scene-context-refactor-xtph5u
```

Expected: 첫 명령은 exit 0이고, `7057c92`는 `-`로 표시된다. 이후 단계에서
`git merge`와 `git cherry-pick`을 사용하지 않는다.

- [ ] **Step 5: 기준선 테스트 실행**

Run:

```bash
swift test
swift build
```

Expected: 둘 다 exit 0. 실패하면 브랜치 반입을 시작하지 않고 기준선 실패를 먼저
별도 진단한다.

---

### Task 2: 사건 추출과 그래프 입력의 중복 키 방어

**Files:**
- Modify: `Sources/MINTCore/Knowledge/EventLog.swift:126`
- Modify: `Sources/MINTCore/Knowledge/BackgroundIndexer.swift:620`
- Test: `Tests/MINTCoreTests/NarrativeIntelligenceTests.swift:53`
- Test: `Tests/MINTCoreTests/PlotThreadTests.swift:35`

**Interfaces:**
- Consumes: `StoryEvent.stableKey`, `EventParser.parse`, 사건 그래프와 플롯의 40개 입력 상한
- Produces: `BackgroundIndexer.uniqueEventsForAnalysis(_:limit:) -> [StoryEvent]`; 모델 출력과 그래프 입력에서 첫 `stableKey`만 유지

- [ ] **Step 1: 같은 씬의 중복 사건 출력을 고정하는 실패 테스트 작성**

`NarrativeIntelligenceTests`에 추가한다.

```swift
func test_사건파서는_같은씬의_동일사건줄을_한번만_보존한다() {
    let output = """
        문이 열린다 | 중요도: 4
        문이 열린다 | 중요도: 4
        서연이 들어온다 | 중요도: 3
        """

    let events = EventParser.parse(
        output, sceneHash: "scene-1", nameIndex: [:])

    XCTAssertEqual(events.map(\.summary), ["문이 열린다", "서연이 들어온다"])
}
```

- [ ] **Step 2: 사건 파서 테스트가 실패하는지 확인**

Run:

```bash
swift test --filter NarrativeIntelligenceTests/test_사건파서는_같은씬의_동일사건줄을_한번만_보존한다
```

Expected: 배열에 `문이 열린다`가 두 번 들어가 FAIL.

- [ ] **Step 3: EventParser에서 첫 stableKey만 보존**

`EventParser.parse`의 루프 바깥에 `seenKeys`를 두고, `StoryEvent`를 만든 뒤 처음 본
키만 append한다.

```swift
var events: [StoryEvent] = []
var seenKeys: Set<String> = []
// 기존 파싱 루프
let event = StoryEvent(
    sceneHash: sceneHash, participants: participants + holders,
    summary: summary, importance: importance, deltas: deltas, quote: quote)
guard seenKeys.insert(event.stableKey).inserted else { continue }
events.append(event)
```

- [ ] **Step 4: 사건 파서 테스트 통과 확인**

Run:

```bash
swift test --filter NarrativeIntelligenceTests/test_사건파서는_같은씬의_동일사건줄을_한번만_보존한다
```

Expected: PASS.

- [ ] **Step 5: 그래프 입력 중복을 고정하는 실패 테스트 작성**

`PlotThreadTests`에 추가한다.

```swift
func test_그래프분석입력은_동일stableKey의_첫사건만_보존한다() {
    let first = StoryEvent(
        sceneHash: "scene-1", participants: [],
        summary: "문이 열린다", importance: 3)
    let repeated = StoryEvent(
        sceneHash: "scene-2", participants: [],
        summary: "문이 열린다", importance: 5)
    let next = StoryEvent(
        sceneHash: "scene-3", participants: [],
        summary: "서연이 들어온다", importance: 4)

    let result = BackgroundIndexer.uniqueEventsForAnalysis(
        [first, repeated, next])

    XCTAssertEqual(result.map(\.sceneHash), ["scene-1", "scene-3"])
    XCTAssertEqual(Set(result.map(\.stableKey)).count, result.count)
}
```

- [ ] **Step 6: 그래프 입력 테스트가 컴파일 실패하는지 확인**

Run:

```bash
swift test --filter PlotThreadTests/test_그래프분석입력은_동일stableKey의_첫사건만_보존한다
```

Expected: `BackgroundIndexer`에 `uniqueEventsForAnalysis`가 없어 FAIL.

- [ ] **Step 7: 분석 입력 정규화 함수를 구현**

`BackgroundIndexer`의 사건 그래프 분석 도우미 근처에 추가한다.

```swift
nonisolated static func uniqueEventsForAnalysis(
    _ events: [StoryEvent], limit: Int = 40
) -> [StoryEvent] {
    var seen: Set<String> = []
    var result: [StoryEvent] = []
    result.reserveCapacity(min(limit, events.count))
    for event in events where seen.insert(event.stableKey).inserted {
        result.append(event)
        if result.count == limit { break }
    }
    return result
}
```

`analyzeEventGraph`와 `analyzePlotThreads`의 `Array(events.prefix(40))`를 이 함수로
교체한다. 깊은 패스의 `memoHash`도 동일한 정규화 목록으로 계산해 실제 모델 입력과
무효화 키가 일치하게 한다.

- [ ] **Step 8: 사건 관련 집중 테스트 실행**

Run:

```bash
swift test --filter NarrativeIntelligenceTests
swift test --filter PlotThreadTests
swift test --filter NarrativeGraphTests
```

Expected: 모두 PASS, `Dictionary(uniqueKeysWithValues:)`에 중복 사건 키가 전달되지 않는다.

- [ ] **Step 9: 전체 검증과 커밋**

Run:

```bash
swift test
swift build
git add Sources/MINTCore/Knowledge/EventLog.swift Sources/MINTCore/Knowledge/BackgroundIndexer.swift Tests/MINTCoreTests/NarrativeIntelligenceTests.swift Tests/MINTCoreTests/PlotThreadTests.swift
git commit -m "fix: 사건 중복 키의 그래프 분석 충돌 방어"
```

Expected: 테스트와 빌드 exit 0, 커밋에는 위 네 파일만 포함된다.

---

### Task 3: 반복 대화에 안전한 기록 재앵커

**Files:**
- Modify: `Sources/MINTCore/Knowledge/ConversationCapture.swift:210`
- Test: `Tests/MINTCoreTests/NarrativeGraphTests.swift:520`

**Interfaces:**
- Consumes: `RecordedConversation.contentHash`, `utf16Start`, `utf16End`, `firstLine`, `lastLine`
- Produces: 기존 위치와 가장 가까운 완전한 대화 블록 또는 `nil`; 기록 승인 UX는 변경하지 않음

- [ ] **Step 1: 현재 범위가 유효하면 그대로 유지하는 테스트 작성**

```swift
func test_기록_재앵커_현재범위해시가_맞으면_원본을유지한다() {
    let body = "\"어디 가?\"\n\"금방 다녀올게.\""
    let ns = body as NSString
    let record = RecordedConversation(
        participants: [], utf16Start: 0, utf16End: ns.length,
        firstLine: "어디 가?", lastLine: "금방 다녀올게.",
        contentHash: DocumentOutline.stableHash(body))

    XCTAssertEqual(ConversationDetector.reanchor(record, in: ns), record)
}
```

- [ ] **Step 2: 반복 대사에서 가까운 블록을 선택하는 실패 테스트 작성**

```swift
func test_기록_재앵커_반복대사는_기존위치와_가까운블록을_선택한다() {
    let body = "\"네.\"\n\"먼저 갈게.\"\n\n긴 서술.\n\n\"네.\"\n\"나중에 갈게.\""
    let ns = body as NSString
    let expectedStart = ns.range(of: "\"네.\"", options: .backwards).location
    let record = RecordedConversation(
        participants: [], utf16Start: expectedStart + 2, utf16End: ns.length,
        firstLine: "네.", lastLine: "나중에 갈게.", contentHash: "낡은 해시")

    let anchored = ConversationDetector.reanchor(record, in: ns)

    XCTAssertEqual(anchored?.utf16Start, expectedStart)
    XCTAssertTrue(ns.substring(to: anchored!.utf16End).hasSuffix("\"나중에 갈게.\""))
}
```

- [ ] **Step 3: 마지막 대사를 찾지 못하면 nil인 실패 테스트 작성**

```swift
func test_기록_재앵커_마지막대사를_찾지못하면_nil이다() {
    let body = "서두\n\"어디 가?\"\n대화가 잘렸다."
    let record = RecordedConversation(
        participants: [], utf16Start: 0, utf16End: 10,
        firstLine: "어디 가?", lastLine: "금방 다녀올게.", contentHash: "낡은 해시")

    XCTAssertNil(ConversationDetector.reanchor(record, in: body as NSString))
}
```

- [ ] **Step 4: 새 재앵커 테스트의 기준선 실패 확인**

Run:

```bash
swift test --filter NarrativeGraphTests/test_기록_재앵커
```

Expected: 반복 대사는 첫 번째 블록에 연결되거나, 마지막 대사가 없는데 임시 범위를
반환해 적어도 한 테스트가 FAIL.

- [ ] **Step 5: 해시 검증과 거리 기반 후보 선택 구현**

`ConversationDetector.reanchor`를 다음 사다리로 교체한다.

```swift
guard !record.firstLine.isEmpty, !record.lastLine.isEmpty else { return nil }
if record.utf16Start >= 0,
    record.utf16End > record.utf16Start,
    record.utf16End <= body.length
{
    let current = body.substring(with: NSRange(
        location: record.utf16Start,
        length: record.utf16End - record.utf16Start))
    if DocumentOutline.stableHash(current) == record.contentHash { return record }
}
```

이어 첫 줄의 모든 일치를 모아 `abs(location - record.utf16Start)`가 가장 작은 후보를
선택한다. 마지막 줄도 첫 줄 이후의 모든 일치를 모아 예상 종료 위치와 가장 가까운
후보를 선택한다. 둘 중 하나라도 없으면 `nil`을 반환한다. 선택 후에는 기존처럼
`lineRange(for:)`로 문단 경계를 맞춘다.

- [ ] **Step 6: 대화 기록 회귀 테스트 실행**

Run:

```bash
swift test --filter NarrativeGraphTests/test_기록_재앵커
swift test --filter DialogueAttributionTests
```

Expected: 모두 PASS. `CompletionController`와 자동 기록 타이머에는 diff가 없다.

- [ ] **Step 7: 전체 검증과 커밋**

Run:

```bash
swift test
swift build
git add Sources/MINTCore/Knowledge/ConversationCapture.swift Tests/MINTCoreTests/NarrativeGraphTests.swift
git commit -m "fix: 반복 대화 기록을 가까운 원문에 재앵커"
```

Expected: 커밋에는 두 파일만 포함되고 사용자 승인 기반 기록 UX가 유지된다.

---

### Task 4: MLX 내부 생성 Task의 취소·종료 대기

**Files:**
- Modify: `Sources/MINTCore/Inference/CompletionEngine.swift:120`
- Create: `Tests/MINTCoreTests/GenerationTaskSynchronizerTests.swift`
- Modify: `Sources/MINTBench/main.swift:18`
- Modify after successful stress run: `PLAN.md:683`

**Interfaces:**
- Consumes: `MLXLMCommon.TokenIterator`, `MLXLMCommon.generateTask`, `ModelContainer.perform`, 현재 `PromptCacheBox` begin/commit/abandon 계약
- Produces: `GenerationTaskSynchronizer.cancelAndWait() async`; 세 생성 경로가 내부 GPU Task 종료 후 컨테이너 잠금을 반환

- [ ] **Step 1: 모델 없는 종료 대기 테스트 작성**

새 테스트 파일에 작성한다.

```swift
@testable import MINTCore
import XCTest

final class GenerationTaskSynchronizerTests: XCTestCase {
    private actor Probe {
        var finished = false
        func markFinished() { finished = true }
    }

    func test_cancelAndWait는_내부Task종료까지_기다린다() async {
        let probe = Probe()
        let task = Task<Void, Never> {
            while !Task.isCancelled { await Task.yield() }
            await probe.markFinished()
        }

        await GenerationTaskSynchronizer(task: task).cancelAndWait()

        let didFinish = await probe.finished
        XCTAssertTrue(didFinish)
    }
}
```

- [ ] **Step 2: 종료 대기 테스트의 컴파일 실패 확인**

Run:

```bash
swift test --filter GenerationTaskSynchronizerTests
```

Expected: `GenerationTaskSynchronizer`가 없어 컴파일 FAIL.

- [ ] **Step 3: 모델 독립 종료 동기화 타입 구현**

`CompletionEngine.swift`의 생성 섹션 앞에 내부 타입으로 추가한다.

```swift
struct GenerationTaskSynchronizer: Sendable {
    let task: Task<Void, Never>

    func cancelAndWait() async {
        task.cancel()
        await task.value
    }
}
```

Run:

```bash
swift test --filter GenerationTaskSynchronizerTests
```

Expected: PASS.

- [ ] **Step 4: MLX stream과 내부 Task를 함께 만드는 헬퍼 구현**

`CompletionEngine` 안에 추가한다.

```swift
private static func generationTask(
    input: LMInput,
    cache: [KVCache]? = nil,
    parameters: GenerateParameters,
    context: ModelContext
) throws -> (AsyncStream<Generation>, GenerationTaskSynchronizer) {
    let iterator = try TokenIterator(
        input: input, model: context.model, cache: cache,
        parameters: parameters)
    let (stream, task) = MLXLMCommon.generateTask(
        promptTokenCount: input.text.tokens.size,
        modelConfiguration: context.configuration,
        tokenizer: context.tokenizer,
        iterator: iterator)
    return (stream, GenerationTaskSynchronizer(task: task))
}
```

현재 의존성은 원본 `e50b649`과 동일한 mlx-swift 0.31.4,
mlx-swift-lm 3.31.3이므로 이 API 형태를 기준으로 한다.

- [ ] **Step 5: 폴더 이름과 백그라운드 one-shot 경로 전환**

두 경로의 `MLXLMCommon.generate`를 `Self.generationTask`로 교체하고, `for await`
루프 직후 취소 검사보다 먼저 다음을 호출한다.

```swift
await synchronizer.cancelAndWait()
try Task.checkCancellation()
```

조기 줄바꿈과 빈 줄 정지가 발생해도 반드시 같은 순서로 종료한다.

- [ ] **Step 6: 자동완성 경로와 KV 정리 순서 전환**

`runGeneration`에서 스트림을 헬퍼로 만들고 루프 직후 다음 순서를 적용한다.

```swift
await synchronizer.cancelAndWait()
if cacheInUse {
    promptCache.commit(tokens: promptTokens)
    cacheInUse = false
}
try Task.checkCancellation()
```

catch 블록의 `CancellationError -> commit`, 실제 오류 `-> abandon` 분기는 그대로
둔다. `cacheInUse = false`는 이미 안전하게 commit한 캐시가 부모 취소로 다시
abandon되는 것을 막는다.

- [ ] **Step 7: 모델 교체 전 기존 컨테이너 종료 대기 추가**

`loadedContainer`에서 다른 모델을 로드하기 전, 기존 컨테이너를 nil로 만들기 전에
다음을 수행한다.

```swift
loadTask?.cancel()
if let container {
    await container.perform { _ in () }
}
container = nil
loadedModelID = nil
promptCache.invalidate()
```

같은 모델을 재사용하거나 같은 `loadTask`를 공유하는 빠른 경로는 변경하지 않는다.

- [ ] **Step 8: 단위 테스트와 컴파일 검증**

Run:

```bash
swift test --filter GenerationTaskSynchronizerTests
swift test --filter PromptCacheMathTests
swift build
```

Expected: 모두 exit 0. 컴파일 오류가 나면 API를 추측해 우회하지 말고 현재
`.build/checkouts/mlx-swift-lm`의 `generateTask` 선언과 원본 `e50b649`을 대조한다.

- [ ] **Step 9: MINTBench 취소 스트레스 모드 추가**

`BenchOptions`에 `cancellationStressRuns: Int?`를 추가하고
`--cancellation-stress 20`을 파싱한다. 모델을 한 번 워밍한 뒤 각 반복에서 다음
순서를 실행한다.

```swift
guard let raw = try? String(
    contentsOfFile: "Fixtures/replay-novel-ko-v1.txt", encoding: .utf8),
    !raw.isEmpty
else {
    print("❌ 취소 스트레스 픽스처를 읽지 못했습니다.")
    exit(1)
}
let stressPrompt = String(raw.prefix(1_200))
_ = try await engine.complete(prefix: stressPrompt, parameters: parameters)

let generation = Task {
    try await engine.complete(prefix: stressPrompt, parameters: parameters)
}
try? await Task.sleep(for: .milliseconds(100))
generation.cancel()
_ = try? await generation.value
let followup = try await engine.complete(
    prefix: stressPrompt + " 그리고", parameters: parameters)
guard !followup.text.isEmpty else { return false }
```

각 반복은 `취소 i/20 → 후속 생성 성공`을 출력하고, 실패하면 exit 1을 반환한다.
프롬프트는 `Fixtures/replay-novel-ko-v1.txt`의 앞 1,200자를 사용하며 파일을 읽지
못하면 명시적으로 실패한다.

- [ ] **Step 10: 실제 Metal 스트레스 검증**

Run:

```bash
scripts/prepare-metallib.sh
swift build -c release
.build/release/MINTBench --model mlx-community/Qwen2.5-3B-Instruct-4bit --cancellation-stress 20
for run in {1..10}; do
  echo "process $run/10"
  .build/release/MINTBench --model mlx-community/Qwen2.5-3B-Instruct-4bit --cancellation-stress 20 || exit 1
done
```

Expected: 첫 실행과 별도 프로세스 10개가 각각 20/20 후속 생성 성공, exit 0.
한 번이라도 EXIT=11 또는 빈 후속 생성이
나오면 이 Task를 커밋하지 않고 실패 로그를 보존해 `superpowers:systematic-debugging`
으로 전환한다.

- [ ] **Step 11: 리플레이 캐시 회귀 확인**

Run:

```bash
.build/release/MINTBench --model mlx-community/Qwen2.5-3B-Instruct-4bit --replay Fixtures/replay-novel-ko-v1.txt --context 1200 --max-tokens 12 --runs 1
```

Expected: 프로세스 exit 0이고 웜 실행에서 프롬프트 재사용이 0이 아니다. TTFC나
재사용이 기준선에서 악화되면 PLAN을 갱신하거나 커밋하지 않고 원인을 조사한다.

- [ ] **Step 12: PLAN에 검증 결과 기록**

20회 취소 스트레스와 10개 프로세스가 모두 성공한 경우에만 `PLAN §16`의 간헐
세그폴트 항목을 해소로 바꾸고 다음 사실을 기록한다.

```markdown
- ~~MINTBench 릴리즈 CLI 간헐 세그폴트~~ **해소(2026-08-22)**:
  MLX 내부 생성 Task를 모든 조기 종료 경로에서 cancel 후 await하고, 모델 교체도
  기존 container.perform 종료 뒤 시작한다. 취소→후속 생성 20/20과 독립 프로세스
  10/10, 리플레이 웜 KV 재사용을 확인했다.
```

- [ ] **Step 13: 전체 검증과 커밋**

Run:

```bash
swift test
swift build
git add Sources/MINTCore/Inference/CompletionEngine.swift Sources/MINTBench/main.swift Tests/MINTCoreTests/GenerationTaskSynchronizerTests.swift PLAN.md
git commit -m "fix: MLX 생성 종료를 기다려 GPU 작업 겹침 방지"
```

Expected: 커밋에는 네 파일만 포함되고 `EntryStore.swift`에는 diff가 없다.

---

### Task 5: 단계별 통합 리뷰와 main 반입

**Files:**
- Review: 세 구현 커밋의 전체 diff
- Verify: `PLAN.md`, `AGENTS.md`, `README.md`
- No new source file required

**Interfaces:**
- Consumes: Task 2~4의 독립 커밋 세 개와 검증 로그
- Produces: main에 순서대로 반입 가능한 승인/거절 판정

- [ ] **Step 1: 범위 누출 검사**

Run:

```bash
git diff --name-status main...HEAD
git diff main...HEAD -- Sources/MINTCore/Agent Sources/MINTCore/KeySceneView.swift Sources/MINTCore/Knowledge/KeyScene.swift Sources/MINTCore/Editor/CompletionController.swift Sources/MINTCore/Storage/EntryStore.swift
```

Expected: 두 번째 명령은 출력이 없다. Agent, KeyScene, 자동 대화 기록, EntryStore가
포함되면 해당 커밋을 거절하고 범위를 다시 분리한다.

- [ ] **Step 2: 커밋 독립성 확인**

Run:

```bash
git log --reverse --oneline main..HEAD
git show --stat --oneline HEAD~2
git show --stat --oneline HEAD~1
git show --stat --oneline HEAD
```

Expected: 사건 중복, 대화 재앵커, MLX 동기화가 각각 별도 커밋이고 어느 커밋도
외부 브랜치 merge commit이 아니다.

- [ ] **Step 3: 최종 자동 검증**

Run:

```bash
swift test
swift build
```

Expected: 모두 exit 0.

- [ ] **Step 4: 앱 E2E 검증**

`swift run MINT`로 실행하고 다음을 확인한다.

1. 한글 조합 중 고스트가 나타나지 않는다.
2. 입력 정지 후 약 500ms에 제안이 등장한다.
3. Tab/→ 수락과 Esc 거절이 동작한다.
4. 빠르게 입력해 진행 중 생성을 여러 번 취소해도 앱이 종료되지 않는다.
5. 다른 모델로 전환한 직후 생성해도 Metal 오류가 없다.
6. 앱 재실행 뒤 저널과 기록된 대화가 보존된다.

Expected: 여섯 항목 모두 통과. 하나라도 실패하면 main 반입을 멈추고 실패한 독립
커밋만 되돌려 원인을 좁힌다.

- [ ] **Step 5: 반입 준비 완료 판정**

`superpowers:requesting-code-review`로 세 커밋의 요구사항 충족과 범위 누출을 검토하고,
통과 후 `superpowers:finishing-a-development-branch`로 main 반입 방식을 결정한다.
사용자가 명시적으로 요청하기 전에는 push나 원격 PR 생성을 하지 않는다.

---

## 후속 격리 트랙

다음 항목은 이 계획에서 구현하지 않는다. 현재 세 수정이 main에 들어간 뒤 각각
별도 brainstorming → 설계 → MINTBench 계획을 거쳐야 한다.

1. **KeyScene:** 작가 수동 장면만 먼저 평가하되, 예측 A/B에서 토큰당 품질 상승과
   미래 누출 0건을 입증하기 전 저장/UI 코드를 반입하지 않는다.
2. **전역 서술 시점:** 호명 대상과 화자를 분리하고, 합성 10문장이 아니라 서로 다른
   실제 작품 코퍼스로 1/3인칭·혼합 시점 정밀도를 측정한다.
3. **범용 대사 전수 스캐너:** 동백꽃 고유 어휘 규칙을 제거하고 큰따옴표 누락률과
   잘못된 화자 귀속률을 별도로 측정한다.
4. **Writing Agent:** 현재 제품 범위와 모델 지연 예산을 별도 제품 결정으로 승인받기
   전에는 반입하지 않는다.
5. **포맷/린트:** 기능 반입과 무관한 독립 유지보수 작업으로만 검토한다.
