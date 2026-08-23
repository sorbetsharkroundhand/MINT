#!/bin/sh
# MINT.app 부팅 스모크 (이슈 #65 Gate 0 — 후속 PR의 공통 보호막).
#
# 검증하는 것: 번들이 metallib을 포함해 "앱으로" 뜨는가 · AppleScript 종료에
# 정상 종료하는가(세그폴트 없이). swift run과 다른 실행 경로(번들 식별자·
# Info.plist·LaunchServices)이므로 배포 형태에서만 보이는 초기화 크래시와
# teardown 크래시(#42 계열)를 PR마다 잡아준다.
# 검증하지 않는 것: 한글 IME·고스트 UX — 그것은 사람 손 스모크(AGENTS §6)다.
#
# 사용법:  scripts/smoke-mint-app.sh
set -u
cd "$(dirname "$0")/.."

APP="build/MINT.app"
BIN="$APP/Contents/MacOS/MINT"
BUNDLE_ID="app.mint.MINT"

[ -x "$BIN" ] || { echo "▸ 번들 없음 — 먼저 빌드합니다"; scripts/build-mint-app.sh; }

pkill -x MINT 2>/dev/null && sleep 1   # 이전 인스턴스 정리 — 판정 오염 방지

# 시작 시점 표식 — 이후 새로 생긴 MINT 크래시 리포트가 있으면 실패로 본다.
MARKER=$(mktemp)
touch "$MARKER"

echo "▸ 앱 실행 (open)…"
open "$APP" || { echo "✗ LaunchServices 실행 실패" >&2; exit 1; }

PID=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    PID=$(pgrep -x MINT | head -1)
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

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null

DEAD=""
for i in $(seq 1 30); do
    kill -0 "$PID" 2>/dev/null || { DEAD=1; break; }
    sleep 0.5
done
[ -n "$DEAD" ] || {
    echo "✗ 15초 내 미종료 — teardown 막힘. 강제 종료한다." >&2
    pkill -9 -x MINT
    exit 1
}
echo "✓ 정상 종료"

sleep 1  # 크래시 리포트가 써질 시간
NEW_CRASHES=$(find ~/Library/Logs/DiagnosticReports -name "MINT-*" -newer "$MARKER" 2>/dev/null | wc -l | tr -d ' ')
rm -f "$MARKER"
if [ "$NEW_CRASHES" != "0" ]; then
    echo "✗ 종료 중 크래시 리포트 $NEW_CRASHES건 생성 — teardown 세그폴트 의심" >&2
    find ~/Library/Logs/DiagnosticReports -name "MINT-*" -newer /dev/null 2>/dev/null | tail -3 >&2
    exit 1
fi

echo "✅ 스모크 통과 — 번들 실행 · 생존 · 정상 종료 · 무크래시"
