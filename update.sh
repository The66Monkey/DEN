#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# == 0 ]] || { printf 'Usage: sudo bash update.sh\n' >&2; exit 1; }
exec /usr/local/bin/den update "$ROOT"