# Sandbox Storage and Safe Development Import — Issue #174

## Intent and authority

Make the sandboxed app write to its own container and let a writer explicitly
import development-build manuscripts without losing the source or the current
project. The owner approved project-folder imports, copy verification before
activation, collision rejection, and inline execution without subagents.

The current contract is [#174](https://github.com/sorbetsharkroundhand/MINT/issues/174),
under [#150](https://github.com/sorbetsharkroundhand/MINT/issues/150). Build on
PR #194 at `96554ab427b0275bf2a7ea111883b81f3e8a46ad`; keep the follow-up based on
`codex/173-unsigned-archive` until that PR lands. The owner will inspect CI later.
Neither this design nor a follow-up PR completes #173, #174, or an owner check.

## Storage and sandbox boundary

Keep `MintStorageLocation` as the single path authority. Its standard location
uses Foundation's user Documents directory with the existing home fallback and
`MINT` suffix. In the sandbox this resolves inside the container; SwiftPM
development builds retain their existing Documents/MINT location. Do not
construct a production `~/Library/Containers` path or relocate development data
automatically. Continue to support explicit temporary-root injection.

Configure both native Xcode target configurations with App Sandbox and a shared
entitlements file. Include `com.apple.security.app-sandbox`,
`com.apple.security.files.user-selected.read-write` for import/export/media, and
`com.apple.security.network.client` for existing optional model downloads.
Inference remains local, and writing remains available without a model or network.
Retain #194's unsigned archive; effective runtime entitlements require signing.

## Explicit folder selection

Use one shared folder-selection flow from onboarding and the File menu.
A modern project selection is its UUID directory containing `project.json`.
A legacy selection is the directory containing `entries.json` and `images/`;
retain the existing Fiction/General choice and verified legacy migrator.
Treat a folder with `project.json` as modern; a damaged modern manifest must not
fall back to legacy import. Otherwise require `entries.json`; `images/` is optional.
Select the containing folder so the sandbox grant includes image files.
Panel cancellation performs no import or activation. Keep granted access alive
through preparation and release it on every completion path. Imported projects
subsequently read only their container copies, so no persistent source bookmark
is needed. Import remains disabled while the legacy workspace owns editing.

## Modern project preparation and activation

Add a generic ProjectStore import operation and use the existing
ImportProjectCoordinator → ProjectSession activation boundary. No Fiction types
or knowledge behavior enter storage, and source validation never opens a source
ProjectStore through an API that creates a lock or directory.

1. Validate the source directory UUID against the manifest ID. Reject an
   unsupported schema, duplicate IDs, unsafe relative paths, symlinks, and
   non-regular filesystem objects. Check cancellation throughout traversal.
2. Reject any existing destination for that ID, including an identical prior
   import. Preserve source IDs, references, schema, and file bytes; do not merge
   or overwrite projects. The existing destination-store lock serializes writes.
3. Copy the complete directory into an import-owned, inactive destination.
   Preserve documents, notes, assets, trashed documents, opaque UserData,
   previous manifests, historical blobs, and other regular files. Directory
   import does not reinterpret or rebuild Intelligence.
4. Compare the complete source/destination file inventory and byte hashes;
   validate the destination's current manifest, manuscript and asset hashes
   using ProjectStore. Recheck the source inventory and hashes before returning,
   so a source change during import fails preparation.
5. On failed/cancelled preparation, remove only the incomplete destination
   created by this import. Source bytes and existing destinations are untouched.
   No active marker is written during preparation.
6. At the coordinator cancellation checkpoint, then through
   `ProjectSession.activateProject`, flush the current owner and activate only
   the verified import. Activation failure/cancellation preserves the previous
   active marker and session. A fully prepared copy may remain inactive if this
   final handoff fails; it must never replace the previous valid project.

Legacy import continues to create a separate project with its existing source
and asset preservation checks. Never migrate `entries.json` in place. Standalone
legacy trash, global settings/stopwords, and an entire multi-project development
library are outside this project-folder import; their originals remain available.
Surface import failures through the existing error UI. Request editor focus only
after successful activation; retain the existing IME/selection/Undo handoff.

## Verification and delivery

Write failing regression coverage before implementation. Cover modern import
with General and Fiction manuscripts, Korean/CRLF bytes, images, trashed
documents, opaque UserData, and recovery files. Exercise corruption, ID
collision, traversal/symlink escape, injected copy/verification failure, source
mutation, mid-copy cancellation, and cancellation/activation failure at the
handoff. Assert source bytes, previous active marker, and existing projects are
preserved; verify a successful imported project reopens independently of source.
Reuse legacy, onboarding and project-session coverage for existing behavior.

Add an isolated, genuinely sandboxed storage probe using the production
MintStorageLocation source and the target's entitlements. Give its test app a
unique bundle ID/container and CFFIXED_USER_HOME within that owned container.
Verify standard storage stays there, writes/reopens a fixture, and an ungranted
write to a separate disposable fixture is denied. Clean up only owned fixtures;
never launch against real manuscripts. Configuration or a container-shaped
path alone is insufficient runtime sandbox evidence.

Run focused tests, `swift build`, `swift test`, `swift build --product MINTBench`,
and the existing unsigned archive validators. Wire the sandbox probe into CI
without weakening existing jobs. Keep a bounded follow-up PR near 500 changed
LOC, and record actual local evidence separately from owner-inspected CI.
The owner's representative development-project migration check stays unticked.
Model/metallib fixes (#175), Apple account signing/submission, and Store
distribution proof (#150 Phase B) are outside this change.

## Platform references

- [Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Apple: Code Signing Tasks — Adding Entitlements for Sandboxing Manually](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
