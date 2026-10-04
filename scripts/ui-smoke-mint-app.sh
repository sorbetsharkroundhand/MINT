#!/bin/sh
# 실제 사용자 앱과 원고를 건드리지 않는 project-owned editor UI 스모크 (#118).
# 먼저 scripts/build-mint-app.sh 실행. 손쉬운 사용 권한이 필요하다.
# 한글 marked text와 Ghost 상호작용은 이 자동화가 증명하지 않는다.
set -eu
cd "$(dirname "$0")/.."

verify_project_state() {
    library=$1
    expected_body=$2
    projects="$library/Projects"
    [ -d "$projects" ] && [ ! -L "$projects" ] || {
        echo "project state invalid: unsafe projects directory" >&2
        return 1
    }
    active_marker="$projects/active-project.json"
    [ -f "$active_marker" ] && [ ! -L "$active_marker" ] || {
        echo "project state invalid: active project marker missing" >&2
        return 1
    }
    project_id=$(plutil -extract rawValue raw -o - "$active_marker" 2>/dev/null) || {
        echo "project state invalid: active project marker unreadable" >&2
        return 1
    }
    case "$project_id" in
        *[!0-9A-Fa-f-]*|'')
            echo "project state invalid: unsafe project id" >&2
            return 1
            ;;
    esac
    project_directory="$projects/$project_id"
    [ -d "$project_directory" ] && [ ! -L "$project_directory" ] || {
        echo "project state invalid: unsafe project directory" >&2
        return 1
    }
    manifest="$project_directory/project.json"
    [ -f "$manifest" ] && [ ! -L "$manifest" ] || {
        echo "project state invalid: manifest missing" >&2
        return 1
    }
    manifest_id=$(plutil -extract id.rawValue raw -o - "$manifest" 2>/dev/null) || return 1
    [ "$manifest_id" = "$project_id" ] || {
        echo "project state invalid: active id does not match manifest" >&2
        return 1
    }
    document_count=$(plutil -extract documents raw -o - "$manifest" 2>/dev/null) || return 1
    [ "$document_count" -gt 0 ] 2>/dev/null || {
        echo "project state invalid: no documents" >&2
        return 1
    }

    found=""
    document_index=0
    while [ "$document_index" -lt "$document_count" ]; do
        document_id=$(plutil -extract "documents.$document_index.id.rawValue" raw -o - "$manifest" 2>/dev/null) || return 1
        document_kind=$(plutil -extract "documents.$document_index.kind" raw -o - "$manifest" 2>/dev/null) || return 1
        relative_path=$(plutil -extract "documents.$document_index.relativePath" raw -o - "$manifest" 2>/dev/null) || return 1
        expected_hash=$(plutil -extract "documents.$document_index.contentHash" raw -o - "$manifest" 2>/dev/null) || return 1
        case "$document_kind" in
            note) document_folder=Notes ;;
            manuscript|reference) document_folder=Documents ;;
            *)
                echo "project state invalid: unknown document kind" >&2
                return 1
                ;;
        esac
        canonical_document_id=$(printf '%s' "$document_id" | tr '[:lower:]' '[:upper:]')
        canonical_relative_path="$document_folder/$canonical_document_id/$expected_hash.md"
        [ "$relative_path" = "$canonical_relative_path" ] || {
            echo "project state invalid: noncanonical document path" >&2
            return 1
        }
        case "/$relative_path/" in
            //*|*/../*|*/./*)
                echo "project state invalid: unsafe document path" >&2
                return 1
                ;;
        esac
        content="$project_directory/$relative_path"
        [ -f "$content" ] && [ ! -L "$content" ] || {
            echo "project state invalid: referenced content missing" >&2
            return 1
        }
        resolved_parent=$(cd "$(dirname "$content")" && pwd -P) || return 1
        resolved_project=$(cd "$project_directory" && pwd -P) || return 1
        case "$resolved_parent/" in
            "$resolved_project"/*) ;;
            *)
                echo "project state invalid: content escaped project" >&2
                return 1
                ;;
        esac
        actual_hash=$(shasum -a 256 "$content" | awk '{print $1}') || return 1
        [ "$actual_hash" = "$expected_hash" ] || {
            echo "project state invalid: content hash mismatch" >&2
            return 1
        }
        if printf '%s' "$expected_body" | cmp -s - "$content"; then found=1; fi
        document_index=$((document_index + 1))
    done
    [ -n "$found" ] || {
        echo "project state invalid: expected body absent" >&2
        return 1
    }
    [ ! -e "$library/entries.json" ] && [ ! -L "$library/entries.json" ] || {
        echo "project state invalid: normal mode created entries.json" >&2
        return 1
    }
    echo "project state verified"
}

if [ "${1:-}" = "--verify-project-state" ]; then
    [ "$#" -eq 3 ] || {
        echo "usage: $0 --verify-project-state LIBRARY EXPECTED_BODY" >&2
        exit 64
    }
    verify_project_state "$2" "$3"
    exit
fi

if /usr/sbin/ioreg -n Root -d1 | /usr/bin/grep -q '"CGSSessionScreenIsLocked"=Yes'; then
    echo "UI smoke requires an unlocked macOS session; no UI verification performed." >&2
    exit 1
fi

SOURCE_APP="$PWD/build/MINT.app"
[ -x "$SOURCE_APP/Contents/MacOS/MINT" ] || {
    echo "✗ 먼저 앱 번들을 빌드하세요" >&2
    exit 1
}

REAL_ENTRIES="$HOME/Documents/MINT/entries.json"
REAL_ACTIVE="$HOME/Documents/MINT/Projects/active-project.json"
file_hash() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo absent
    fi
}
REAL_ENTRIES_HASH=$(file_hash "$REAL_ENTRIES")
REAL_ACTIVE_HASH=$(file_hash "$REAL_ACTIVE")

SMOKE_ROOT=$(mktemp -d /tmp/mint-ui-smoke.XXXXXX)
SMOKE_ROOT=$(cd "$SMOKE_ROOT" && pwd -P)
SMOKE_HOME="$SMOKE_ROOT/home"
APP="$SMOKE_ROOT/MINT.app"
SMOKE_EXECUTABLE="MINTUISmoke$(uuidgen | tr -d '-')"
BIN="$APP/Contents/MacOS/$SMOKE_EXECUTABLE"
PID=""
PASSED=""
SMOKE_BUNDLE_ID=""
PREFERENCES_OWNED=""

fail() { echo "✗ $1" >&2; exit 1; }
owned_pid() {
    [ -n "$PID" ] && [ "$(ps -p "$PID" -o comm= 2>/dev/null)" = "$BIN" ]
}
find_pid() {
    ps -axo pid=,comm= | awk -v bin="$BIN" '$2 == bin {print $1}'
}
check_original() {
    [ "$(file_hash "$REAL_ENTRIES")" = "$REAL_ENTRIES_HASH" ] \
        || fail "실제 entries.json 해시가 달라졌습니다"
    [ "$(file_hash "$REAL_ACTIVE")" = "$REAL_ACTIVE_HASH" ] \
        || fail "실제 활성 프로젝트 표식 해시가 달라졌습니다"
}
cleanup() {
    status=$?
    trap - 0
    [ -n "$PID" ] || PID=$(find_pid)
    if owned_pid; then kill -9 "$PID" 2>/dev/null || true; fi
    if [ -n "$PREFERENCES_OWNED" ]; then
        defaults delete "$SMOKE_BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    if [ "$(file_hash "$REAL_ENTRIES")" != "$REAL_ENTRIES_HASH" ] \
        || [ "$(file_hash "$REAL_ACTIVE")" != "$REAL_ACTIVE_HASH" ]; then
        echo "✗ 실제 사용자 저장소 해시가 달라졌습니다" >&2
        status=1
        PASSED=""
    fi
    if [ -n "$PASSED" ]; then
        rm -rf "$SMOKE_ROOT"
    else
        echo "▸ 실패 자료 보존: $SMOKE_ROOT" >&2
    fi
    exit "$status"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

mkdir -p "$SMOKE_HOME/Documents" "$SMOKE_HOME/Library/Logs/DiagnosticReports"
ditto "$SOURCE_APP" "$APP"
mv "$APP/Contents/MacOS/MINT" "$BIN"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")
SMOKE_BUNDLE_ID="$BUNDLE_ID.ui-smoke.$(uuidgen)"
if defaults read "$SMOKE_BUNDLE_ID" >/dev/null 2>&1; then
    fail "격리 설정 식별자가 이미 존재합니다"
fi
plutil -replace CFBundleIdentifier -string "$SMOKE_BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$SMOKE_EXECUTABLE" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$SMOKE_BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "$SMOKE_BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
PREFERENCES_OWNED=1
# Exercise the retired-tool fallback without preconfiguring a model or AI consent.
defaults write "$SMOKE_BUNDLE_ID" mint.sidebarSection -string margin

TOKEN="smoke$(uuidgen | tr -d '-')"
PROJECT_ID="33333333-3333-3333-3333-333333333333"
DOCUMENT_ID="44444444-4444-4444-4444-444444444444"
PROJECT_BODY="project-$TOKEN"
EDITED_BODY="edited-$TOKEN"
NEW_BODY="new-$TOKEN final"
PERSISTED_BODY="$EDITED_BODY$PROJECT_BODY"
WRITER_GENRE="FixtureGenre-$TOKEN"
WRITER_NAME="FixtureCharacter-$TOKEN"
WRITER_NOTE="FixtureNote-$TOKEN"
PROJECT_HASH=$(printf '%s' "$PROJECT_BODY" | shasum -a 256 | awk '{print $1}')
PROJECT_ROOT="$SMOKE_HOME/Documents/MINT/Projects"
PROJECT_DIRECTORY="$PROJECT_ROOT/$PROJECT_ID"
PROJECT_DOCUMENT_PATH="Documents/$DOCUMENT_ID/$PROJECT_HASH.md"
mkdir -p "$PROJECT_DIRECTORY/Documents/$DOCUMENT_ID"
printf '%s' "$PROJECT_BODY" > "$PROJECT_DIRECTORY/$PROJECT_DOCUMENT_PATH"
printf '%s' "{\"schemaVersion\":1,\"id\":{\"rawValue\":\"$PROJECT_ID\"},\"title\":\"Isolated Project\",\"mode\":\"fiction\",\"documents\":[{\"id\":{\"rawValue\":\"$DOCUMENT_ID\"},\"title\":\"Isolated Manuscript\",\"kind\":\"manuscript\",\"relativePath\":\"$PROJECT_DOCUMENT_PATH\",\"contentHash\":\"$PROJECT_HASH\"}],\"trashedDocumentIDs\":[],\"assets\":[]}" \
    > "$PROJECT_DIRECTORY/project.json"
printf '%s' "{\"rawValue\":\"$PROJECT_ID\"}" > "$PROJECT_ROOT/active-project.json"

cat > "$SMOKE_ROOT/ui.applescript" <<'AS'
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

on findElementContaining(rootElement, attributeName, expectedValue, remainingDepth)
    tell application "System Events"
        try
            if (value of attribute attributeName of rootElement as text) contains expectedValue then return rootElement
        end try
        if remainingDepth ≤ 0 then return missing value
        repeat with childElement in UI elements of rootElement
            set matchedElement to my findElementContaining(childElement, attributeName, expectedValue, remainingDepth - 1)
            if matchedElement is not missing value then return matchedElement
        end repeat
    end tell
    return missing value
end findElementContaining
on run argv
    set targetPID to (item 1 of argv) as integer
    set operation to item 2 of argv
    set expectedValue to item 3 of argv
    tell application "System Events"
        set targetProcess to first application process whose unix id is targetPID
        if unix id of targetProcess is not targetPID then error "Accessibility process resolved to another app"
        if not (exists window 1 of targetProcess) then error "메인 창 없음"
        set rootElement to window 1 of targetProcess
        if operation is "field-set" or operation is "field-equals" or operation is "field-absent" then
            set targetElement to my findElementContaining(rootElement, "AXIdentifier", expectedValue, 30)
            if operation is "field-absent" then
                if targetElement is not missing value then error "Unexpected writer field: " & expectedValue
            else
                if targetElement is missing value then error "Writer field missing: " & expectedValue
                set fieldValue to item 4 of argv
                if operation is "field-set" then
                    set frontmost of targetProcess to true
                    set value of attribute "AXFocused" of targetElement to true
                    tell targetProcess
                        keystroke "a" using command down
                        if fieldValue is "" then
                            key code 51
                        else
                            keystroke fieldValue
                        end if
                    end tell
                    delay 0.6
                else if (value of targetElement as text) is not fieldValue then
                    error "Writer field mismatch: " & expectedValue
                end if
            end if
        else if operation is "press" or operation is "present" or operation is "absent" then
            set targetElement to my findElement(rootElement, "AXIdentifier", expectedValue, 30)
            if targetElement is missing value then set targetElement to my findElement(rootElement, "AXDescription", expectedValue, 30)
            if targetElement is missing value then set targetElement to my findElement(rootElement, "AXTitle", expectedValue, 30)
            if targetElement is missing value then set targetElement to my findElementContaining(rootElement, "AXHelp", expectedValue, 30)
            if operation is "absent" then
                if targetElement is not missing value then error "숨겨야 할 컨트롤이 표시됨: " & expectedValue
            else
                if targetElement is missing value then error "필요한 컨트롤 없음: " & expectedValue
                if operation is "press" then click targetElement
            end if
        else if operation is "resize" then
            set size of rootElement to {expectedValue as integer, 700}
        else if operation is "autocomplete" then
            set autocompleteControl to my findElement(rootElement, "AXDescription", "자동완성", 30)
            -- Newer macOS versions expose SwiftUI labels as AXAttributedDescription.
            if autocompleteControl is missing value then set autocompleteControl to my findElementContaining(rootElement, "AXHelp", "자동완성 ·", 30)
            if autocompleteControl is missing value then error "자동완성 컨트롤 없음"
            if (value of attribute "AXValue" of autocompleteControl as text) is not "자동완성 꺼짐" then error "자동완성 접근성 상태 유실"
        else if operation is "navigator" then
            if my findElement(rootElement, "AXIdentifier", "mint.navigator", 30) is missing value then error "탐색기 없음"
        else if operation is "focused" then
            set editor to my findElement(rootElement, "AXIdentifier", "mint.editor", 30)
            if editor is missing value then error "에디터 없음"
            if not (value of attribute "AXFocused" of editor) then error "에디터 포커스 유실"

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
                delay 0.6
                -- Editing can replace the SwiftUI accessibility tree.
                set editor to my findElement(window 1 of targetProcess, "AXIdentifier", "mint.editor", 30)
                if editor is missing value then error "입력 후 에디터 없음"
                if not (value of attribute "AXFocused" of editor) then error "입력 후 에디터 포커스 유실"
            else if operation is "equals" then
                if (value of editor as text) is not expectedValue then error "에디터 본문 불일치"
            else if operation is "undo" or operation is "redo" then
                set frontmost of targetProcess to true
                set value of attribute "AXFocused" of editor to true
                if operation is "undo" then
                    tell targetProcess to keystroke "z" using command down
                else
                    tell targetProcess to keystroke "z" using {command down, shift down}
                end if
            else
                error "알 수 없는 UI 작업: " & operation
            end if
        end if
    end tell
end run
AS

launch() {
    check_original
    open -n --env "CFFIXED_USER_HOME=$SMOKE_HOME" \
        --env "HF_HOME=$SMOKE_HOME/ModelDownloads" "$APP"
    PID=""
    for _ in $(seq 1 15); do
        sleep 1
        PID=$(find_pid)
        [ -n "$PID" ] && break
    done
    owned_pid || fail "격리 앱 실행 실패"
    sleep 8
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
    for _ in $(seq 1 40); do
        kill -0 "$PID" 2>/dev/null || { PID=""; return; }
        sleep 0.5
    done
    fail "정상 종료 시간 초과"
}

ui() {
    owned_pid || fail "격리 실행 파일 PID 확인 실패"
    osascript "$SMOKE_ROOT/ui.applescript" "$PID" "$1" "${2:-}" "${3:-}" >/dev/null
    case "$1" in press|resize) sleep 0.3 ;; esac
}

wait_ui() {
    operation=$1
    expected=$2
    for _ in $(seq 1 40); do
        if osascript "$SMOKE_ROOT/ui.applescript" "$PID" "$operation" "$expected" >/dev/null 2>&1; then
            return
        fi
        sleep 0.25
    done
    ui "$operation" "$expected"
}

open_writer_information() {
    ui press "mint.writer-tools.compatibility"
    ui press "인물과 작품 정보"
}

assert_isolated_project_mode() {
    [ ! -e "$SMOKE_HOME/Documents/MINT/entries.json" ] \
        && [ ! -L "$SMOKE_HOME/Documents/MINT/entries.json" ] \
        || fail "정상 프로젝트 모드가 entries.json을 만들었습니다"
    [ ! -e "$SMOKE_HOME/ModelDownloads" ] \
        || fail "명시적 허가 없이 모델 다운로드 디렉터리가 생겼습니다"
}

launch
wait_ui equals "$PROJECT_BODY"
ui type "$EDITED_BODY"
wait_ui equals "$PERSISTED_BODY"
ui absent "mint.workspace-mode"
ui absent "리빙 마진"
ui absent "문서로 돌아가기"
ui absent "mint.ghost-shortcut-hint"
ui resize 1250
wait_ui autocomplete ""
ui press "파일 목록 숨기기"
ui press "파일 목록 보이기"
ui navigator
open_writer_information
ui field-set "mint.writer.genre" "$WRITER_GENRE"
ui press "mint.writer.add-character"
ui field-set "mint.writer.character.name." "$WRITER_NAME"
ui field-set "mint.writer.character.note." "$WRITER_NOTE"
ui press "문서로 돌아가기"
ui focused
ui resize 860
wait_ui autocomplete ""
open_writer_information
ui absent "리빙 마진"
ui press "문서로 돌아가기"
ui focused
ui navigator
ui press "새 문서"
wait_ui equals ""
ui type "$NEW_BODY"
wait_ui equals "$NEW_BODY"
ui undo ""
wait_ui equals "new-$TOKEN "
ui redo ""
wait_ui equals "$NEW_BODY"
open_writer_information
ui field-equals "mint.writer.genre" ""
ui field-absent "mint.writer.character.name."
ui press "문서로 돌아가기"
ui press "mint.document.$DOCUMENT_ID"
wait_ui equals "$PERSISTED_BODY"
# Address the generated document by its persisted identity, not a localized AX label.
NEW_DOCUMENT_ID=$(plutil -extract documents.1.id.rawValue raw -o - "$PROJECT_DIRECTORY/project.json") \
    || fail "새 문서 식별자 저장 실패"
ui press "mint.document.$NEW_DOCUMENT_ID"
wait_ui equals "$NEW_BODY"
terminate
verify_project_state "$SMOKE_HOME/Documents/MINT" "$PERSISTED_BODY" >/dev/null
verify_project_state "$SMOKE_HOME/Documents/MINT" "$NEW_BODY" >/dev/null
assert_isolated_project_mode

writer_record_path() {
    writer_key="writer-$(printf '%s' "$DOCUMENT_ID" | tr '[:upper:]' '[:lower:]')"
    relative=$(plutil -extract "userData.$writer_key.relativePath" raw -o - "$PROJECT_DIRECTORY/project.json") \
        || fail "Writer record missing from project manifest"
    case "$relative" in UserData/records/*/*.data) ;; *) fail "Writer record outside UserData" ;; esac
    printf '%s/%s' "$PROJECT_DIRECTORY" "$relative"
}
WRITER_RECORD=$(writer_record_path)
[ "$(plutil -extract genre raw -o - "$WRITER_RECORD")" = "$WRITER_GENRE" ] || fail "Writer genre was not persisted"
[ "$(plutil -extract characters.0.name raw -o - "$WRITER_RECORD")" = "$WRITER_NAME" ] || fail "Writer character was not persisted"
[ "$(plutil -extract characters.0.note raw -o - "$WRITER_RECORD")" = "$WRITER_NOTE" ] || fail "Writer note was not persisted"

