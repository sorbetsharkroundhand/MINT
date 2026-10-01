#!/bin/sh
# Produce the unsigned #173 distribution foundation; signing belongs to #150 Phase B.
set -eu
cd "$(dirname "$0")/.."

# Keep one dependency authority. Xcode's generated workspace receives the same pins.
LOCK_DIR="Distribution/MINT.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$LOCK_DIR" build
cp Package.resolved "$LOCK_DIR/Package.resolved"

xcodebuild archive \
    -project Distribution/MINT.xcodeproj -scheme MINT -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$PWD/build/MINT.xcarchive" \
    -derivedDataPath "$PWD/.build/archive-dd" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    -skipMacroValidation \
    ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

scripts/validate-mint-archive.sh
