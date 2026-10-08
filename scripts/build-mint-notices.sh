#!/bin/sh
# Audit the dependency sources used by this native Xcode build, before signing.
set -eu
NOTICE_DERIVED_ROOT="$BUILD_DIR"
while [ ! -d "$NOTICE_DERIVED_ROOT/SourcePackages/checkouts" ]; do
    if [ "$NOTICE_DERIVED_ROOT" = / ]; then
        echo "Cannot locate this Xcode build's dependency checkouts" >&2
        exit 1
    fi
    NOTICE_DERIVED_ROOT=$(dirname "$NOTICE_DERIVED_ROOT")
done
python3 "$SRCROOT/../scripts/mint-notices.py" \
    --checkouts "$NOTICE_DERIVED_ROOT/SourcePackages/checkouts" \
    --output "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
