#!/bin/sh
# Exercise rejection of incomplete/signed archives using a copy of the real artifact.
set -eu
cd "$(dirname "$0")/.."

ARCHIVE="${1:-build/MINT.xcarchive}"
scripts/validate-mint-archive.sh "$ARCHIVE"
ARCHIVE_TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mint-archive-validation.XXXXXX")
trap 'rm -rf "$ARCHIVE_TEST_ROOT"' EXIT
FIXTURE="$ARCHIVE_TEST_ROOT/MINT.xcarchive"
ditto "$ARCHIVE" "$FIXTURE"
APP="$FIXTURE/Products/Applications/MINT.app"

expect_rejected() {
    if scripts/validate-mint-archive.sh "$FIXTURE" > "$ARCHIVE_TEST_ROOT/result.log" 2>&1; then
        echo "Archive validator accepted $1" >&2
        exit 1
    fi
    echo "Rejected $1"
}

/usr/libexec/PlistBuddy -c 'Set :ApplicationProperties:Team unexpected-team' "$FIXTURE/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Add :ApplicationProperties:Team string unexpected-team' "$FIXTURE/Info.plist"
expect_rejected "an archive with a signing team"
cp "$ARCHIVE/Info.plist" "$FIXTURE/Info.plist"

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.invalid' "$APP/Contents/Info.plist"
expect_rejected "an unexpected application"
cp "$ARCHIVE/Products/Applications/MINT.app/Contents/Info.plist" "$APP/Contents/Info.plist"

METAL=$(find "$APP/Contents/Resources" -type f -name default.metallib -print -quit)
mv "$METAL" "$ARCHIVE_TEST_ROOT/default.metallib"
expect_rejected "an archive without MLX shaders"
mv "$ARCHIVE_TEST_ROOT/default.metallib" "$METAL"

FONT=$(find "$APP/Contents/Resources" -type f -name latinmodern-math.otf -print -quit)
mv "$FONT" "$ARCHIVE_TEST_ROOT/latinmodern-math.otf"
expect_rejected "an archive without math fonts"
mv "$ARCHIVE_TEST_ROOT/latinmodern-math.otf" "$FONT"

scripts/validate-mint-archive.sh "$FIXTURE"
PRIVACY="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
mv "$PRIVACY" "$ARCHIVE_TEST_ROOT/PrivacyInfo.xcprivacy"
expect_rejected "an archive without its root privacy manifest"
mv "$ARCHIVE_TEST_ROOT/PrivacyInfo.xcprivacy" "$PRIVACY"
/usr/libexec/PlistBuddy -c 'Set :NSPrivacyTracking true' "$PRIVACY"
expect_rejected "an archive with an unexpected tracking declaration"
cp Distribution/Resources/PrivacyInfo.xcprivacy "$PRIVACY"
NOTICES="$APP/Contents/Resources/ThirdPartyNotices.txt"
mv "$NOTICES" "$ARCHIVE_TEST_ROOT/notices.txt"
expect_rejected "an archive without license notices"
mv "$ARCHIVE_TEST_ROOT/notices.txt" "$NOTICES"
printf 'tampered\n' >> "$NOTICES"
expect_rejected "an archive with changed license notices"
cp "$ARCHIVE/Products/Applications/MINT.app/Contents/Resources/ThirdPartyNotices.txt" "$NOTICES"
printf 'fixture\n' > "$APP/Contents/Resources/unapproved.safetensors"
expect_rejected "an archive with unapproved model weights"
rm "$APP/Contents/Resources/unapproved.safetensors"
scripts/validate-mint-archive.sh "$FIXTURE"
echo "Archive validation regressions passed"
