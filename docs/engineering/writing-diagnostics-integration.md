# Production Korean proofreading integration

The app owns one `WritingDiagnosticsRuntime` shared by the project editor, Living Margin, project controls, foreground-completion policy and the existing pressure monitor. It uses the bundled pinned offline NLP backend independently of shipping-LLM setup or completion authorization. This does not claim general Korean grammar coverage, smaller-device support, Store distribution or actual-app/IME/VoiceOver/paint acceptance.

## Native authority and publication

The project session remains the only mutable manuscript/profile owner. The editor bridge delivers the current document snapshot before a proved native commit. Initial loads, same-editor external reloads and unchanged metadata use the capture's exact source/native map, without guessing offsets or comparing the whole body on normal typing. A consumer attached after the editor can replay that existing proof. Repeated connection to the same current identity/revision is idempotent. Replacing or detaching the native editor suspends authority; an explicit load resets source only when required by ownership.

Publication is coalesced outside the native binding callback and checks current ownership/stamps before preparing values. Opening a surface reads prepared values and does not start analysis, load a model, navigate, or move focus. Correctness marks use the separate native layer; prepared margin updates retain other producers and session dismissal IDs. Independent occurrences are not merged solely because their messages and spelling are identical. Related style occurrences carry bounded original source anchors, including exact decomposed Hangul units; their hints rebase through unrelated edits and their retained quotes count toward the existing finding budgets.

## Explicit choices

Each generated action ID binds the full current stamp and exact candidate through a generated lookup. No replacement text is parsed from IDs. Native replacement revalidates current source/map/format/undo ownership through Task 11. Previous action IDs cannot apply a changed candidate or mutate current preferences.

Dismissal is session presentation state. Intentional occurrences, disabled rules, learned words, language and repetition/dialogue sensitivity use the versioned project writing-style record, separately from User Canon. Changes capture the displayed runtime identity and pass through `WritingStyleRepository` and `ProjectSession`. Settings use the controller's already-decoded profile. Unreadable/future bytes remain preserved and controls stay read-only; unsupported stored language tags remain representable. Word lookup is NFC-normalized while manuscript/evidence remain unchanged.

An intentional action after typing explicitly captures the current source revision under the current finding stamp. The controller may remember that owned proof for suppression before the metadata-only profile update. Ordinary edits still clear it; they never hash the full source. Existing decisions are never re-anchored by searching for the first duplicate quote.

## Supported findings and status

Current correctness alternatives remain the independently verified `됬다` past-tense and morphology-confirmed bound-noun spacing signatures from Task 6. They are not a whole-paragraph native join replacement. Morphological word/particle/ending/connector repetition and the bounded sentence/causality/rhythm sessions from Tasks 7–8 feed original evidence and plain Korean explanations to the margin. Nonactionable info patterns remain report output. Unsupported, pending, partial, paused and unavailable states are explicit; no-model editing, save, search and EPUB export remain usable.

Project controls appear in Writing settings, alongside the existing typography/author controls. The margin exposes explicit current alternatives and project choices, with category/evidence/action accessibility text and compact details/retry. Other producer custom actions remain hidden until their executor is connected. No panel opens as a side effect of a result, and editor Ghost key handling is unchanged.

## Verification boundaries

Headless synthetic-project integration uses the real pinned provider in Fiction and General modes: native edit, debounce, finding, explicit correction, one Undo, flush and reopen. Additional regressions cover surface-opening admission/focus, distinct session/durable choices, stale action IDs, related original anchors and budgets, late attachment, idempotent reconnect, retained-map transition replay, same-editor external load and unavailable backend/profile write/search/export. Temporary native windows are never displayed; no MINT product launch or UI smoke is part of this pass.

The frozen Task 12 backend gate passed with unchanged resource/worker inputs: cold 1.070 s, peak resident 868,810,752 bytes, warm 1,024-unit analysis 15.671 ms and admitted-call cancellation drain 14.646 ms. All frozen limits passed; outputs are retained at `build/korean-backend-validation/task-12-frozen-verify-20261016`.

Clean developer-bundle/unsigned-archive validation uses a fresh ignored task output directory. Task-scoped runner copies change only cwd/output/validation paths from the standard scripts so retained app/archive artifacts are not replaced. Runner diffs, hashes and source/artifact/support receipts remain in the ignored execution ledger. Final packaging evidence is recorded separately after validation. This remains developer packaging evidence, not Store or final native acceptance.

The implementation gate passed 1,142 tests (2 existing skips), build, MINTBench and a warning-free Release MINTCore compile. The reviewed explicit-intentional regression is RED→GREEN and preserves source/projection-reset counts. Nine support privacy tests and 17 notice tests passed. Package/archive validation and required PR/main CI are recorded separately from this logic evidence.
