#!/bin/sh
# #100 진단: 전체 MLX 빌드 전에 LaunchServices의 홈·설정 전달을 확인한다.
set -eu
cd "$(dirname "$0")/.."
PROBE_ROOT=$(mktemp -d /tmp/mint-prefs-probe.XXXXXX)
PROBE_ROOT=$(cd "$PROBE_ROOT" && pwd -P)
PROBE_APP="$PROBE_ROOT/Probe.app"
PROBE_HOME="$PROBE_ROOT/home"
PROBE_ID="app.mint.probe.$(uuidgen)"
mkdir -p "$PROBE_APP/Contents/MacOS" "$PROBE_HOME/Library/Preferences"
cp scripts/fixtures/smoke-preferences.plist "$PROBE_HOME/Library/Preferences/$PROBE_ID.plist"
plutil -create xml1 "$PROBE_APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "$PROBE_ID" "$PROBE_APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string MINT "$PROBE_APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$PROBE_APP/Contents/Info.plist"
swiftc scripts/fixtures/preferences-launch-probe.swift -o "$PROBE_APP/Contents/MacOS/MINT"
codesign --force -s - "$PROBE_APP"
for PROBE_MODE in read seed read; do
    open -n -W --env "CFFIXED_USER_HOME=$PROBE_HOME" --stdout "$PROBE_ROOT/$PROBE_MODE.log" --stderr "$PROBE_ROOT/$PROBE_MODE.err" "$PROBE_APP" --args "$PROBE_MODE"
    cat "$PROBE_ROOT/$PROBE_MODE.log" "$PROBE_ROOT/$PROBE_MODE.err"
done
ls -l "$PROBE_HOME/Library/Preferences/$PROBE_ID.plist"
if [ -f "$HOME/Library/Preferences/$PROBE_ID.plist" ]; then
    echo 'Preferences API wrote to the real home'
fi
test -f "$PROBE_HOME/probe-passed"
