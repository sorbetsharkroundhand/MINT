#!/bin/sh
# Inspect the unsigned #173 archive without launching it or using Apple credentials.
set -eu
cd "$(dirname "$0")/.."

ARCHIVE="${1:-build/MINT.xcarchive}"
APP="$ARCHIVE/Products/Applications/MINT.app"
fail() { echo "Archive validation failed: $*" >&2; exit 1; }

[ -s "$ARCHIVE/Info.plist" ] || fail "missing archive Info.plist: $ARCHIVE"
plutil -lint "$ARCHIVE/Info.plist" >/dev/null
[ "$(plutil -extract ApplicationProperties.ApplicationPath raw -o - "$ARCHIVE/Info.plist")" = "Applications/MINT.app" ] \
    || fail "archive does not identify MINT as its application"
for SIGNING_FIELD in SigningIdentity Team; do
    SIGNING_VALUE=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$SIGNING_FIELD" "$ARCHIVE/Info.plist" 2>/dev/null) || SIGNING_VALUE=""
    [ -z "$SIGNING_VALUE" ] || fail "unexpected archive signing metadata: $SIGNING_FIELD"
done
[ -s "$APP/Contents/Info.plist" ] || fail "missing application Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
[ "$(plutil -extract CFBundlePackageType raw -o - "$APP/Contents/Info.plist")" = "APPL" ] \
    || fail "product is not an application bundle"
[ "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")" = "app.mint.MINT" ] \
    || fail "unexpected application bundle identifier"
[ "$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")" = "MINT" ] \
    || fail "unexpected application executable"
[ -x "$APP/Contents/MacOS/MINT" ] || fail "missing executable"
xcrun lipo "$APP/Contents/MacOS/MINT" -verify_arch arm64
[ ! -d "$APP/Contents/_CodeSignature" ] || fail "application was bundle-signed"
[ ! -e "$APP/Contents/embedded.provisionprofile" ] || fail "unexpected provisioning profile"

RESOURCES="$APP/Contents/Resources"
[ -d "$RESOURCES" ] || fail "missing package resources"
python3 scripts/validate-mint-privacy.py "$APP"
[ -n "$(find "$RESOURCES" -type f -name default.metallib -size +0c -print -quit)" ] \
    || fail "missing compiled MLX Metal library"
[ -n "$(find "$RESOURCES" -type f -name latinmodern-math.otf -size +0c -print -quit)" ] \
    || fail "missing SwiftMath font resources"

echo "Validated unsigned MINT archive: $ARCHIVE"
