#!/bin/sh
# Produce the unsigned #173 distribution foundation; signing belongs to #150 Phase B.
set -eu
cd "$(dirname "$0")/.."
scripts/prepare-korean-backend.sh

# Keep one dependency authority. Xcode's generated workspace receives the same pins.
LOCK_DIR="Distribution/Purlory.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$LOCK_DIR" build
cp Package.resolved "$LOCK_DIR/Package.resolved"
PURLORY_SOURCE_REVISION=$(git rev-parse HEAD)
PURLORY_SOURCE_DIRTY=false
[ -z "$(git status --porcelain --untracked-files=normal)" ] || PURLORY_SOURCE_DIRTY=true

xcodebuild archive \
    -project Distribution/Purlory.xcodeproj -scheme Purlory -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$PWD/build/Purlory.xcarchive" \
    -derivedDataPath "$PWD/.build/archive-dd" \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    -skipMacroValidation \
    ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=

# The archive is unsigned. Record provenance before validation/any owner signing.
# Stamp the exact checkout after Xcode expands the explicit distribution Info.plist.
PURLORY_ARCHIVE_INFO="build/Purlory.xcarchive/Products/Applications/Purlory.app/Contents/Info.plist"
plutil -replace PurlorySourceRevision -string "$PURLORY_SOURCE_REVISION" "$PURLORY_ARCHIVE_INFO"
plutil -replace PurlorySourceDirty -bool "$PURLORY_SOURCE_DIRTY" "$PURLORY_ARCHIVE_INFO"
scripts/validate-purlory-archive.sh
