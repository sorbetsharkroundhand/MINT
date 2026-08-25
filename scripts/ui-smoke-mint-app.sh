#!/bin/sh
# MINT.app UI 스모크 — 실제 창·메뉴·키보드 왕복 (이슈 #39).
#
# 부팅 스모크(smoke-mint-app.sh)가 "프로세스가 살아 있나"라면 이 스크립트는
# **사용자 경로**를 검증한다 — System Events(UI scripting)로:
#   1) 메인 윈도우 존재
#   2) 키보드 타이핑이 에디터에 반영되는지 (AX value 읽기)
#   3) 메뉴 바(파일 ▸ 새 저널) 명령 왕복
# XCUITest(xcodeproj 필요) 대신 접근성 API를 쓴 것 — SwiftPM 전용 저장소에서
# "실제 macOS UI 회귀"를 가능하게 하는 최소 장치다. VoiceOver 상태 판독과
# 한글 IME 조합은 사람 손 스모크(AGENTS §6)와 병행한다.
#
# 요구 사항: 이 터미널(또는 실행 주체)에 **손쉬운 사용 권한**이 부여되어야 한다.
#           미부여면 스크립트가 명확히 안내하고 실패한다 (조용한 오판 금지).
#
# 사용법:  scripts/ui-smoke-mint-app.sh
set -u
cd "$(dirname "$0")/.."

APP="build/MINT.app"
BIN="$APP/Contents/MacOS/MINT"
BUNDLE_ID="app.mint.MINT"

[ -x "$BIN" ] || { echo "▸ 번들 없음 — 먼저 빌드합니다"; scripts/build-mint-app.sh >/dev/null 2>&1 || scripts/build-mint-app.sh; }

pkill -x MINT 2>/dev/null && sleep 1

echo "▸ 앱 실행…"
open "$APP" || { echo "✗ LaunchServices 실행 실패" >&2; exit 1; }

PID=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    PID=$(pgrep -x MINT | head -1)
    [ -n "$PID" ] && break
done
[ -n "$PID" ] || { echo "✗ 프로세스가 뜨지 않았다" >&2; exit 1; }
sleep 6   # 첫 창·스토어 부팅 여유
echo "✓ 부팅 (pid $PID)"

fail() { echo "✗ $1" >&2; osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1; exit 1; }

# 1) 메인 윈도우 존재 — AX 트리 상단 확인.
osascript <<'AS' >/dev/null 2>&1 || fail "손쉬운 사용 권한 없음 — 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 손쉬운 사용에서 터미널을 허용하세요"
tell application "System Events"
    tell process "MINT"
        set w to window 1
    end tell
end tell
AS
echo "✓ 메인 윈도우 존재"

# 2) 키보드 입력 왕복 — 포커스를 에디터로, ASCII 타이핑, AX value로 검증.
#    (한글은 IME 조합 상태가 개입해 자동화 신뢰가 낮다 — AGENTS §6 수동 스모크 영역)
osascript <<'AS' >/dev/null 2>&1 || fail "키 입력 주입 실패"
tell application "System Events"
    tell process "MINT"
        set frontmost to true
        delay 0.5
        keystroke "ui smoke 123"
    end tell
end tell
AS
sleep 1
TYPED=$(osascript <<'AS' 2>/dev/null
tell application "System Events"
    tell process "MINT"
        set v to ""
        repeat with t in (text areas of scroll area 1 of splitter group 1 of window 1)
            set v to value of t
            if v contains "ui smoke 123" then return "FOUND"
        end repeat
        return "MISSING"
    end tell
end tell
AS
)
[ "$TYPED" = "FOUND" ] || fail "타이핑한 텍스트가 에디터 AX value에 없다 (입력 왕복 실패)"
echo "✓ 키보드 입력 → 에디터 반영"

# 3) 메뉴 명령 왕복 — 파일 ▸ 새 저널 (⌘N과 같은 경로).
osascript <<'AS' >/dev/null 2>&1 || fail "메뉴 명령 실패"
tell application "System Events"
    tell process "MINT"
        set frontmost to true
        click menu item "새 저널" of menu "파일" of menu bar item "파일" of menu bar 1
    end tell
end tell
AS
sleep 1
echo "✓ 메뉴 명령(새 저널) 왕복"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
for i in 1 2 3 4 5; do
    sleep 1
    kill -0 "$PID" 2>/dev/null || { echo "✓ 정상 종료 — UI 스모크 통과"; exit 0; }
done
echo "✗ 종료 실패" >&2
exit 1
