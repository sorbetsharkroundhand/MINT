#!/bin/sh
# 실제 사용자 앱과 원고를 건드리지 않는 작업공간 UI 스모크 (#103).
# 먼저 scripts/build-mint-app.sh 실행. 손쉬운 사용 권한이 필요하다.
# 한글 IME·고스트 지연은 자동 입력으로 검증하지 않는다 (AGENTS §6).
set -eu
cd "$(dirname "$0")/.."
SOURCE_APP="$PWD/build/MINT.app"
[ -x "$SOURCE_APP/Contents/MacOS/MINT" ] || { echo "✗ 먼저 앱 번들을 빌드하세요" >&2; exit 1; }
REAL_ENTRIES="$HOME/Documents/MINT/entries.json"
real_hash() {
    if [ -e "$REAL_ENTRIES" ] || [ -L "$REAL_ENTRIES" ]; then
        hash_result=$(shasum -a 256 "$REAL_ENTRIES") || return 1
        printf '%s\n' "$hash_result" | awk '{print $1}'
    else
        echo absent
    fi
}
REAL_HASH=$(real_hash)
SMOKE_ROOT=$(mktemp -d /tmp/mint-ui-smoke.XXXXXX)
SMOKE_ROOT=$(cd "$SMOKE_ROOT" && pwd -P)
SMOKE_HOME="$SMOKE_ROOT/home"
APP="$SMOKE_ROOT/MINT.app"
BIN="$APP/Contents/MacOS/MINT"
PID=""; PASSED=""; PREFERENCES_OWNED=""; SMOKE_BUNDLE_ID=""
fail() { echo "✗ $1" >&2; exit 1; }
owned_pid() { [ -n "$PID" ] && [ "$(ps -p "$PID" -o comm= 2>/dev/null)" = "$BIN" ]; }
find_pid() { ps -axo pid=,comm= | awk -v bin="$BIN" '$2 == bin {print $1}'; }
check_original() { [ "$(real_hash)" = "$REAL_HASH" ] || fail "실제 원고 해시가 달라졌습니다. 격리 검증 실패"; }
cleanup() {
    status=$?
    trap - 0
    [ -n "$PID" ] || PID=$(find_pid)
    if owned_pid; then kill -9 "$PID" 2>/dev/null || true; fi
    if [ -n "$PREFERENCES_OWNED" ]; then defaults delete "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true; fi
    if [ "$(real_hash)" != "$REAL_HASH" ]; then
        echo "✗ 실제 원고 해시가 달라졌습니다" >&2
        status=1; PASSED=""
    fi
    if [ -n "$PASSED" ]; then rm -rf "$SMOKE_ROOT"; else echo "▸ 실패 자료 보존: $SMOKE_ROOT" >&2; fi
    exit "$status"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
mkdir -p "$SMOKE_HOME/Documents/MINT"
ditto "$SOURCE_APP" "$APP"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")
SMOKE_BUNDLE_ID="$BUNDLE_ID.ui-smoke.$(uuidgen)"
if defaults read "$SMOKE_BUNDLE_ID" >/dev/null 2>&1; then fail "격리 설정 식별자가 이미 존재합니다"; fi
plutil -replace CFBundleIdentifier -string "$SMOKE_BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
PREFERENCES_OWNED=1
defaults import "$SMOKE_BUNDLE_ID" scripts/fixtures/smoke-preferences.plist
[ "$(defaults read "$SMOKE_BUNDLE_ID" mint.initialModelConfirmed)" = 1 ] || fail "격리 초기 설정 실패"
[ "$(defaults read "$SMOKE_BUNDLE_ID" completion.enabled)" = 0 ] || fail "모델 없는 집필 설정 실패"

# 고유 합성 원고가 실제 에디터에 나타나야 입력을 허용한다. 사용자 원고는 읽지 않는다.
TOKEN="smoke$(uuidgen | tr -d '-')"
cat > "$SMOKE_HOME/Documents/MINT/entries.json" <<JSON
{"entries":[{"id":"11111111-1111-1111-1111-111111111111","title":"격리 소설","createdAt":"2026-01-01T00:00:00Z","body":"$TOKEN","kind":"novel","titleIsCustom":true},{"id":"22222222-2222-2222-2222-222222222222","title":"격리 저널","createdAt":"2026-01-02T00:00:00Z","body":"second$TOKEN","titleIsCustom":true}],"activeID":"11111111-1111-1111-1111-111111111111"}
JSON
cat > "$SMOKE_ROOT/ui.applescript" <<'AS'
-- 고정된 뷰 계층 대신 접근성 식별자·레이블을 재귀 검색한다.
on findElement(rootElement, attributeName, expectedValue, remainingDepth)
    tell application "System Events"
        try
            if (value of attribute attributeName of rootElement) is expectedValue then return rootElement
        end try
        if remainingDepth ≤ 0 then return missing value
        repeat with childElement in UI elements of rootElement
            set matchedElement to my findElement(childElement, attributeName, expectedValue, remainingDepth - 1)
            if matchedElement is not missing value then return matchedElement
        end repeat
    end tell
    return missing value
end findElement
on run argv
    set targetPID to (item 1 of argv) as integer
    set operation to item 2 of argv
    set expectedValue to item 3 of argv
    tell application "System Events"
        set targetProcess to first application process whose unix id is targetPID
        if not (exists window 1 of targetProcess) then error "메인 창 없음"
        set rootElement to window 1 of targetProcess
        if operation is "press" then
            set targetElement to my findElement(rootElement, "AXDescription", expectedValue, 30)
            if targetElement is missing value then set targetElement to my findElement(rootElement, "AXTitle", expectedValue, 30)
            if targetElement is missing value then error "필요한 버튼 없음: " & expectedValue
            click targetElement
        else if operation is "navigator" then
            if my findElement(rootElement, "AXIdentifier", "mint.navigator", 30) is missing value then error "탐색기 없음"
        else if operation is "new" then
            click menu item "새 저널" of menu "파일" of menu bar item "파일" of menu bar 1 of targetProcess
        else
            set editor to my findElement(rootElement, "AXIdentifier", "mint.editor", 30)
            if editor is missing value then error "에디터 없음"
            if operation is "type" then
                set frontmost of targetProcess to true
                set value of attribute "AXFocused" of editor to true
                delay 0.2
                if not (frontmost of targetProcess) then error "격리 앱 포커스 없음"
                if not (value of attribute "AXFocused" of editor) then error "에디터 포커스 없음"
                tell targetProcess to keystroke expectedValue
                delay 0.5
                if not (value of attribute "AXFocused" of editor) then error "입력 후 에디터 포커스 유실"
            end if
            if operation is "empty" then
                if (value of editor as text) is not "" then error "새 저널이 비어 있지 않음"
            else if (value of editor as text) does not contain expectedValue then
                error "에디터 본문 검증 실패"
            end if
        end if
    end tell
end run
AS
ui() {
    owned_pid || fail "격리 실행 파일 PID 확인 실패"
    osascript "$SMOKE_ROOT/ui.applescript" "$PID" "$1" "${2:-}" >/dev/null
    case "$1" in press|new) sleep 0.3 ;; esac
}
launch() {
    check_original
    open -n --env "CFFIXED_USER_HOME=$SMOKE_HOME" "$APP"
    PID=""
    for i in $(seq 1 10); do
        sleep 1
        PID=$(find_pid)
        [ -n "$PID" ] && break
    done
    owned_pid || fail "격리 앱 실행 실패"
    sleep 3
    check_original
}
terminate() {
    owned_pid || fail "종료 대상 PID 확인 실패"
    osascript -l JavaScript - "$PID" <<'JXA' >/dev/null
ObjC.import('AppKit');
function run(argv) {
    const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(argv[0]));
    if (!app.terminate) throw new Error('정상 종료 요청 거절');
}
JXA
    for i in $(seq 1 30); do
        kill -0 "$PID" 2>/dev/null || { PID=""; return; }
        sleep 0.5
    done
    fail "정상 종료 시간 초과"
}
launch
ui verify "$TOKEN"
ui navigator
ui type "typed$TOKEN"
echo "✓ 격리 원고 확인 · 에디터 입력 왕복"
ui press "파일 목록 숨기기"
ui press "파일 목록 보이기"
ui navigator
ui press "스토리 바이블"
ui press "문서로 돌아가기"
ui navigator
ui press "저널 격리 저널"
ui verify "second$TOKEN"
ui press "소설 격리 소설"
ui verify "typed$TOKEN"
ui new
sleep 0.5
ui empty
ui type "new$TOKEN"
terminate
[ -s "$SMOKE_HOME/Documents/MINT/entries.json" ] || fail "격리 원고 저장 없음"
launch
ui verify "new$TOKEN"
ui press "소설 격리 소설"
ui verify "typed$TOKEN"
terminate
check_original
PASSED=1
echo "✓ UI 스모크 통과 — 탐색기 · 문서 전환 · 새 저널 · 재실행 보존 · 실제 원고 해시 불변"
