#!/bin/sh
# MINT.app 최소 번들 빌드 (이슈 #65 Gate 0).
#
# SwiftPM CLI 산출물은 그대로 실행하면 "Failed to load the default metallib"로
# 죽는다(AGENTS §0). prepare-metallib.sh가 실행 파일 옆에 mlx.metallib을 놓아주므로,
# 앱 번들도 같은 배치(Contents/MacOS/MINT + 같은 디렉터리의 mlx.metallib)면
# 추가 코드 없이 동작한다. xcodeproj 없이 Gate 0의 "앱 번들 스모크"를 가능하게
# 하는 것이 목적 — 서명·샌드박스·아이콘 같은 배포 요소는 이 스크립트의 범위가 아니다.
#
# 사용법:  scripts/build-mint-app.sh   → build/MINT.app
set -eu
cd "$(dirname "$0")/.."

# metallib은 mlx-swift 리비전에 묶여 있다 — 낡은 캐시 복사를 막으려면 항상 경유.
scripts/prepare-metallib.sh

echo "▸ 릴리즈 빌드…"
swift build -c release

REL=".build/arm64-apple-macosx/release"
APP="build/MINT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$REL/MINT" "$APP/Contents/MacOS/MINT"
cp "$REL/mlx.metallib" "$APP/Contents/MacOS/mlx.metallib"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>MINT</string>
    <key>CFBundleIdentifier</key>
    <string>app.mint.MINT</string>
    <key>CFBundleName</key>
    <string>MINT</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 로컬 실행용 애드혹 서명 — `open` 실행과 TCC 권한 대화의 엉킴을 줄인다.
codesign --force -s - "$APP" >/dev/null 2>&1 || echo "⚠ 애드혹 서명 실패 — 직접 실행에는 지장 없음" >&2

echo "✓ $APP"
