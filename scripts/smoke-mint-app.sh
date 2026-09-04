#!/bin/sh
# MINT.app 부팅 스모크 (이슈 #65 Gate 0 — 후속 PR의 공통 보호막).
#
# 검증하는 것: 번들이 metallib을 포함해 "앱으로" 뜨는가 · 정상 종료 요청에
# 정상 종료하는가(세그폴트 없이). swift run과 다른 실행 경로(번들 식별자·
# Info.plist·LaunchServices)이므로 배포 형태에서만 보이는 초기화 크래시와
# teardown 크래시(#42 계열)를 PR마다 잡아준다.
# 검증하지 않는 것: 한글 IME·고스트 UX — 그것은 사람 손 스모크(AGENTS §6)다.
#
# 사용법:  scripts/smoke-mint-app.sh
set -eu
cd "$(dirname "$0")/.."

SOURCE_APP="$PWD/build/MINT.app"

[ -x "$SOURCE_APP/Contents/MacOS/MINT" ] || {
    echo "▸ 번들 없음 — 먼저 빌드합니다"
    scripts/build-mint-app.sh
}

# 고유 번들 경로와 홈으로 실행 소유권을 분리한다. 기존 앱·실제 원고를 건드리지 않는다.
SMOKE_ROOT=$(mktemp -d /tmp/mint-smoke.XXXXXX)
# macOS의 /tmp는 /private/tmp 심볼릭 링크다. ps가 보고하는 실제 경로와 맞춘다.
SMOKE_ROOT=$(cd "$SMOKE_ROOT" && pwd -P)
SMOKE_HOME="$SMOKE_ROOT/home"
APP="$SMOKE_ROOT/MINT.app"
BIN="$APP/Contents/MacOS/MINT"
PID=""
PASSED=""
cleanup() {
    # 실패 정리는 이 실행 파일의 PID에만 한정한다. 강제 종료는 통과로 세지 않는다.
    if [ -z "$PID" ]; then
        PID=$(ps -axo pid=,comm= | awk -v bin="$BIN" '$2 == bin { print $1 }')
    fi
    if [ -n "$PID" ] && [ "$(ps -p "$PID" -o comm= 2>/dev/null)" = "$BIN" ]; then
        # CI에서만 종료 실패의 스택·화면을 남긴다. 개인 Mac 화면은 수집하지 않는다.
        if [ -z "$PASSED" ] && [ "${GITHUB_ACTIONS:-}" = true ]; then
            DIAGNOSTICS="$PWD/build/smoke-diagnostics"
            mkdir -p "$DIAGNOSTICS"
            sample "$PID" 1 1 -file "$DIAGNOSTICS/MINT-sample.txt" || true
            screencapture -x "$DIAGNOSTICS/screen.png" || true
            ps -p "$PID" -o pid=,stat=,etime=,comm= > "$DIAGNOSTICS/process.txt" || true
        fi
        kill -9 "$PID" 2>/dev/null || true
    fi
    if [ -n "$PASSED" ]; then
        rm -rf "$SMOKE_ROOT"
    else
        echo "▸ 실패 진단 보존: $SMOKE_ROOT" >&2
    fi
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
mkdir -p "$SMOKE_HOME/Documents" "$SMOKE_HOME/Library/Logs/DiagnosticReports"
ditto "$SOURCE_APP" "$APP"

# 시작 시점 표식 — 이후 새로 생긴 MINT 크래시 리포트가 있으면 실패로 본다.
MARKER="$SMOKE_ROOT/started"
touch "$MARKER"

echo "▸ 격리 앱 실행 (open): $SMOKE_HOME"
open -n --env "CFFIXED_USER_HOME=$SMOKE_HOME" "$APP" || {
    echo "✗ LaunchServices 실행 실패" >&2
    exit 1
}

for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    PID=$(ps -axo pid=,comm= | awk -v bin="$BIN" '$2 == bin { print $1 }')
    [ -n "$PID" ] && break
done
[ -n "$PID" ] || { echo "✗ 프로세스가 뜨지 않았다" >&2; exit 1; }

# SwiftUI 첫 창 + EntryStore·백그라운드 인덱서 부팅까지 여유.
sleep 8
if ! kill -0 "$PID" 2>/dev/null; then
    echo "✗ 부팅 후 조기 종료 — 초기화 크래시" >&2
    exit 1
fi
echo "✓ 부팅 생존 (pid $PID)"

# 이름·번들 ID 대신 확인한 PID에 정상 종료를 요청한다. terminate는 앱이 거절할 수
# 있는 정상 종료 요청이며 forceTerminate가 아니다. 실제 소멸은 아래에서 따로 확인한다.
osascript -l JavaScript - "$PID" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
    const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(Number(argv[0]));
    if (!app.terminate) throw new Error('MINT 정상 종료 요청 거절');
}
JXA

DEAD=""
for i in $(seq 1 30); do
    kill -0 "$PID" 2>/dev/null || { DEAD=1; break; }
    sleep 0.5
done
[ -n "$DEAD" ] || {
    echo "✗ 15초 내 미종료 — teardown 막힘" >&2
    exit 1
}
echo "✓ 정상 종료"

[ -s "$SMOKE_HOME/Documents/MINT/entries.json" ] || {
    echo "✗ 격리 홈에 원고 저장이 확인되지 않았다" >&2
    exit 1
}

sleep 1  # 크래시 리포트가 써질 시간
# CrashReporter가 실제 사용자 또는 격리 홈에 쓰는 경우를 모두 검사한다.
CRASH_LIST="$SMOKE_ROOT/crashes"
for REPORTS in "$HOME/Library/Logs/DiagnosticReports" "$SMOKE_HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
    if [ -d "$REPORTS" ]; then
        find "$REPORTS" -name "MINT-*" -newer "$MARKER" >> "$CRASH_LIST"
    fi
done
NEW_CRASHES=$(wc -l < "$CRASH_LIST" | tr -d ' ')
if [ "$NEW_CRASHES" != "0" ]; then
    echo "✗ 종료 중 크래시 리포트 $NEW_CRASHES건 생성 — teardown 세그폴트 의심" >&2
    cat "$CRASH_LIST" >&2
    exit 1
fi

PASSED=1
echo "✅ 스모크 통과 — 격리 번들 실행 · 생존 · 정상 종료 · 무크래시"
