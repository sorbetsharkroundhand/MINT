# Reproducible release benchmark metrics (#179)

Current #179 body/comments read; no active linked PR. Emit a repeatable comparison artifact, without selecting or approving a model. Existing replay performs cache-reset cold inference then warm inference at each deterministic local cut; retain its Unicode-character prefix (>=2) and shared eojeol (>=2 characters, whitespace/punctuation normalized) metrics.

A pure report schema records exact candidate ID/revision, fixture SHA-256, hardware physical/working-set memory, OS/toolchain, parameter settings and attempted/completed samples. Mean cold/warm TTFC excludes missing chunks and records sample counts (no invented zero latency); this remains decoded first-text-chunk latency, not a claim of raw first-token timing. KV reuse is sum warm reused tokens / sum warm prompt tokens. Report null where no valid denominator/latency exists and record failed cuts; incomplete runs exit nonzero.

Count Han codepoints, fixed reasoning tags and fixed assistant/chat boilerplate patterns in consumed raw decoded text before sentence truncation/post-processing. Also count final displayed output separately so sanitization cannot hide a contaminated candidate. These are deterministic pattern counts, not language identification or a universal classifier. Keep fixed positive/negative fixtures in unit tests and document exact ranges/patterns.

Record MLX's lifetime peak active allocation and macOS process lifetime peak physical footprint separately, including model loading. Never sum them or represent either as total system memory. A fresh bench process supplies a clean per-run boundary. Metadata and counters are pure/injectable; bench alone reads toolchain and process memory.

CLI `--release-report <new-json-path>` requires a local replay fixture and explicit model. `--candidate-memory-budget-bytes <positive-uint>` opts into #177's bounded candidate measurement policy without populating app release choices. Validate options/output destination before loading; never overwrite existing report or manuscript files. Successful report output is local only. CLI dry/help/invalid-option smoke must not download models.

Two bounded PRs if needed: pure schema/metrics/fixtures/docs, then raw observation and CLI reporting/metadata/memory plumbing. Unit regression coverage precedes product changes. Run full isolated tests and Swift/bench builds; no physical candidate inference or owner model/license approval is inferred. CI completion is deferred to the user, leave #179 open.
