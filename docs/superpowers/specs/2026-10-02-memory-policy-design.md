# Memory-gated release models (#177)

Choose and load only an explicitly approved, revision-pinned model that fits this Mac. Preserve existing selected IDs and all writing/settings data, while refusing unsupported loads before MLX initialization or download. Candidate file sizes are not measured peak memory or a release endorsement.

Use a pure `ModelMemoryPolicy` with injectable `HardwareMemory` and `[ModelReleaseEntry]`. Detect the highest 8/16/24/32 GiB tier no larger than physical unified memory; machines below 8 GiB or without unified Metal memory are unsupported. Enforce peak memory at or below 60% of the smaller physical/Metal recommended working set, matching #180's peak target. Validate positive declared peaks, immutable revisions and supported/default tiers. Multiple defaults for a tier are invalid rather than resolved by order.

The compiled approved catalog remains empty until the owner supplies #180/#155 evidence. This intentionally leaves no normal release model/default available; show a short explanation and keep writing usable. Do not select a candidate based on historical benchmarks. Catalog rows/defaults are generated from approved entries, while saved IDs remain recoverable and receive a local unsupported explanation. Guard manual settings changes, download starts and inference preflight with the same policy.

The benchmark needs to gather the evidence required for approval. Provide an explicit candidate-evaluation policy taking a declared peak-byte budget, restricted to pinned candidates and the same hardware budget check. It does not populate the normal UI catalog or grant release approval. #179 will expose the explicit CLI option; no hidden app override.

Split pure policy/schema and app integration if the complete change exceeds ~500 LOC. Test deterministic tier/budget/default decisions without a GPU, fail missing/unapproved/changed revision or oversized declarations, test local engine rejection before resource initialization, and preserve saved selections/unrelated settings. Run isolated tests and builds for each slice. No physical model-fit claim, license approval, CI wait, merge or owner-check edit.

Self-review: empty approved policy is the explicit safe behavior while owner evidence is pending, not a placeholder for invented mapping. The candidate evaluation path avoids a circular dependency between approval and measurement. User instruction authorizes inline execution without intermediate approval handoffs or subagents.
