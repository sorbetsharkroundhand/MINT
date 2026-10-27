# Editorial redesign integration verification — 2026-10-28

## Scope

Integrate the editorial workspace branch with its document navigator, binder tabs,
project-owned writer tools, expanded Markdown/math editing, native MathML EPUB
export, and the three pinned local completion candidates. The owner's request
explicitly includes fixing build/export regressions and merging main after checks.
This is integration evidence, not Store distribution or shipping-model approval.

## Build and editor repairs

- Reproduced a normal `swift build` failure: the Hugging Face macro target imported
  a Swift 6.4 prebuilt module with Swift 6.3.3. Replaced the macro-only dependency
  with a direct local `AutoTokenizer` bridge. Normal builds require no prebuilt
  override and tokenizer loading remains local to the verified installation.
- Reproduced selected-text loss on `*`, a source-mode load that reset its own flag,
  and unstable nested bold/strikethrough serialization. Existing failing round-trip
  tests now pass with the expected manuscript intact.
- Traced native undo/layout exceptions with LLDB. TextKit emitted selection changes
  while applying a storage delta; inline math collapse then recursively changed
  the storage length. Defer selection processing until layout invalidation returns,
  and measure caret overlays after the native edit completes. The regression also
  checks the next run-loop/layout update, not merely the synchronous edit.
- Added failing EPUB regressions for XML attribute escaping, literal code spans,
  formatted-looking URL destinations, MathML structure, and the OPF mathml property.
  Protect code/URLs before prose formatting and escape link attributes.
- Migrated obsolete rail-based UI checks to the visible pouch menu, native search,
  and current tile close controls. Retained IME, focus, selection, undo, durable
  settings, passive-analysis, and project ownership assertions.
- Selection toolbar has a borderless native panel with no window shadow; the
  toolbar surface no longer draws an outer stroke or shadow.

## Local evidence

Logs are under `build/redesign-merge-verification/` (ignored build artifacts).

| Check | Result |
| --- | --- |
| Default `swift build` | Passed (`build-direct-tokenizer.log`) |
| Full `swift test`, isolated `CFFIXED_USER_HOME` | 1,469 tests, 4 opt-in skips, 0 failures (`full-suite.log`) |
| Final EPUB/math/editor/projection/undo subset | 101 tests, 1 opt-in skip, 0 failures (`final-focused.log`) |
| `swift build --product MINTBench` | Passed (`bench-build.log`) |
| Benchmark CLI preflight smoke | Passed; no model download (`bench-cli.log`) |
| Support diagnostics | 9 tests passed |
| Korean backend validation/preparation | 14 + 3 tests passed |
| Dependency notices | 17 tests passed |
| `git diff --check` | Passed |

The final subset includes the restored backslash punctuation boundary in the
incremental diagnostic projection. All test manuscripts and real-model runs use
isolated storage. The earlier failures recorded in the model experiment report
were resolved in this integration pass. Required PR CI and release-bundle/app
checks are also required before the merge; their final results belong to the PR.

## Review

Reviewed inline as requested by the active #99 integration directive: model
installation/ownership and cache failure handling; project navigation and legacy
copy preparation; storage and editor identity across tool transitions; EPUB XML
and MathML output; native selection/undo ordering; and the native test assertions.
No CI job, required check, model-memory approval, or data protection was relaxed.

## Real-model editor verification after the tokenizer bridge change

Each candidate loaded its already installed pinned weights into the native
redesigned editor, produced visible Korean Ghost text, accepted it with native
Tab, persisted the accepted body, and restored the original with undo.

| Candidate | Prompt style | Observed continuation |
| --- | --- | --- |
| Qwen3.5 9B | continuation | ` 아무도 없었다.` |
| Ministral 3 14B | continuation | ` 한 남자가 서 있었다.` |
| Gemma 4 26B-A4B | instruct | `어둠이 짙게 깔려 있었다.` |

Evidence and captures are in `build/writing-model-benchmarks-2026-10-26/`:
`merge-qwen-native-ghost`, `merge-ministral-awake-native-ghost`, and
`merge-gemma-native-ghost` (`.log` and `.png`). The first Ministral attempt timed
out waiting for Ghost across a 539-second wall-clock interval and exited with a
signal; the subsequent run under a temporary awake assertion passed in 7.56
seconds. The failed attempt remains in `merge-ministral-native-ghost.log` and is
not counted as successful evidence. These are functional checks, not new latency
benchmarks. The original comparative benchmark results remain in the model report.