launch
wait_ui equals "$NEW_BODY"
ui press "mint.document.$DOCUMENT_ID"
wait_ui equals "$PERSISTED_BODY"
open_writer_information
ui field-equals "mint.writer.genre" "$WRITER_GENRE"
ui field-equals "mint.writer.character.name." "$WRITER_NAME"
ui field-equals "mint.writer.character.note." "$WRITER_NOTE"
ui press "인물 삭제"
ui field-absent "mint.writer.character.name."
ui field-set "mint.writer.genre" ""
ui press "문서로 돌아가기"
ui focused
terminate
verify_project_state "$SMOKE_HOME/Documents/MINT" "$PERSISTED_BODY" >/dev/null
verify_project_state "$SMOKE_HOME/Documents/MINT" "$NEW_BODY" >/dev/null
assert_isolated_project_mode
check_original
WRITER_RECORD=$(writer_record_path)
if plutil -extract characters.0 json -o - "$WRITER_RECORD" >/dev/null 2>&1; then fail "Deleted character survived"; fi
if plutil -extract genre raw -o - "$WRITER_RECORD" >/dev/null 2>&1; then fail "Cleared genre survived"; fi

PASSED=1
echo "✓ UI 스모크 통과 — 문서 전환·생성 · 작가 설정 편집·삭제·재실행 · 포커스 복원 · manifest 검증"
