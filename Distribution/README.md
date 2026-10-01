# Unsigned Xcode archive

Issue [#173](https://github.com/sorbetsharkroundhand/MINT/issues/173) adds the
minimum native app target for the distribution foundation. Open
`MINT.xcodeproj` and use its shared `MINT` scheme. It compiles the existing
`Sources/MINT/MINTApp.swift` entry point and links the root Swift package's
`MINTCore` library; `Package.swift` remains the dependency/source authority.
The project stays under `Distribution/` so existing root SwiftPM/Xcode Metal
preparation commands keep their current behavior.

From the repository root, with full Xcode and its Metal toolchain installed:

```sh
swift package resolve
scripts/archive-mint-app.sh
scripts/test-mint-archive-validation.sh
scripts/test-mint-sandbox-storage.sh
scripts/test-mint-sandbox-mlx.sh
```

The result is `build/MINT.xcarchive`. `scripts/validate-mint-archive.sh` checks
its application metadata, Apple Silicon executable, compiled MLX Metal
library, SwiftMath fonts, and absence of signing metadata, an application
bundle signature, or a provisioning profile. The regression script copies
the real artifact and checks rejection of signing metadata, an unexpected
application, missing shaders, and missing fonts. CI uploads
`MINT-unsigned-xcarchive` as an inspectable ZIP.
The generated Xcode workspace uses the root `Package.resolved` pins.
The arm64 linker leaves an intrinsic ad-hoc signature in the executable;
the archive has no Apple signing identity/team or sealed bundle signature.

Both target configurations declare App Sandbox, user-selected file read/write,
and network-client entitlements (optional model downloads; inference stays local).
Signing remains disabled for the unsigned archive. The storage regression script
compiles the production `MintStorageLocation` source into a uniquely identified,
ad-hoc-signed probe. It checks effective entitlements, container write/reopen, and
denial of an ungranted external write; an unsandboxed control must fail despite
its redirected home. Its CFFIXED_USER_HOME and disposable
container/fixtures are isolated from real manuscripts. All probe data is removed
afterward; macOS may retain its protected container-manager metadata record.
This proves the storage resolver boundary, not the full signed app or Store build.

Foundation selects Documents/MINT inside the container for a sandboxed build;
SwiftPM development builds keep their existing Documents/MINT location. Nothing
automatically moves development data. Onboarding and File > Import Project use
explicit folder selection: select a modern UUID folder containing `project.json`,
or a legacy folder containing `entries.json` and optional `images/`. Legacy import
asks for the writing mode; modern import preserves its manifest mode. A damaged
modern manifest cannot fall back to legacy import. Duplicate project IDs are
rejected. A complete copy is verified before activation; failure or cancellation
preserves the source and current project. A copy verified before a failed handoff
may remain inactive. Global legacy settings/trash and whole-library migration
are outside this per-project import; their originals remain available.

MLX initialization validates the developer-colocated library or the native
`mlx-swift_Cmlx.bundle` library through bundle URLs before model loading or MLX
memory configuration. Missing, empty, escaping or corrupt resources produce an
actionable local error while writing remains available. Initialization runs once
at first model load and checks a small GPU operation through MLX's throwing error
boundary; it does not scan manuscripts or download a model.

The MLX smoke script copies the actual native archive, applies the existing
sandbox entitlements, and invokes the app's explicit archive diagnostic. It
requires GPU result 42 from packaged resources, tests missing/corrupt libraries,
checks process survival and normal termination, and rejects model downloads.
Every copy has a unique identity/container and CFFIXED_USER_HOME; the original
archive and real manuscripts are untouched. The diagnostic is enabled only by
`MINT_VERIFY_MLX_RESOURCES=1`, writes its result inside standard storage, and does
not select a model or authorize AI.

The default smoke requires a Metal-capable Mac and never skips GPU validation.
Standard archive CI runs `scripts/test-mint-sandbox-mlx.sh --resource-errors-only`
to exercise missing/empty resources and editor survival before Metal is touched.
This mode does not prove GPU initialization. GitHub's [standard macOS runner
specification](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
does not guarantee GPU acceleration; the full smoke must run on actual supported
hardware. The existing archive, storage, build and test gates remain required.

No Apple account or Store upload is involved. #150 Phase B owns signed Store
distribution proof; the real-device owner check in #175 remains separate.
The initial version fields match the current developer bundle and do not
declare a release version. Existing SwiftPM builds/tests and developer-bundle
smoke remain in CI.
