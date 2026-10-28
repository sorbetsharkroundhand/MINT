#!/bin/sh
# Isolated backend validation; never launches Purlory or modifies the user's model cache.
set -eu
cd "$(dirname "$0")/.."
exec python3 scripts/korean-backend-probe/validate.py "$@"
