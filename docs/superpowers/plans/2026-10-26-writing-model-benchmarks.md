# Writing Model Benchmarks Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for implementation in this chat. Follow the owner's requested sequence; no parallel agents are needed.

**Goal:** Reclaim obsolete downloaded model weights and measure Qwen3.5 9B, Ministral 3 14B, and Gemma 4 26B-A4B through MINT's native local completion engine, including nonempty Korean continuation evidence.

**Architecture:** Reuse the existing revision-pinned installation store, MLX Swift engine, cursor-bounded context assembly, and schema-2 MINTBench reports. Register the three MLX 4-bit artifacts as measurement candidates. Normal shipping model approval remains separate from this explicitly requested experiment.

**Tech Stack:** Swift 6, AppKit/SwiftUI, MLX Swift, Hugging Face immutable model inventories, Apple M2 Max with 32 GiB unified memory.

**Spec:** The owner's 2026-10-26 request in this chat; current #99, #179, and #180 contracts; `docs/release-model-benchmark.md`.

## Global Constraints

- Preserve the existing dirty redesign worktree and manuscript/user-decision data.
- Delete only identified obsolete model caches; record exact paths, identities, and reclaimed bytes.
- Never upload a manuscript. Use repository fixtures and synthetic prose for inference and UI checks.
- Keep immutable revisions, file integrity checks, cancellation, IME, stale-result checks, and the existing memory cap.
- Run one inference process at a time. Compare the same fixture, generation settings, and hardware.
- Do not equate plausible continuation, exact held-out matching, and shipping quality. Record each separately.
- Preserve the later goal: audit/port remaining core functions, run integrated tests, then merge main when required checks pass. This first experiment is not evidence that all of that later work is complete.

## Review Focus

- Boundary prompts can produce newline-only output that is invisible after normal Ghost processing.
- Model-specific chat templates, thinking tokens, and tokenizers can fail despite successful weight loading.
- Gemma's complete pinned weight set is near this Mac's candidate memory cap; measure actual peak before claiming fit.
- Runtime metallib must match the locked MLX revision.
- Bench success must also exercise the native editor's Ghost display/accept path with synthetic data.

## Tasks

- [x] Inspect checkout, storage, installed runtime support, current issue contracts, and exact model inventories.
- [x] Remove the six identified obsolete Hugging Face caches; retain cleanup evidence.
- [x] Add immutable candidate manifests and verify the existing metadata/preflight tests.
- [x] Prepare the matching MLX runtime and optimized benchmark binary.
- [x] Install and measure each model with the same 12-cut Korean replay fixture, preserving logs and schema-2 reports.
- [x] Run synthetic mid-sentence continuation probes; diagnose any load, empty-output, or contamination failures before changing implementation.
- [x] Verify Ghost generation/display/acceptance in the redesign editor using an isolated home and explicit candidate policy.
- [x] Save comparative results and identify remaining integration work before the eventual full-feature merge.

## Completion evidence (2026-10-27)

See `docs/release/writing-model-benchmarks-2026-10-27.md`. All three candidates were measured; all three real-model editor checks passed (Qwen/Ministral continuation, Gemma instruct). The focused 72-test suite and two acceptance-undo regressions passed. The full 1,466-test suite exposed 36 failures across 19 current redesign test methods, all listed in the report. The broader integration/main merge remains outstanding.
