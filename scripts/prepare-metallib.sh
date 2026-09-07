#!/bin/sh
# `swift run MINT`용 mlx metallib 준비.
#
# SwiftPM CLI는 Metal 셰이더를 빌드하지 못한다(mlx-swift 공식 제약) —
# 그래서 `swift run` 산출물은 "Failed to load the default metallib"로 죽는다.
# mlx는 실행 파일과 같은 디렉터리의 `mlx.metallib`을 가장 먼저 찾으므로,
# xcodebuild가 만든 metallib을 .build 실행 디렉터리에 복사해 해결한다.
#
# mlx-swift 리비전이 바뀌면 캐시된 metallib은 낡은 것이다. 로컬 DerivedData와
# CI에서 복원 가능한 compact cache 모두 리비전 stamp로 검증한다.
#
# 사용법:  scripts/prepare-metallib.sh   (캐시 miss 시 xcodebuild가 돌아 수 분 소요)
set -eu
cd "$(dirname "$0")/.."

DD=".build/metallib-dd"
DD_STAMP="$DD/mlx-revision.stamp"
CACHE_DIR=".build/metallib-cache"
CACHE_LIB="$CACHE_DIR/default.metallib"
CACHE_STAMP="$CACHE_DIR/mlx-revision.stamp"

# 고정된 mlx-swift 리비전 (identity가 "mlx-swift"인 항목만 — "mlx-swift-lm" 제외).
MLX_REV=$(grep -A 5 '"identity" : "mlx-swift",' Package.resolved 2>/dev/null \
    | sed -n 's/.*"revision" : "\([0-9a-f]*\)".*/\1/p' | head -1 || true)

if [ -z "$MLX_REV" ]; then
    echo "⚠ Package.resolved에서 mlx-swift 리비전을 읽지 못했습니다 — 신선도 검사 없이 진행합니다." >&2
fi

is_fresh() {
    stamp_file="$1"
    [ -z "$MLX_REV" ] || [ "$(cat "$stamp_file" 2>/dev/null || true)" = "$MLX_REV" ]
}

LIB=""

# CI는 이 작은 디렉터리만 캐시한다. 거대한 xcodebuild DerivedData 전체를
# 저장하지 않아도 실제 런타임에 필요한 metallib만 재사용할 수 있다.
if [ -s "$CACHE_LIB" ] && is_fresh "$CACHE_STAMP"; then
    LIB="$CACHE_LIB"
    echo "✓ 캐시된 mlx.metallib 재사용"
fi

# 로컬 개발에서는 기존 DerivedData도 재사용한다.
if [ -z "$LIB" ]; then
    DD_LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" 2>/dev/null | head -1 || true)
    if [ -n "$DD_LIB" ] && is_fresh "$DD_STAMP"; then
        LIB="$DD_LIB"
    fi
fi

if [ -z "$LIB" ]; then
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo "✗ xcodebuild가 없습니다 — Metal 셰이더 빌드에는 전체 Xcode 설치가 필요합니다" >&2
        echo "  (Command Line Tools만으로는 부족). Xcode 설치 후 다시 실행하세요." >&2
        exit 1
    fi

    echo "▸ metallib 캐시 miss — xcodebuild 실행…"
    rm -rf "$DD"
    xcodebuild build -scheme MINT -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$DD" -quiet

    LIB=$(find "$DD" -name default.metallib -path "*Cmlx*" | head -1 || true)
    if [ -z "$LIB" ]; then
        echo "✗ metallib을 찾지 못했습니다 (xcodebuild 로그 확인 필요)" >&2
        exit 1
    fi

    if [ -n "$MLX_REV" ]; then
        printf '%s\n' "$MLX_REV" > "$DD_STAMP"
    fi
fi

# 유효한 metallib을 compact cache로 승격한다. GitHub Actions는 이 디렉터리만
# 저장하므로 다음 run에서는 xcodebuild 전체를 건너뛸 수 있다.
if [ "$LIB" != "$CACHE_LIB" ]; then
    mkdir -p "$CACHE_DIR"
    cp "$LIB" "$CACHE_LIB"
    if [ -n "$MLX_REV" ]; then
        printf '%s\n' "$MLX_REV" > "$CACHE_STAMP"
    fi
    LIB="$CACHE_LIB"
fi

if [ -z "$LIB" ] || [ ! -s "$LIB" ]; then
    echo "✗ 사용할 mlx.metallib이 없습니다" >&2
    exit 1
fi

for CONFIG in debug release; do
    BIN_DIR=".build/arm64-apple-macosx/$CONFIG"
    mkdir -p "$BIN_DIR"
    cp "$LIB" "$BIN_DIR/mlx.metallib"
    echo "✓ $BIN_DIR/mlx.metallib"
done

echo "완료 — 이제 swift run MINT 가 동작합니다."
