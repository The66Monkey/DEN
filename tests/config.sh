#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
printf 'abcdefghijklmnopqrstuvwxyz12\n' > "$TEMP/token"
chmod 600 "$TEMP/token"
DESEC_TOKEN_FILE="$TEMP/token"
request_ddns_token </dev/null
[[ "$DESEC_TOKEN" == abcdefghijklmnopqrstuvwxyz12 ]]
chmod 644 "$TEMP/token"
if (request_ddns_token </dev/null) 2>/dev/null; then fail 'Accepted a public token file.'; fi
chmod 600 "$TEMP/token"
ln -s "$TEMP/token" "$TEMP/token-link"
if (DESEC_TOKEN_FILE="$TEMP/token-link"; request_ddns_token </dev/null) 2>/dev/null; then fail 'Accepted a token symlink.'; fi
if (DESEC_TOKEN_FILE="$TEMP/missing"; request_ddns_token </dev/null) 2>/dev/null; then fail 'Accepted a missing token file.'; fi
printf 'invalid token\n' > "$TEMP/token"
if (request_ddns_token </dev/null) 2>/dev/null; then fail 'Accepted an invalid token file.'; fi
unset DESEC_TOKEN_FILE DESEC_TOKEN
if (request_ddns_token </dev/null) 2>/dev/null; then fail 'Accepted noninteractive install without a token file.'; fi
read_settings "$ROOT/config/example.env"
validate_hostname FedoraDEN
validate_hostname home-server
if validate_hostname '-den'; then fail 'Accepted a hostname starting with a hyphen.'; fi
if validate_hostname 'den-'; then fail 'Accepted a hostname ending with a hyphen.'; fi
if validate_hostname 'den server'; then fail 'Accepted a hostname containing spaces.'; fi
if validate_hostname 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl'; then
    fail 'Accepted a hostname longer than 63 characters.'
fi
request_server_hostname </dev/null
[[ "$SERVER_HOSTNAME" == "$(hostname -s)" ]]
[[ "$KEEPASS_ENABLED" == no ]]
[[ "$FLUXER_ENABLED" == no ]]
[[ "$QBITTORRENT_ENABLED" == no ]]
[[ "$QBITTORRENT_VPN_ENABLED" == no ]]
[[ "$MEDIA_MOUNT" == /mnt/den-storage ]]
[[ "$SECONDARY_CACHE_ENABLED" == yes ]]
[[ "$ACME_CHALLENGE" == http ]]
[[ "$ALLOW_SHARED_MEDIA_BACKUP" == no ]]
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
[[ "$SECONDARY_CACHE_ENABLED" == yes ]]
if (write_environment "$TEMP/deployment") 2>/dev/null; then exit 1; fi
for invalid in 'LAN_IP=192.168.1.999' 'LAN_IP=192.168.2.10' 'LAN_IP=192.168.1.0' 'LAN_CIDR=0.0.0.0/8' 'LAN_CIDR=192.168.1.1/24' 'DOMAIN=$(touch /tmp/den-injection)' 'BACKUP_MOUNT=/srv/den' 'MEDIA_MOUNT=/srv/den' 'MEDIA_MOUNT=/mnt/den-backup' 'MEDIA_MOUNT=/mnt/a/../b' 'MEDIA_MOUNT=/mnt/disk with spaces' 'KEEPASS_ENABLED=maybe' 'FLUXER_ENABLED=maybe' 'QBITTORRENT_ENABLED=maybe' 'QBITTORRENT_VPN_ENABLED=maybe'; do
    if (printf -v "${invalid%%=*}" '%s' "${invalid#*=}"; validate_settings) 2>/dev/null; then
        fail "Accepted invalid setting: $invalid"
    fi
