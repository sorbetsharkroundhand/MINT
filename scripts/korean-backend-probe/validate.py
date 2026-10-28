#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys
import tarfile
import zipfile

from artifacts import ValidationError, load_manifest, verify_inputs


def main():
    parser = argparse.ArgumentParser(description="Validate the pinned Korean backend without launching Purlory")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check-inputs", action="store_true", help="Verify/extract inputs only; not the promotion gate")
    mode.add_argument("--probe", action="store_true")
    mode.add_argument("--verify", action="store_true")
    mode.add_argument("--fixtures", action="store_true", help="Real C-ABI fixtures only; not the promotion gate")
    mode.add_argument("--check-metrics", type=Path, help="Compare a recorded report with frozen metrics only")
    parser.add_argument("--manifest", type=Path, default=Path("Distribution/KoreanBackend/artifacts.json"))
    parser.add_argument("--artifacts-root", type=Path, default=Path("build/korean-backend-validation"))
    parser.add_argument("--output", type=Path, default=Path("build/korean-backend-verification"))
    parser.add_argument("--budgets", type=Path, default=Path("Distribution/KoreanBackend/budgets.json"))
    args = parser.parse_args()
    try:
        if args.check_inputs:
            print(json.dumps(verify_inputs(load_manifest(args.manifest), args.artifacts_root)))
        elif args.check_metrics:
            from budgets import compare
            compare(load_manifest(args.check_metrics), load_manifest(args.budgets))
            print("Recorded metrics meet frozen budgets; native execution was not repeated by this mode.")
        else:
            from probe import run
            run(args)
    except (ValidationError, OSError, ValueError, KeyError, TypeError, tarfile.TarError,
            zipfile.BadZipFile) as error:
        print("Korean backend validation failed: " + str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
