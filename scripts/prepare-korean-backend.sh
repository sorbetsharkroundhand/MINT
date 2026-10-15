#!/bin/sh
# Build-time only. Runtime proofreading never downloads resources.
set -eu
cd "$(dirname "$0")/.."
exec python3 scripts/korean-backend-probe/prepare.py "$@"
