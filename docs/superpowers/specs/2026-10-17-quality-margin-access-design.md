# Reachable prepared writing suggestions

Issue: #270, first quality-presentation slice; follow-up to #126 integration. Baseline: verified Outline successor `662a7c1f14743a58c3727a7e21c54d2d23e2f390`, PR #285 in CI. Delivery waits for its required merged-main CI.

## Authority and scope
The owner directed performing all UI/internal functionality on 2026-10-17. Choose the recommended bounded design, write/review its specification and plan inline and implement sequentially without subagents or repeated approval prompts. Required exact-head PR/main CI and standing green-CI merge authorization remain. Actual MINT checks are owner-handled later; do not launch the product/UI-smoke scripts or operate a shipping LLM.

Code inspection found a real presentation gap: the diagnostics runtime populates LivingMarginModel, but the rail has no opening action and both layout gates exclude the stored `margin` section. Existing integration tests exercise the model/view body rather than the reachable workspace. Record this correction to prior integration claims; reuse the existing framework and producer instead of rebuilding them.

This slice exposes existing quality suggestions and their safe original-evidence navigation. Story/continuity/scene/thread producers and optional local-model alternatives remain subsequent #270 work; do not close #270 or #126's final native acceptance on this partial delivery.

## UI and presentation state
Offer a native rail action named `문장 제안` when a diagnostics runtime is connected or prepared supported insights exist. Opening it explicitly selects the existing `margin` tool, returns to Write and restores editor focus/selection. No NLP/model/report work starts from that action or rendering. Empty content stays quiet using the existing empty state and runtime status. Results never auto-open a tool or change geometry while writing.

Track explicit opening in ephemeral workspace state; use a presentation-only `marginVisible` flag in the existing context visibility/layout policy. Do not add a saved section ID, migrate preferences or expose a stored empty/deferred margin on its own. Close and other tool selection retire that transient opening; changing projects retires it as well. Outline may temporarily cover the open margin and restore the saved tool when closed. Keep the existing native editor and Undo owner mounted for all transitions/docks. Give the opaque panel an inspectable, non-hit-testing native boundary, using the same surface pattern as the frame/Outline, without stacked glass.

## Original-evidence navigation
The current generic margin bridge searches a resolved quote and can pick the first duplicate. A writing diagnostic must instead resolve its published insight ID to the current stamped finding and its original/related evidence ranges. Extend the internal LivingMarginView callback to carry both insight and anchor; only the quality route uses this exact path. Existing Story routes remain unchanged for their later producer work.

In one explicit synchronous main-actor transaction, require active/non-dismissed published insight membership; current controller finding stamp; full snapshot identity; actual native document key; matching native revision/map; no marked text; exact original UTF-16 evidence at its captured offset; and a native mapping for every representative source range. Select the mapped native span, capture the first project-owned source return point and restore editor focus. Never use fuzzy/ordinal quote search for quality findings, rewrite source, move during composition or admit NLP work. An unprovable/stale target publishes a quiet localized status and leaves selection/source unchanged. Reuse the exact source-return transaction and expose `집필 위치로 돌아가기` in the margin.

Existing durable apply/ignore/learn/intentional actions remain owned by WritingDiagnosticsActions and WriterStyleProfile, separate from User Canon. No action/schema/provider/resource/API-visibility widening is needed.

## Verification and review
Add failing whole-workspace coverage for the absent native rail action and panel, including a paused counting native worker: opening/closing/switching modes keeps analysis count, source, selection, editor identity and Undo stable, while saved dock/tool state behaves as specified. Keep stored empty-margin behavior when no producer exists. Add failing owned integration tests for the new navigation API, exact second duplicate through Markdown, return capture, altered evidence, stale generation/actual key and marked-text refusal.

Run focused workspace/diagnostic/native suites, full tests, build and MINTBench under temporary CFFIXED_USER_HOME with locked resolution. Review inline, publish one bounded partial-#270 PR, attach it and require all three exact PR and merged-main jobs. Preserve all earlier artifacts, models, backups and ledgers. Final native/IME/VoiceOver/appearance acceptance stays with #119.

Inline design review: this restores access to an already implemented producer and fixes an unsafe future UI route before exposure. Preparation remains outside presentation, source and native owners are proved together, empty/uncertain output stays quiet and no durable-data migration or new dependency exists. Owner-only release choices are untouched; no unresolved UI/internal choice remains under the execution directive.
