#!/bin/sh
# `swift run MINT`용 mlx metallib 준비.
#
# SwiftPM CLI는 Metal 셰이더를 빌드하지 못한다(mlx-swift 공식 제약) —
# 그래서 `swift run` 산출물은 "Failed to load the default metallib"로 죽는다.
# mlx는 실행 파일과 같은 디렉터리의 `mlx.metallib`을 가장 먼저 찾으므로,
# xcodebuild가 만든 metallib을 .build 실행 디렉터리에 복사해 해결한다.
#
# mlx-swift 리비전이 바뀌면(패키지 업데이트) 캐시된 metallib은 낡은 것이다 —
# Package.resolved의 리비전을 스탬프로 남겨 두고, 달라지면 자동 재빌드한다.
# (예전엔 "버전 올리면 다시 실행"이라고 안내했지만, 재실행해도 find가 낡은
# 파일을 찾아 그대로 복사했다 — 커널 불일치로 조용히 깨질 수 있는 함정.)
#
# 사용법:  scripts/prepare-metallib.sh   (최초 1회는 xcodebuild가 돌아 수 분 소요)
set -eu
cd "$(dirname "$0")/.."

DD=".build/metallib-dd"
STAMP="$DD/mlx-revision.stamp"

# 고정된 mlx-swift 리비전 (identity가 "mlx-swift"인 항목만 — "mlx-swift-lm" 제외).
MLX_REV=$(grep -A 5 '"identity" : "mlx-swift",' Package.resolved 2>/dev/null \
    | sed -n 's/.*"revision" : "\([0-9a-f]*\)".*/\1/p' | head -1 || true)
CACHED_REV=$(cat "$STAMP" 2>/dev/null || true)

LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" 2>/dev/null | head -1 || true)

NEED_BUILD=""
if [ -z "$LIB" ]; then
    NEED_BUILD="metallib 최초 1회 빌드"
elif [ -n "$MLX_REV" ] && [ "$CACHED_REV" != "$MLX_REV" ]; then
    NEED_BUILD="mlx-swift 리비전 변경(${CACHED_REV:-기록 없음} → $MLX_REV) — metallib 재빌드"
fi
if [ -z "$MLX_REV" ]; then
    echo "⚠ Package.resolved에서 mlx-swift 리비전을 읽지 못했습니다 — 신선도 검사 없이 진행합니다." >&2
fi

if [ -n "$NEED_BUILD" ]; then
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "✗ xcodebuild가 없습니다 — Metal 셰이더 빌드에는 전체 Xcode 설치가 필요합니다" >&2
        echo "  (Command Line Tools만으로는 부족). Xcode 설치 후 다시 실행하세요." >&2
        exit 1
    fi
    echo "▸ $NEED_BUILD (xcodebuild)…"
    # 낡은 산출물을 먼저 비운다 — find가 옛 metallib을 다시 집지 않게.
    rm -rf "$DD"
    xcodebuild build -scheme MINT -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$DD" -quiet
    LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" | head -1 || true)
    if [ -n "$MLX_REV" ]; then
        printf '%s\n' "$MLX_REV" > "$STAMP"
    fi
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
