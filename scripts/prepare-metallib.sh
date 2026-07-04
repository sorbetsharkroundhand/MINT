#!/bin/sh
# `swift run MINT`용 mlx metallib 준비.
#
# SwiftPM CLI는 Metal 셰이더를 빌드하지 못한다(mlx-swift 공식 제약) —
# 그래서 `swift run` 산출물은 "Failed to load the default metallib"로 죽는다.
# mlx는 실행 파일과 같은 디렉터리의 `mlx.metallib`을 가장 먼저 찾으므로,
# xcodebuild가 만든 metallib을 .build 실행 디렉터리에 복사해 해결한다.
#
# 사용법:  scripts/prepare-metallib.sh   (최초 1회는 xcodebuild가 돌아 수 분 소요)
set -e
cd "$(dirname "$0")/.."

DD=".build/metallib-dd"
LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" 2>/dev/null | head -1)
if [ -z "$LIB" ]; then
    echo "▸ metallib 최초 1회 빌드 중 (xcodebuild)…"
    xcodebuild build -scheme MINT -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$DD" -quiet
    LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" | head -1)
fi
if [ -z "$LIB" ]; then
    echo "✗ metallib을 찾지 못했습니다 (xcodebuild 로그 확인 필요)" >&2
    exit 1
fi

for CONFIG in debug release; do
    BIN_DIR=".build/arm64-apple-macosx/$CONFIG"
    mkdir -p "$BIN_DIR"
    cp "$LIB" "$BIN_DIR/mlx.metallib"
    echo "✓ $BIN_DIR/mlx.metallib"
done
echo "완료 — 이제 swift run MINT 가 동작합니다."
