# Pinned model installation (#176)

The editor must remain usable without a model. A single cached shard is not a ready installation. Preserve the existing preset IDs without approving their release lineup/license; #177/#180 own that policy.

Compile immutable Hub revisions and complete file inventories into a manifest. LFS files use SHA-256; regular Git files use their Git blob SHA-1 (including the blob header), exactly as published by the Hub. Require safe relative paths, sizes, config/tokenizer/weights, and integrity for every file.

Own installations under MINT/Models, separate from manuscripts, Intelligence and the shared Hub cache. Download only named files at the exact revision into staging. Verify regular-file size and digest with bounded, cancellable streaming reads before writing a receipt and publishing the directory. Interrupted staging is never ready; retries may reuse verified staged files. Leave older revisions intact.

Use one shared installation actor to serialize operations per model and share duplicate requests. Observe missing/downloading/verifying/ready/interrupted/failed states. Refresh and load verify a receipt against the current manifest and the complete file inventory outside the main actor. Loading uses only the verified local directory; no mutable Hub lookup or unpinned custom model fallback.

Three reviewable PRs: immutable manifest metadata and validation, owned installation state with deterministic filesystem tests, then download UI/engine integration with lifecycle tests. Local tests use disposable fixtures, no model weights or real manuscripts. No CI wait, merge, issue closure or owner-check edit. The user's unattended inline execution instruction supersedes intermediate design/plan approval pauses and subagent review requirements.
