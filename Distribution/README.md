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

This is an unsigned archive, with no Apple account, Store upload, sandbox
migration, or runtime resource-loading change. #174 owns sandbox storage;
#175 owns sandboxed MLX loading; #150 Phase B owns signing/distribution proof.
The initial version fields match the current developer bundle and do not
declare a release version. Existing SwiftPM builds/tests and developer-bundle
smoke remain in CI.
