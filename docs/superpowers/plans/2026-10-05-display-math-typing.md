# Display Math Typing Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; the user forbids subagents and authorizes continuous work without another approval.

**Goal:** Preserve double-dollar opening delimiters until a display formula closes.

**Architecture:** Fix delimiter ownership in the shared MathScanner, then reuse its results for closing-inline detection. The editor keeps its existing display wrapper, marked-text guard and native Undo implementation.

**Tech Stack:** Swift/Foundation scanner, native AppKit editor harness, packaged UI smoke.

**Spec:** [Issue #241](https://github.com/sorbetsharkroundhand/MINT/issues/241), current body/comments refreshed 2026-10-05; no blockers or active PR.

## Global Constraints
- No math UI redesign, new Markdown dialect, disk/inference work or IME changes.
- Preserve adjacent inline formulas, escaped dollars and code exclusions.
- Owner macOS/IME verification stays unclaimed; required CI precedes merge.

## Review Focus
- Incomplete and complete display delimiters must not publish inline atoms.
- A previous inline closer next to a new inline opener must remain valid.
- An escaped literal dollar followed by inline math must remain valid.
- Cursor-bound closing detection must retain its existing currency exclusions.
- Display typing, serialization and native Undo/Redo must agree.

### Task 1: Preserve delimiter ownership

**Files:** Modify `Sources/MINTCore/Editor/MathScanner.swift`, `Tests/MINTCoreTests/MathScannerTests.swift`; create `Tests/MINTCoreTests/MathDisplayTypingTests.swift`; extend `scripts/ui-smoke-mint-app.sh` with double-dollar typing lifecycle evidence after main incorporates the harness fixes from #193.

**Interfaces:** Existing `MathScanner.regions(in:skipping:)` and `closingInline(in:atCaret:)` signatures remain unchanged. Native editor uses them as today.

- [x] Add failing scanner regressions for incomplete `$$E=mc^2$` and real editor per-character typing through `$$E=mc^2$$`; preserve adjacent inline/escape cases.
- [x] Run scanner tests (pure Foundation, safe during another isolated UI test). Run native editor tests only after any UI smoke ends; record actual failures before production edits.
- [x] Keep both opening dollars owned by display scanning and use scanner output for closing-inline detection; update touched historical guide citation to the current invariant.
- [ ] Run math scanner/round-trip/native typing/Undo tests, full tests, required builds and packaged typing/save/reopen evidence serially with foreground tests.
- [ ] Review inline, commit/push/create/attach one bounded PR; merge the exact reviewed latest head after required CI. Leave owner checkboxes untouched.
