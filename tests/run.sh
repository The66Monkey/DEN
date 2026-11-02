#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for script in install.sh update.sh recover.sh bin/den bin/den-local lib/*.sh lib/hosts/*.sh templates/ddns-update.sh templates/profile.d/*.sh tests/*.sh; do
    bash -n "$script"
done
shellcheck --severity=warning -x -P "$ROOT" install.sh update.sh recover.sh bin/den bin/den-local lib/*.sh lib/hosts/*.sh templates/ddns-update.sh templates/profile.d/*.sh tests/*.sh
bash tests/config.sh
bash tests/storage.sh
bash tests/ddns.sh
bash tests/firewall.sh
bash tests/compose.sh
bash tests/homepage.sh
bash tests/qbittorrent.sh
bash tests/backup.sh
bash tests/restic.sh
if command -v unshare >/dev/null && unshare --user --map-root-user --mount true 2>/dev/null; then
    unshare --user --map-root-user --mount bash tests/storage-mounted.sh
else
    printf 'Isolated real bind-mount checks skipped: user/mount namespaces unavailable.\n'
fi
if command -v nft >/dev/null && unshare --user --map-root-user --mount --net true 2>/dev/null; then
    unshare --user --map-root-user --mount --net bash tests/firewall-network.sh
else
    printf 'Real network guard checks skipped: nftables or user/network namespaces unavailable.\n'
fi
bash tests/vpn.sh
bash tests/keepass.sh
bash tests/fluxer.sh
bash tests/update.sh
bash tests/automatic.sh
bash bin/den help >/dev/null
bash bin/den-local help >/dev/null
bash install.sh --help >/dev/null
printf 'All DEN automated checks passed. No live services were deployed.\n'