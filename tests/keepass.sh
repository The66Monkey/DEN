#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! python3 -c 'import pykeepass' >/dev/null 2>&1; then
    printf 'KeePass integration test skipped; install python3-pykeepass to run it.\n'
    exit 0
fi
python3 "$ROOT/tests/keepass.py"
printf 'KeePass vault permissions, entries, attachments and sync checks passed.\n'