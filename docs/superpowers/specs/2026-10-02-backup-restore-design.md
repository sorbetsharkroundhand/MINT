# #184 verified previous-backup restore

Current #184 and #151 require explicit writer choice, verified activation and
source preservation. #183 establishes deterministic failures on the authoritative
ProjectStore/ProjectSession. Restore the existing local previous-project manifest,
not an invented cloud/archive service. No owner wording approval is assumed.

Preview materializes every manuscript, asset, legacy archive and opaque UserData
record from the previous manifest and identifies project title/document summaries.
A canonical manifest fingerprint prevents a changed backup from silently replacing
the preview. Restoration re-verifies and writes an independent new project ID with
the same document IDs, original assets, opaque decisions and archived legacy bytes.
Preserve the entire source directory, including broken current manifest, previous
manifest and derived cache. No user-data/domain-dependent rewrite in generic store.
Do not copy derived Intelligence. New copy is verified before activation.

Session restoration flushes any surviving mutable owner, prepares domain data,
loads the asset catalog and uses existing conditional activate/adopt semantics.
Activation/preparation/write failure leaves the former runtime/marker intact; a
verified inactive copy may remain after failure. A failed initial open may resolve
its active project ID without materializing the broken current manifest. Preview
and cancel perform no writes/transition. No competing mutable runtime is created.

A bounded native sheet/error entry identifies the previous saved project, document
count and text preview, explains a separate recovered copy, and offers Cancel/Open
recovered copy. Add a file-menu entry for healthy/surviving sessions and an error
screen entry when automatic open failed. Busy transitions cannot launch overlapping
restore actions. Runtime/coordinator tests cover success, cancel, corrupt/stale
backup, write/activation/preparation failure and reopening with verified assets.
Owner native copy/wording and RC interaction remain pending.

Two bounded slices: verified storage preview/copy; authoritative session and native
flow. RED/GREEN, focused/full/build/bench and exact-production bundle smoke precede
each Draft PR; no CI/merge wait, real manuscripts, model decision or owner check.
