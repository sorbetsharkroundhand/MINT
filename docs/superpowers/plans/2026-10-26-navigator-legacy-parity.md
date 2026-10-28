# Restore legacy navigator behavior within the current design

Work inline on `codex/purlory-editorial-redesign`, preserving the shared checkout. The user explicitly requested the behavior from the pre-redesign navigator, including sorting, nested folders, grouping documents by dropping one onto another, and extraction by dragging outside a folder's region.

## Implementation contract

- Use `SidebarDragDrop.swift`, `SidebarView.swift` and the corresponding `EntryStore` operations as behavioral references. Keep `ProjectSession` and `ProjectNavigation` as the durable project owners.
- Preserve the current tree, indentation guides, folder dividers and spatial drag engine. Remove the dedicated extraction strip and redundant direct extraction menu item introduced in the previous attempt.
- Match legacy document zones: edge quarters reorder, center groups without modifiers. Documents dropped on folder rows enter that folder; folder drags reorder or nest, with cycle prevention and spring expansion.
- Make indentation gutters and existing folder-bottom dividers accept extraction into the enclosing list. Empty navigator background extracts to the root.
- Bound hit tests by both actual row bounds and the visible region; an oversized SwiftUI `visibleRect` must never capture another row or the workspace.
- Preserve undo, manuscript contents, retained editor hosts and durable folder membership. Reordering selects manual sorting so its result is visible.

## Steps

- [x] Audit legacy functions against current navigation, sorting, search, creation, rename, date/kind changes, trash/restore, export and naming paths.
- [x] Observe failing regressions for direct grouping, legacy nesting zones, natural extraction, cycle rejection and new-folder ordering.
- [x] Restore legacy zones and ordering, add natural outdent targets, and remove the rejected controls.
- [x] Verify native document/folder gestures, grouping, subtree extraction, cancel, undo, spring expansion and saved organization.
- [x] Complete builds, broader spatial/math tests and the full suite; compare known baseline failures and record evidence.

Use synthetic projects with `CFFIXED_USER_HOME=/tmp/purlory-navigator-parity-evidence/home`. No real manuscripts or production bundle are involved.

Final evidence: build and benchmark compile passed; 52 focused tests passed both separately and within the full run. The full suite ran 1,454 tests and retained exactly the same 16 failing cases as the preceding baseline, with no new failures. See [verification](../../release/navigator-legacy-parity-verification-2026-10-26.md).
