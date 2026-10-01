#!/bin/sh
# Exercise MLX initialization and recoverable resource errors in copies of the native archive.
set -eu
cd "$(dirname "$0")/.."
CASES="valid missing corrupt"
if [ "${1:-}" = --resource-errors-only ]; then
    CASES="missing empty"
    shift
fi
[ "$#" -le 1 ] || { echo "Usage: $0 [--resource-errors-only] [archive]" >&2; exit 1; }
SOURCE_APP="${1:-build/MINT.xcarchive}/Products/Applications/MINT.app"
[ -x "$SOURCE_APP/Contents/MacOS/MINT" ] || { echo "Native archive missing" >&2; exit 1; }
MLX_SMOKE_ROOT=$(mktemp -d "$HOME/.mint-sandbox-mlx.XXXXXX")
MLX_CONTAINERS=""
MLX_PID=""
MLX_BINARY=""
fail() { echo "Sandbox MLX verification failed: $*" >&2; exit 1; }
owned_pid() { [ -n "$MLX_PID" ] && [ "$(ps -p "$MLX_PID" -o comm= 2>/dev/null)" = "$MLX_BINARY" ]; }
cleanup() {
    if [ -z "$MLX_PID" ] && [ -n "$MLX_BINARY" ]; then
        MLX_PID=$(ps -axo pid=,comm= | awk -v bin="$MLX_BINARY" '$2 == bin {print $1}')
    fi
    if owned_pid; then kill -9 "$MLX_PID" 2>/dev/null || true; fi
    rm -rf "$MLX_SMOKE_ROOT"
    for ID in $MLX_CONTAINERS; do
        CONTAINER="$HOME/Library/Containers/$ID"
        rm -rf "$CONTAINER/Data"
        METADATA="$CONTAINER/.com.apple.containermanagerd.metadata.plist"
        rm -f "$METADATA" 2>/dev/null || true
        if ! rmdir "$CONTAINER" 2>/dev/null; then
            [ -f "$METADATA" ] && [ -z "$(find "$CONTAINER" -mindepth 1 ! -name .com.apple.containermanagerd.metadata.plist -print -quit)" ] \
                || fail "test data remains after cleanup"
        fi
    done
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

for CASE in $CASES; do
    ID="app.mint.mlx-smoke.$(uuidgen | tr '[:upper:]' '[:lower:]')"
    CONTAINER="$HOME/Library/Containers/$ID"
    [ ! -e "$CONTAINER" ] || fail "container collision"
    mkdir "$CONTAINER"
    MLX_CONTAINERS="$MLX_CONTAINERS $ID"
    PROBE_HOME="$CONTAINER/Data"
    mkdir -p "$PROBE_HOME/Documents"
    APP="$MLX_SMOKE_ROOT/$CASE.app"
    ditto "$SOURCE_APP" "$APP"
    EXECUTABLE="MINTMetalSmoke$(uuidgen | tr -d '-')"
    MLX_BINARY="$APP/Contents/MacOS/$EXECUTABLE"
    mv "$APP/Contents/MacOS/MINT" "$MLX_BINARY"
    plutil -replace CFBundleIdentifier -string "$ID" "$APP/Contents/Info.plist"
    plutil -replace CFBundleExecutable -string "$EXECUTABLE" "$APP/Contents/Info.plist"
    LIBRARY="$APP/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
    [ -s "$LIBRARY" ] || fail "packaged Cmlx library missing"
    case "$CASE" in
        missing) rm "$LIBRARY" ;;
        empty) : > "$LIBRARY" ;;
        corrupt) printf '%s' 'corrupt metallib fixture' > "$LIBRARY" ;;
    esac
    codesign --force --deep --sign - --entitlements Distribution/MINT.entitlements "$APP"
    codesign --verify --deep --strict "$APP"
    codesign --display --entitlements :- "$APP" > "$MLX_SMOKE_ROOT/effective.plist" 2>/dev/null
    [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$MLX_SMOKE_ROOT/effective.plist")" = true ] \
        || fail "sandbox entitlement ineffective"
    open -n --env "CFFIXED_USER_HOME=$PROBE_HOME" \
        --env "HF_HOME=$PROBE_HOME/ModelDownloads" --env MINT_VERIFY_MLX_RESOURCES=1 "$APP"
    RESULT="$PROBE_HOME/Documents/MINT/mlx-runtime-verification.txt"
    ATTEMPT=0
    while [ ! -f "$RESULT" ] && [ "$ATTEMPT" -lt "${MINT_MLX_PROBE_TIMEOUT:-30}" ]; do
        sleep 1
        ATTEMPT=$((ATTEMPT + 1))
    done
    MLX_PID=$(ps -axo pid=,comm= | awk -v bin="$MLX_BINARY" '$2 == bin {print $1}')
    [ -f "$RESULT" ] || fail "$CASE produced no diagnostic result"
    cat "$RESULT"
    if [ "$CASE" = valid ]; then
        [ "$(head -n 1 "$RESULT")" = PASS ] || fail "GPU initialization failed"
        grep -F "$APP/Contents/Resources/" "$RESULT" >/dev/null || fail "library came from outside the app"
    else
        [ "$(head -n 1 "$RESULT")" = FAIL ] || fail "$CASE resource accepted"
        grep -F '다시 설치' "$RESULT" >/dev/null || fail "$CASE did not identify a resource error"
        grep -F '원고 편집은 계속할 수 있습니다' "$RESULT" >/dev/null || fail "resource error was not actionable"
    fi
    sleep 1
    owned_pid || fail "$CASE broke the editor process"
    [ ! -e "$PROBE_HOME/ModelDownloads" ] || fail "probe downloaded a model"
    osascript -l JavaScript - "$MLX_PID" <<'JXA' >/dev/null
ObjC.import('AppKit');
function run(argv) {
    const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(argv[0]));
    if (!app.terminate) throw new Error('Normal termination rejected');
}
JXA
    ATTEMPT=0
    while kill -0 "$MLX_PID" 2>/dev/null && [ "$ATTEMPT" -lt 30 ]; do
        sleep 0.5
        ATTEMPT=$((ATTEMPT + 1))
    done
    kill -0 "$MLX_PID" 2>/dev/null && fail "$CASE did not terminate normally"
    MLX_PID=""
    echo "Verified sandboxed native archive: $CASE resources, editor survives, no model download"
done
if [ "$CASES" = "missing empty" ]; then
    echo "Resource-error checks only; GPU initialization requires the default smoke on a Metal-capable Mac"
fi
echo "Sandbox MLX verification passed; all owned fixture data will be removed"
