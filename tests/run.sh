#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for script in install.sh update.sh recover.sh bin/den lib/*.sh lib/hosts/*.sh tests/*.sh; do
    bash -n "$script"
done
shellcheck --severity=warning -x -P "$ROOT" install.sh update.sh recover.sh bin/den lib/*.sh lib/hosts/*.sh tests/*.sh
bash tests/config.sh
bash tests/compose.sh
bash tests/backup.sh
bash tests/restic.sh
bash tests/vpn.sh
bash tests/keepass.sh
bash tests/fluxer.sh
bash tests/update.sh
bash bin/den help >/dev/null
bash install.sh --help >/dev/null
printf 'All DEN automated checks passed. No live services were deployed.\n'