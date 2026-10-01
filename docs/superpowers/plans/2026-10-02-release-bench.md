# Release Benchmark Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; no subagents or intermediate approval handoffs, per user instruction.

**Goal:** Emit reproducible pinned-model quality, cold/warm latency, KV reuse and memory measurements.
**Architecture:** Pure report/counter value types plus a benchmark-only raw observation/metadata adapter in existing replay.
**Tech Stack:** Swift Codable/CryptoKit, MLX allocator snapshots, Darwin process footprint, existing local fixture.
**Spec:** docs/superpowers/specs/2026-10-02-release-bench-design.md

## Global Constraints
- Count consumed raw text separately from displayed text; no source manuscript/output text in the JSON.
- TTFC means decoded chunk; absent samples/denominators are null, not zero.
- Exact pins, fixture hash, OS/toolchain and memory boundary recorded; no model winner/fit/license claim.
- No network in fixture tests/CLI validation smoke; never overwrite existing report files.

## Review Focus
- Sanitization must not conceal reasoning/chat/Han contamination.
- Missing TTFC and zero prompts must not fabricate perfect measurements.
- Cold cache reset must precede each cold sample; warm denominator is warm prompt count.
- Failed/incomplete cuts must be visible and return failure.
- Candidate evaluation must be explicit and preserve normal release gating.

## Task 1: Pure release metrics
Files: Sources/MINTCore/Inference/ReleaseBenchmarkReport.swift, Tests/MINTCoreTests/ReleaseBenchmarkReportTests.swift, docs/release-model-benchmark.md.
Interfaces: BenchmarkContamination.count(_:); ReleaseBenchmarkSample(coldText:warmText:rawColdText:rawWarmText:truth:coldTTFC:warmTTFC:warmPromptTokens:warmReusedTokens:); ReleaseBenchmarkReport(metadata:samples:attempted:), Codable aggregates and write(to:) with no overwrite.
- [x] Add failing deterministic fixtures for known Han/reasoning/chat patterns, clean Korean, hit/KV/TTFC/null math and no-overwrite export.
- [x] Implement schema/counters/aggregation and exact metric documentation.
- [x] Run focused/full isolated tests, Swift/bench builds; review inline, commit and stacked Draft PR.

## Task 2: Engine observation and CLI
Files: CompletionEngine.swift, Sources/MINTBench/main.swift, benchmark observer tests.
Interfaces: benchmark SPI rawText on Completion preserving consumed chunks before cuts; MLX peak snapshot; explicit CLI candidate budget/report options, injected metadata to Task 1 report.
- [x] Add failing raw-before-sanitization and option/path validation regression coverage.
- [x] Capture raw decoded text without changing displayed behavior; report fixture/toolchain/hardware/peak metadata and all required metrics from replay.
- [x] Run focused/full isolated tests, Swift/bench builds and no-load CLI smokes; review inline, commit and stacked Draft PR. No CI wait.
