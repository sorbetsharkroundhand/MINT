> Historical evidence: the names below identify the original tested artifacts, before the Purlory rename.

# HTML native workspace port verification

The supplied `mint.html` is the behavioral contract recorded in
`docs/superpowers/specs/2026-10-19-html-native-workspace-port-design.md`. This port
replaces the prior single-editor presentation with a retained native AppKit canvas.
ProjectSession remains the only manuscript owner. The owner explicitly chose the
existing local AI in place of the HTML's Gemini client.

## Traceability

Paths below are relative to `Sources/MINTCore`; tests are in `Tests/MINTCoreTests`.
Rows group related contracts; they do not imply that screenshots prove every case.

| Source contract | Production path | Deterministic/native evidence |
| --- | --- | --- |
| T01, T03–T07, T11, T13 | `Workspace/SpatialWorkspaceLayout.swift`, `SpatialWorkspaceController.swift`, `SpatialWorkspaceGeometry.swift` | `SpatialWorkspaceTests`, `SpatialWorkspaceControllerTests`: six insertion positions, unique tiles, normalized weights, open/close/all, reading order, corrupt preferences and overflow |
| T02, T08–T10 | `Workspace/SpatialWorkspaceCanvas.swift`, `SpatialTileHeader.swift`, keyed `ContentView.swift` editor bindings | `SpatialNativeWorkspaceTests`: native header events, insertion preview, cancellation, retained editor identity/selection/composition, named native accessibility groups and independent Undo. `TypingUndoTests` also exercises the responder-chain Undo/Redo commands, rather than only invoking the manager directly |
| T12 | `Workspace/SpatialNavigatorDragRegion.swift`, `ProjectNavigatorView.swift` | Native navigator events reorder actual documents while retaining both editors |
| T14–T15 | `Workspace/SpatialResizeHandle.swift`, canvas geometry | Native column/row events, pair equalization, keyboard resizing, project replacement during resize |
| P01–P04 | `Workspace/WorkspacePouchGeometry.swift`, `WorkspacePouchController.swift`, `WorkspacePouchView.swift` | `WorkspacePouchTests`, `FramedWorkspaceTests`: four edges, orientation, spring convergence, outside collapse, restore with the same editor, real native controls |
| E01, E05 | `Workspace/WorkspaceEditorInteraction.swift`, `WorkspaceParagraphTransfer.swift`, `WorkspaceDocumentTransaction.swift`; generic `Editor/EditorWorkspaceInteraction.swift` hooks | `WorkspaceParagraphTransferTests`, `WorkspaceOriginalParagraphTests`, native grip events: rich source, code fence ownership, Option/sole-paragraph copy, atomic Undo/Redo, command lifetime, stale rejection and inactive first grip |
| E02–E03 | `Editor/SelectionToolbar.swift`, `Workspace/WorkspaceAssistance.swift` | `WorkspaceAssistanceTests`, existing formatting/serialization tests: no-model behavior, preserved rich selection, real note creation and explicit manuscript mutations |
| E04, N02 | `Workspace/WorkspaceEntityController.swift`, `Editor/OriginalSourceNavigation.swift`, `SourceNavigation.swift` | `WorkspaceEntityTests`, `WorkspaceCommandPaletteTests`, existing original-source tests: source proof across opaque math, delayed hide/keepalive, fresh closed-tile navigation and return position |
| E06–E08 | `Workspace/WorkspaceEditorInteraction.swift`, canvas and pouch presentation | Native tests: typewriter viewport insets, focus opacity without persisted changes, whisper wake threshold; both-theme synthetic captures |
| E09 | `Editor/CompletionController.swift`, active editor attachment | Existing Ghost/IME/identity tests; continuation button invokes the guarded local Ghost path |
| E10, N01 | `Workspace/WorkspaceWritingStatistics.swift`, document status and `WorkspaceSpatialChrome.swift` | `WorkspacePresentationTests`, framed/native tests: per-document counts, minimum reading time, goal progress, selected editor AX identity and title |
| N03, N06 | ProjectSession creation and `UserData/ProjectWriterToolsView.swift` | Existing project/writer compatibility tests; blank real documents/records retain author edit/delete access |
| N04 | `Workspace/WorkspaceCommandSearch.swift`, `WorkspaceQuickCommandPanel.swift`, `AppCommands.swift` | `WorkspaceCommandPaletteTests`: categories, first nine results, native title invocation and exact original selection. Source search/Ask remain on Cmd-Option-K |
| N05 | `Workspace/WorkspaceCompactCard.swift`, `WorkspaceNarrativeCards.swift`, real writer and margin views | `SpatialNarrativePreparationTests`, entity/native tests: shared expansion, real records, original-backed narrative preparation in write mode; current source/runtime admission retained |
| N07 | Existing palette integration plus pouch/palette theme action | `FramedWorkspaceTests`, `SpatialWorkspaceCaptureTests`: both standard themes; explicit custom palette/font settings remain authoritative |
| A01–A03 | `Workspace/WorkspaceAssistance.swift`, `WorkspaceAssistancePanel.swift`, local-ready `CompletionController` adapter | `WorkspaceAssistanceTests`: explicit apply, whole-document coauthor context, selected-range polish across formatting boundaries with preserved outside source and Undo, original-backed margin suggestions, no-model error, live cancellation and stale/ABA rejection. Synthetic streams test transactions, not real-model quality |

