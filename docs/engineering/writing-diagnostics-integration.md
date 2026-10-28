# Production Korean proofreading integration

The app owns one `WritingDiagnosticsRuntime` shared by the project editor, Living Margin, project controls, foreground-completion policy and the existing pressure monitor. It uses the bundled pinned offline NLP backend independently of shipping-LLM setup or completion authorization. This does not claim general Korean grammar coverage, smaller-device support, Store distribution or actual-app/IME/VoiceOver/paint acceptance.

## Native authority and publication

The project session remains the only mutable manuscript/profile owner. The editor bridge delivers the current document snapshot before a proved native commit. Initial loads, same-editor external reloads and unchanged metadata use the capture's exact source/native map, without guessing offsets or comparing the whole body on normal typing. A consumer attached after the editor can replay that existing proof. Repeated connection to the same current identity/revision is idempotent. Replacing or detaching the native editor suspends authority; an explicit load resets source only when required by ownership. Initial/reloaded authority also requires the actual native binding’s stable project/document key and exact original UTF-16 bytes to match the session snapshot. Identical text in another document is insufficient. A rejected load clears mapped/queued capture authority; an ignored stale binding cannot restore it. The full comparison occurs only at the load seam, outside ordinary typing.

Publication is coalesced outside the native binding callback and checks current ownership/stamps before preparing values. Opening a surface reads prepared values and does not start analysis, load a model, navigate, or move focus. Correctness marks use the separate native layer; prepared margin updates retain other producers and session dismissal IDs. Independent occurrences are not merged solely because their messages and spelling are identical. Related style occurrences carry bounded original source anchors, including exact decomposed Hangul units; their hints rebase through unrelated edits and their retained quotes count toward the existing finding budgets.

## Explicit choices

Each generated action ID binds the full current stamp and exact candidate through a generated lookup. No replacement text is parsed from IDs. Native replacement revalidates current source/map/format/undo ownership through Task 11. Previous action IDs cannot apply a changed candidate or mutate current preferences.

Dismissal is session presentation state. Intentional occurrences, disabled rules, learned words, language and repetition/dialogue sensitivity use the versioned project writing-style record, separately from User Canon. Changes capture the displayed runtime identity and pass through `WritingStyleRepository` and `ProjectSession`. Settings use the controller's already-decoded profile. Unreadable/future bytes remain preserved and controls stay read-only; unsupported stored language tags remain representable. Word lookup is NFC-normalized while manuscript/evidence remain unchanged.

An intentional action after typing explicitly captures the current source revision under the current finding stamp. The controller may remember that owned proof for suppression before the metadata-only profile update. Ordinary edits still clear it; they never hash the full source. Existing decisions are never re-anchored by searching for the first duplicate quote.

## Supported findings and status

Current correctness alternatives remain the independently verified `됬다` past-tense and morphology-confirmed bound-noun spacing signatures from Task 6. They are not a whole-paragraph native join replacement. Morphological word/particle/ending/connector repetition and the bounded sentence/causality/rhythm sessions from Tasks 7–8 feed original evidence and plain Korean explanations to the margin. Nonactionable info patterns remain report output. Unsupported, pending, partial, paused and unavailable states are explicit; no-model editing, save, search and EPUB export remain usable.

Project controls appear in Writing settings, alongside the existing typography/author controls. The margin exposes explicit current alternatives and project choices, with category/evidence/action accessibility text and compact details/retry. Other producer custom actions remain hidden until their executor is connected. No panel opens as a side effect of a result, and editor Ghost key handling is unchanged.

## Verification boundaries

Headless synthetic-project integration uses the real pinned provider in Fiction and General modes: native edit, debounce, finding, explicit correction, one Undo, flush and reopen. Additional regressions cover surface-opening admission/focus, distinct session/durable choices, stale action IDs, related original anchors and budgets, late attachment, idempotent reconnect, retained-map transition replay, same-editor external load and unavailable backend/profile write/search/export. Temporary native windows are never displayed; no Purlory product launch or UI smoke is part of this pass.

The frozen Task 12 backend gate passed with unchanged resource/worker inputs: cold 1.070 s, peak resident 868,810,752 bytes, warm 1,024-unit analysis 15.671 ms and admitted-call cancellation drain 14.646 ms. All frozen limits passed; outputs are retained at `build/korean-backend-validation/task-12-frozen-verify-20261016`.

