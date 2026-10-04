#!/bin/sh
# Exercise report-option refusal without model downloads, inference or user data.
set -eu
cd "$(dirname "$0")/.."
BENCH_BIN="${1:-.build/debug/MINTBench}"
[ -x "$BENCH_BIN" ] || { echo "Build MINTBench before CLI smoke" >&2; exit 1; }
BENCH_CLI_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mint-bench-cli.XXXXXX")
trap 'rm -rf "$BENCH_CLI_ROOT"' EXIT
mkdir "$BENCH_CLI_ROOT/home"
export CFFIXED_USER_HOME="$BENCH_CLI_ROOT/home"
export HF_HOME="$BENCH_CLI_ROOT/hf"
MODEL="mlx-community/Qwen2.5-1.5B-Instruct-4bit"
FIXTURE="Fixtures/replay-novel-ko-v1.txt"
"$BENCH_BIN" --help > "$BENCH_CLI_ROOT/help.log"
grep -F -- '--release-report' "$BENCH_CLI_ROOT/help.log" >/dev/null
grep -F -- '--candidate-memory-budget-bytes' "$BENCH_CLI_ROOT/help.log" >/dev/null
expect_failure() {
    if "$BENCH_BIN" "$@" > "$BENCH_CLI_ROOT/result.log" 2>&1; then
        echo "Invalid benchmark request succeeded: $*" >&2; exit 1
    fi
}
expect_failure --model unregistered/model --replay "$FIXTURE" --release-report "$BENCH_CLI_ROOT/new.json"
expect_failure --model "$MODEL" --release-report "$BENCH_CLI_ROOT/new.json"
expect_failure --model "$MODEL" --replay "$FIXTURE" --candidate-memory-budget-bytes 0
expect_failure --model "$MODEL" --replay "$FIXTURE" --release-report "$BENCH_CLI_ROOT/new.json" --cancellation-stress 1
printf '%s' preserve > "$BENCH_CLI_ROOT/existing.json"
expect_failure --model "$MODEL" --replay "$FIXTURE" --release-report "$BENCH_CLI_ROOT/existing.json" --candidate-memory-budget-bytes 2147483648
[ "$(cat "$BENCH_CLI_ROOT/existing.json")" = preserve ] || { echo "Existing data overwritten" >&2; exit 1; }
[ ! -e "$BENCH_CLI_ROOT/new.json" ] && [ ! -e "$HF_HOME" ] && [ ! -e "$CFFIXED_USER_HOME/Documents/MINT/Models" ] \
    || { echo "Refused request created report or model resources" >&2; exit 1; }
echo "Benchmark CLI smoke passed: help, preflight refusal, preserved output, no model download"
