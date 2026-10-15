# MINT Korean backend

Foundation-only Swift values around the pinned Kiwi C ABI. No MINTCore, Fiction, AppKit, MLX, runtime networking or global dictionary mutation lives here.

Before loading either package manifest or building from a clean checkout, run from the repository root:

```sh
scripts/prepare-korean-backend.sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution --filter KoreanBackendPackagingTests
```

Preparation reconstructs the exact published XCFramework/model inputs from the validated artifact manifest. It verifies archive and member hashes before copying build inputs. Generated binary/model/notice copies are ignored by Git; the resource index and compiled index fingerprint remain tracked. Root package targets use these same sources directly, preserving the existing cross-toolchain dependency pin set. The leaf manifest supports isolated native-library builds.

The published macOS framework contains a universal static archive without framework metadata. Preparation preserves its binary/header bytes and emits a macOS static-library XCFramework descriptor (`libKiwi.a` plus headers), following [Apple's static-library XCFramework format](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle). Xcode links it into MINT without copying an invalid runtime framework. No native recompilation or upstream source alteration is involved.

`KoreanNativeWorker(resources:)` stores configuration only. `analyze(_:)` lazily verifies resources and initializes the native backend on one utility thread. Requests contain at most 1,024 UTF-16 units; NUL input is rejected and empty input does not initialize resources. The caller subdivides larger analysis windows with correct offset/overlap handling.

`cancelPending()` invalidates current and queued publication/admission authority. Task cancellation is also honored. Resource hashing checks admission between chunks and heavy C calls check immediately before entry. An already executing synchronous C call drains; it is not represented as interruptible. `release()` closes admission, waits for admitted initialization/analysis to drain, closes the handles and retires the thread. Cold initialization has a separate measured bound from a warm analysis call; no main actor or foreground Ghost operation waits for it.

Tokens and sentence ranges address the exact original request in UTF-16 coordinates. Virtual zero-length morphemes may describe grammar but are not editable targets. Native join candidates are uncalibrated observations: they can change names, dialect, spacing or Unicode normalization. Production rules must independently prove a safe local change; never apply a whole joined paragraph automatically.

See [native validation and measured limits](../../docs/engineering/korean-backend-validation.md). Final application integration and candidate IME/visual/accessibility acceptance remain separate from this adapter's availability and lifecycle tests.