done
if (ALLOW_SHARED_MEDIA_BACKUP=maybe; validate_settings) 2>/dev/null; then fail 'Accepted an invalid shared-storage flag.'; fi
if (SECONDARY_CACHE_ENABLED=maybe; validate_settings) 2>/dev/null; then fail 'Accepted an invalid secondary-cache flag.'; fi
(MEDIA_MOUNT="$BACKUP_MOUNT"; ALLOW_SHARED_MEDIA_BACKUP=yes; validate_settings)
ALLOW_SHARED_MEDIA_BACKUP=yes
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/shared-deployment"
read_settings "$TEMP/shared-deployment/.env"
[[ "$ALLOW_SHARED_MEDIA_BACKUP" == yes ]]
printf 'DOMAIN=home.example.net\nEMAIL=you@example.net\nLAN_IP=192.168.1.10\nLAN_CIDR=192.168.1.0/24\nBACKUP_MOUNT=/mnt/den-backup\nKEEPASS_ENABLED=yes\nFLUXER_ENABLED=yes\nQBITTORRENT_ENABLED=yes\n' > "$TEMP/keepass.env"
read_settings "$TEMP/keepass.env"
[[ -z "$MEDIA_MOUNT" ]]
[[ "$SECONDARY_CACHE_ENABLED" == no ]]
[[ "$ALLOW_SHARED_MEDIA_BACKUP" == no ]]
[[ "$QBITTORRENT_VPN_ENABLED" == no ]]
if (QBITTORRENT_ENABLED=no; QBITTORRENT_VPN_ENABLED=yes; validate_settings) 2>/dev/null; then
    fail 'Accepted torrent VPN without qBittorrent.'
fi
QBITTORRENT_VPN_ENABLED=yes
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/keepass-deployment"
grep -Fxq 'KEEPASS_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'FLUXER_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'QBITTORRENT_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'QBITTORRENT_VPN_ENABLED=yes' "$TEMP/keepass-deployment/.env"
grep -Fxq 'MEDIA_MOUNT=' "$TEMP/keepass-deployment/.env"
grep -Fxq 'UPDATE_REPOSITORY=https://github.com/The66Monkey/DEN.git' "$TEMP/keepass-deployment/.env"
for invalid in 'file:///tmp/release.git' 'https://user:password@github.com/test/DEN.git' 'https://github.com/test/DEN.git;touch /tmp/den-injection'; do
    if (UPDATE_REPOSITORY="$invalid"; validate_settings) 2>/dev/null; then fail 'Invalid automatic update source accepted.'; fi
done
grep -Ev '^QBITTORRENT(_VPN)?_ENABLED=' "$TEMP/keepass-deployment/.env" > "$TEMP/legacy.env"
read_settings "$TEMP/legacy.env"
[[ "$QBITTORRENT_ENABLED" == no ]]
[[ "$ACME_CHALLENGE" == http ]]
ACME_CHALLENGE=dns-desec
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/dns-deployment"
[[ "$(stat -c %a "$TEMP/dns-deployment/private/desec-token")" == 600 ]]
grep -Fxq "$DESEC_TOKEN" "$TEMP/dns-deployment/private/desec-token"
read_settings "$TEMP/dns-deployment/.env"
[[ "$ACME_CHALLENGE" == dns-desec ]]
if (ACME_CHALLENGE=invalid; validate_settings) 2>/dev/null; then fail 'Accepted an invalid ACME challenge.'; fi
for subnet in '10.44.0.0/24' '172.30.44.0/24'; do
    if (LAN_CIDR="$subnet"; LAN_IP="${subnet%0/*}10"; validate_settings) 2>/dev/null; then exit 1; fi
done
printf 'DOMAIN=home.example.net\nDOMAIN=other.example.net\n' > "$TEMP/duplicate.env"
if (read_settings "$TEMP/duplicate.env") 2>/dev/null; then exit 1; fi
printf 'UNKNOWN=value\n' > "$TEMP/unknown.env"
if (read_settings "$TEMP/unknown.env") 2>/dev/null; then exit 1; fi
printf 'Config and secret-generation checks passed.\n'