# #183 deterministic recovery coverage

Current #183 and parent #151 define automated durability coverage, with UI in #184.
The authoritative ProjectStore/ProjectSession already verifies immutable document,
asset and opaque UserData bytes before atomic manifest/active-marker publication.
Reuse ProjectFileSystem injection; do not replace Foundation atomic I/O or create
a production crash-control API just to test failure orchestration.

A reusable test filesystem injects either before an atomic write or while an
uncommitted replacement is staged. The staging double models interruption before
the atomic commit boundary; it does not claim physical power-loss/fsync proof.
Only fixture-owned staging bytes may be removed. Enumerate durable UserData,
manuscript/note, previous/current manifest, asset and active-marker commits. Each
case gets a fresh root so unreferenced immutable blobs cannot bypass injection.
Assert the injected phase actually fired, exact previous manifest/active marker,
and verified reload of the previous document and explicit decisions.

Migration receipt/source/assets and pre-activation failure must retain the old
owner and untouched legacy archive; successful retry/reopen is separately verified.
Corrupt manifest/blob candidates cannot replace the active runtime. A corrupt
derived sidecar becomes empty/rebuildable and replacement changes no durable
manifest/body/UserData. Restart after a completed save before activation finds
the previous active owner and a verified saved candidate.

Meaningful mutation RED proves byte-hash verification assertions fail without the
production guard. Full tests/app/bench and exact-production developer smoke precede
Draft PR. Inline author review, no CI wait, issue closure, owner checkbox or real
manuscripts; continue #184 after this independent coverage is delivered.
