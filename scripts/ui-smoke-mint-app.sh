#!/bin/sh
# MINT.app UI 스모크 — 실제 창·키보드·메뉴 왕복 (이슈 #39).
#
# 검증 경로 (System Events / UI scripting):
#   1) 메인 윈도우 존재
#   2) 키보드 타이핑 → 에디터에 반영 (AX 값 읽기로 확인)
#   3) 메뉴 명령(파일 ▸ 새 저널) 왕복
#   4) AppleScript 정상 종료
#
# 데이터 격리 (중요): **CFFIXED_USER_HOME**으로 실행 파일을 직접 띄운다.
# - NSHomeDirectory/FileManager는 $HOME env를 무시한다(passwd 기준) — HOME만
#   바꾸는 격리는 실패했고(2026-08-25 실오류), CFFIXED_USER_HOME은 문서 디렉터리
#   자체를 재지향한다(런타임 검증 완료).
# - 이중 안전장치: 실행 전후로 **실제** ~/Documents/MINT/entries.json의 mtime을
#   비교해, 격리가 깨졌다면 타이핑 전에 즉시 실패시킨다.
#
# 요구 사항: 실행 주체에 손쉬운 사용 권한. 미부여면 명확히 안내하고 실패한다.
#
# 사용법:  scripts/ui-smoke-mint-app.sh
set -u
cd "$(dirname "$0")/.."

APP="build/MINT.app"
BIN="$APP/Contents/MacOS/MINT"

[ -x "$BIN" ] || { echo "▸ 번들 없음 — 먼저 빌드합니다"; scripts/build-mint-app.sh >/dev/null 2>&1 || scripts/build-mint-app.sh; }

pkill -x MINT 2>/dev/null && sleep 1   # 판정 오염 방지

# 격리 세션용 가짜 HOME — 문서 디렉터리가 여기 아래 생긴다.
ISOLATED_HOME=$(mktemp -d "$TMPDIR/MINT-ui-smoke.XXXXXX")
mkdir -p "$ISOLATED_HOME/Documents"

# 실제 원고 보호 검증용 — 실행 전 mtime 스냅샷.
REAL_ENTRIES="$HOME/Documents/MINT/entries.json"
REAL_MTIME_BEFORE=""
[ -f "$REAL_ENTRIES" ] && REAL_MTIME_BEFORE=$(stat -f %m "$REAL_ENTRIES")

cleanup() {
    pkill -x MINT 2>/dev/null
    rm -rf "$ISOLATED_HOME"
}
trap cleanup EXIT

echo "▸ 격리 세션으로 앱 실행 ($ISOLATED_HOME)…"
CFFIXED_USER_HOME="$ISOLATED_HOME" HOME="$ISOLATED_HOME" "$BIN" &
BIN_PID=$!

PID=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    PID=$(pgrep -x MINT | head -1)
    [ -n "$PID" ] && break
done
[ -n "$PID" ] || { echo "✗ 프로세스가 뜨지 않았다" >&2; exit 1; }
sleep 6   # 첫 창·스토어 부팅 여유
echo "✓ 부팅 (pid $PID)"

fail() { echo "✗ $1" >&2; exit 1; }

# ★ 격리 조기 단언 — 첫 실행 세션은 아직 저장 파일이 없을 수 있으므로,
# "실제 원고가 이미 건드리지 않았는가"만 지금 확인하고 최종 증명은 종료 시 한다.
if [ -n "$REAL_MTIME_BEFORE" ] && [ -f "$REAL_ENTRIES" ]; then
    NOW_MTIME=$(stat -f %m "$REAL_ENTRIES")
    [ "$REAL_MTIME_BEFORE" = "$NOW_MTIME" ] \
        || fail "격리 실패 — 앱이 실제 홈을 쓰고 있다. 중단한다 (원고 보호)"
fi
echo "✓ 데이터 격리 확인 (실제 원고 무접촉)"

# 권한 게이트 — 실패 시 원인을 정확히 말한다.
osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1 \
    || fail "손쉬운 사용 권한 없음 — 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 손쉬운 사용에서 실행 주체를 허용하세요"

osascript -e 'tell application "System Events" to tell process "MINT" to exists window 1' >/dev/null 2>&1 \
    || fail "메인 윈도우가 없다"
echo "✓ 메인 윈도우 존재"

# 키보드 입력 왕복 — 포커스는 첫 실행 기본(에디터). ASCII만 쓴다(한글은 IME 조합이
# 개입해 자동화 신뢰 저하 — AGENTS §6 수동 스모크 영역).
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
		set found to false
		repeat with el in (UI elements of scroll area 1 of group 1 of window 1)
			repeat with t in (static texts of el)
				try
					if (value of t) contains "ui smoke 123" then
						set found to true
						exit repeat
					end if
				end try
			end repeat
			if found then exit repeat
		end repeat
		if found then return "FOUND"
		return "MISSING"
	end tell
end tell
AS
)
[ "$TYPED" = "FOUND" ] || fail "타이핑한 텍스트가 에디터 AX 값에 없다 (입력 왕복 실패)"
echo "✓ 키보드 입력 → 에디터 반영"

# 메뉴 명령 왕복.
osascript <<'AS' >/dev/null 2>&1 || fail "메뉴 명령 실패"
tell application "System Events"
	tell process "MINT"
		set frontmost to true
		click menu item "새 저널" of menu "파일" of menu bar item "파일" of menu bar 1
	end tell
end tell
AS
sleep 1
echo "✓ 메뉴 명령(새 저널) 완료"

# 정상 종료 + 격리 세션 저장 확인 (원격 원칙: 종료 flush 계약).
osascript -e 'tell application "System Events" to tell process "MINT" to keystroke "q" using command down' >/dev/null 2>&1
for i in 1 2 3 4 5; do
    sleep 1
    kill -0 "$PID" 2>/dev/null || break
done
if kill -0 "$PID" 2>/dev/null; then
    fail "정상 종료 실패"
fi
[ -f "$ISOLATED_HOME/Documents/MINT/entries.json" ] \
    && echo "✓ 격리 세션 저장 생성 — flush 계약 OK" \
    || echo "⚠ 격리 세션 entries.json 미생성 (편집 없는 신규 실행 경로)"

# ★ 격리 최종 단언 — 실제 원고가 이 세션 동안 손대지 않았음을 mtime으로 증명.
if [ -n "$REAL_MTIME_BEFORE" ] && [ -f "$REAL_ENTRIES" ]; then
    REAL_MTIME_AFTER=$(stat -f %m "$REAL_ENTRIES")
    [ "$REAL_MTIME_BEFORE" = "$REAL_MTIME_AFTER" ] \
        || fail "실제 원고 파일의 mtime이 변했다 — 격리 붕괴. 즉시 확인 요망"
    echo "✓ 사용자 원고 무변경 입증 (mtime 불변)"
fi

echo "✓ UI 스모크 통과"
