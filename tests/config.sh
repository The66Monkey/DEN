#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
read_settings "$ROOT/config/example.env"
[[ "$KEEPASS_ENABLED" == no ]]
[[ "$FLUXER_ENABLED" == no ]]
[[ "$QBITTORRENT_ENABLED" == no ]]
[[ "$MEDIA_MOUNT" == /mnt/den-storage ]]
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/deployment"
[[ "$(stat -c %a "$TEMP/deployment/.env")" == 600 ]]
[[ "$(stat -c %a "$TEMP/deployment")" == 700 ]]
[[ "$(stat -c %a "$TEMP/deployment/private/ddns.env")" == 600 ]]
grep -Fxq 'DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12' "$TEMP/deployment/private/ddns.env"
read_settings "$TEMP/deployment/.env"
[[ ${#DB_PASSWORD} == 48 && ${#RESTIC_PASSWORD} == 48 ]]
[[ "$KEEPASS_ENABLED" == no ]]
[[ "$FLUXER_ENABLED" == no ]]
[[ "$QBITTORRENT_ENABLED" == no ]]
[[ "$MEDIA_MOUNT" == /mnt/den-storage ]]
if (write_environment "$TEMP/deployment") 2>/dev/null; then exit 1; fi
for invalid in 'LAN_IP=192.168.1.999' 'LAN_IP=192.168.2.10' 'LAN_IP=192.168.1.0' 'LAN_CIDR=0.0.0.0/8' 'LAN_CIDR=192.168.1.1/24' 'DOMAIN=$(touch /tmp/den-injection)' 'BACKUP_MOUNT=/srv/den' 'MEDIA_MOUNT=/srv/den' 'MEDIA_MOUNT=/mnt/den-backup' 'MEDIA_MOUNT=/mnt/a/../b' 'MEDIA_MOUNT=/mnt/disk with spaces' 'KEEPASS_ENABLED=maybe' 'FLUXER_ENABLED=maybe' 'QBITTORRENT_ENABLED=maybe'; do
    if (printf -v "${invalid%%=*}" '%s' "${invalid#*=}"; validate_settings) 2>/dev/null; then
        fail "Accepted invalid setting: $invalid"
    fi
done
printf 'DOMAIN=home.example.net\nEMAIL=you@example.net\nLAN_IP=192.168.1.10\nLAN_CIDR=192.168.1.0/24\nBACKUP_MOUNT=/mnt/den-backup\nKEEPASS_ENABLED=yes\nFLUXER_ENABLED=yes\nQBITTORRENT_ENABLED=yes\n' > "$TEMP/keepass.env"
read_settings "$TEMP/keepass.env"
[[ -z "$MEDIA_MOUNT" ]]
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/keepass-deployment"
grep -Fxq 'KEEPASS_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'FLUXER_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'QBITTORRENT_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'MEDIA_MOUNT=' "$TEMP/keepass-deployment/.env"
grep -Fxq 'UPDATE_REPOSITORY=https://github.com/The66Monkey/DEN.git' "$TEMP/keepass-deployment/.env"
for invalid in 'file:///tmp/release.git' 'https://user:password@github.com/test/DEN.git' 'https://github.com/test/DEN.git;touch /tmp/den-injection'; do
    if (UPDATE_REPOSITORY="$invalid"; validate_settings) 2>/dev/null; then fail 'Invalid automatic update source accepted.'; fi
done
grep -v 'QBITTORRENT_ENABLED=' "$TEMP/keepass-deployment/.env" > "$TEMP/legacy.env"
read_settings "$TEMP/legacy.env"
[[ "$QBITTORRENT_ENABLED" == no ]]
for subnet in '10.44.0.0/24' '172.30.44.0/24'; do
    if (LAN_CIDR="$subnet"; LAN_IP="${subnet%0/*}10"; validate_settings) 2>/dev/null; then exit 1; fi
done
printf 'DOMAIN=home.example.net\nDOMAIN=other.example.net\n' > "$TEMP/duplicate.env"
if (read_settings "$TEMP/duplicate.env") 2>/dev/null; then exit 1; fi
printf 'UNKNOWN=value\n' > "$TEMP/unknown.env"
if (read_settings "$TEMP/unknown.env") 2>/dev/null; then exit 1; fi
printf 'Config and secret-generation checks passed.\n'