## Verification scope

Native tests use synthetic projects under `CFFIXED_USER_HOME`. The optional
`SpatialWorkspaceCaptureTests` records light/dark workspaces, a mixed tool stack,
live header insertion preview, typewriter/focus, expanded pouch, collapsed orb and
restoration; it also asserts the restored editor is the same native instance.
No fixture comes from a real manuscript. Both historical journal preservation tests
now require an explicitly supplied `MINT_TEST_JOURNAL_FIXTURE` path. The final pass
supplies a generated synthetic journal so these checks run instead of being skipped.

The implementation keeps the original six-way layout and motion constants while
repairing lossy trimming, stale writes, duplicate-source ambiguity and sample AI
fallbacks. Minimum-size overflow scrolls rather than making tiles unreachable.
Native frame coordinates replace the HTML's simulated desktop. Manuscripts remain
opaque under the repository's data/editor invariants.

Automated evidence does not certify human Hangul IME feel, VoiceOver usability,
real-model generation quality/latency, signing, sandbox/archive or Store readiness.
Those remain the existing release checks documented in
`docs/release/verification-and-support.md`.

## Candidate and results

Verification date: 2026-10-20 (Asia/Seoul).

- Code candidate: `d42887004b0f3ae9616d6b9441559ee6d4f96d96`; packaged source dirty flag: `false`.
- Developer app: version 0.1.0, build 1; arm64, OS 27.0.1 (26A434).
- Executable SHA-256: `7c70fbccebb22d29e204068bf5868e1895c85cded6f7c6933e0bcfca1cc6eedf`.
- Notice inventory SHA-256: `7d5a19807b00480f32d3a0c6a93e8227958b4c8ae71aa98302878a6c4d60cf91`; 31 dependencies, 37 vendored/resource components, no bundled model weights.
- Full isolated suite: **1,379 tests, zero failures, no skips** (179.37 seconds). Synthetic journal and native screenshot fixtures explicitly enabled.
- Explicit `swift build` and `swift build --product MINTBench`: passed.
- Standard `scripts/build-mint-app.sh`: passed, including Korean backend, matching Metal library, resources, privacy and notice validation.
- Standard isolated `scripts/smoke-mint-app.sh`: passed, no-model boot, normal termination and no crash; no download directory or legacy journal created.
- Standard `scripts/ui-smoke-mint-app.sh`: passed on this candidate. Real keyboard Undo/Redo, document switches, writer record persistence/edit/delete, image-only clipboard paste with managed-asset hash checks, image/math Undo/Redo and relaunch, focus, invalid recovery, cancel and recovered-copy preservation all passed. Both manuscripts and durable writer data were verified against project manifests.

The UI script copies the identified developer bundle to a unique app identity and
isolated home for automation. It never opens the owner's workspace. Native captures
and allowlisted candidate metadata are retained locally outside tracked source.
This is feature-branch evidence, not release approval or issue closure.