Clean developer-bundle/unsigned-archive validation uses a fresh ignored task output directory. Task-scoped runner copies change only cwd/output/validation paths from the standard scripts so retained app/archive artifacts are not replaced. Runner diffs, hashes and source/artifact/support receipts remain in the ignored execution ledger. Final packaging evidence is recorded separately after validation. This remains developer packaging evidence, not Store or final native acceptance.

The initial implementation gate passed 1,142 tests (2 existing skips), build, PurloryBench and a warning-free Release PurloryCore compile. The reviewed explicit-intentional regression is RED→GREEN and preserves source/projection-reset counts. Nine support privacy tests and 17 notice tests passed. Package/archive validation and required PR/main CI are recorded separately from this logic evidence.

## Initial artifact evidence (superseded candidate)

Before the final native-load ownership hardening, developer bundle and unsigned Xcode archive resource validation passed from clean implementation commit `d31185390b5dde112b722552197a6729ca75239f`. Both support reports verify that exact revision with `sourceDirty=false` and exclude synthetic manuscript/profile canaries and private paths. The standard rejection suite was explicitly repeated against the **new** archive and passed all 11 rejection cases. Product compilation reported zero warnings/errors. Retained `build/Purlory.app` and `build/Purlory.xcarchive` metadata/executable hashes remained unchanged.

Artifacts and full receipts are retained under `build/task-12-package-verification-20261016/`. The tracked code/resource digest (Sources, manifests, Distribution and scripts) is `d2eb164085c40d9f3bb1f18472d5afaa36ddcba201c85a0df836914b40573953`. The associated documentation-only evidence commit preserved this digest. These artifacts remain retained historical evidence; they are not the final ownership-hardened candidate.

| Artifact | Executable SHA-256 |
| --- | --- |
| Developer `Purlory.app` | `5c33ec86cf40a92aa2b6de759ea221c184180d9202f2d443e228e70c9344230e` |
| Unsigned archive application | `16544c2897db3ad9af2c222850a03b32380e5e8556d3bc270951b7f7ed2029b4` |

No local Purlory product launch, UI smoke, signing account, Store validation or actual native acceptance is implied by these resource inspections. Required exact-head PR/main CI and the owner's later acceptance remain separate records in #126/#119.

## Native-load ownership regression gate

Final review reproduced two unsafe loads before the fix: a different native body carrying the same typo/hint, and byte-identical text loaded through another document binding. Each RED test failed three authority/publication assertions. The bridge now proves both the native stable binding key and the loaded original UTF-16 source; a rejection clears capture ownership and queued projection work. The regression also verifies that ignored stale edits cannot restore authority and a correct explicit reload can recover. Existing runtime-key invalidation is preserved.

After hardening, 94 focused tests and the full 1,144-test suite passed (2 existing full-suite skips), as did build and PurloryBench. The unchanged native backend gate above remains applicable; clean bundle/archive validation must be repeated from this hardened committed source before PR delivery. No product launch or final native acceptance is claimed.

## Final clean artifact evidence

Ownership-hardened source `5424a260cd8d38f06fab4a836bfb01e14ec68b8f` passed fresh developer-bundle and unsigned-Xcode-archive validation under `build/task-12-package-verification-20261016-source-owner/`. Both support reports prove that exact clean revision and exclude synthetic manuscript/profile canaries and private paths. The standard rejection helper explicitly targeted this new archive and passed all 11 rejection cases. The earlier candidate, default app/archive and their metadata/executable hashes remained preserved. No Purlory product was launched.

The tracked code/resource SHA-256 (Sources, manifests, Distribution and scripts) is `1084b0f968e151540f922a0fa07bd75bf75ed1f687dbed0ffbfaf1f05da91f5c`. The following evidence-only documentation commit preserves that digest. Final PR/main CI and owner native acceptance remain separately recorded; these packages do not establish Store distribution proof.

| Artifact | Executable SHA-256 |
| --- | --- |
| Final developer `Purlory.app` | `a1daf3c676c36ef3e47a0858c1703b8e286596c5fe5663b3f9a94b36d437c42c` |
| Final unsigned archive application | `507d49f0f712b49be9b54e6efc0b63c00231a152daf78d50b971cac79ba7d873` |
