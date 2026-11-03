#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/state"
cat > "$TEMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *https://api.ipify.org* ]]; then
    printf '%s\n' "$DDNS_TEST_IP"
    exit 0
fi
printf '%s\n' "$*" >> "$DDNS_REQUEST_LOG"
cat > "$DDNS_CURL_CONFIG"
EOF
chmod +x "$TEMP/bin/curl"
export PATH="$TEMP/bin:$PATH"
export DDNS_REQUEST_LOG="$TEMP/request"
export DDNS_CURL_CONFIG="$TEMP/curl-config"
export DDNS_TEST_IP=188.66.61.106
export DOMAIN=scandinavianhacking.dedyn.io
export DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
export FLUXER_ENABLED=yes
export QBITTORRENT_ENABLED=yes
export AI_ENABLED=yes
STATE_FILE="$TEMP/state/last-ip"

bash "$ROOT/templates/ddns-update.sh" "$STATE_FILE"
grep -Fq 'hostname=vpn.scandinavianhacking.dedyn.io,home.scandinavianhacking.dedyn.io,media.scandinavianhacking.dedyn.io,photos.scandinavianhacking.dedyn.io,files.scandinavianhacking.dedyn.io,git.scandinavianhacking.dedyn.io,chat.scandinavianhacking.dedyn.io' "$DDNS_REQUEST_LOG"
grep -Fq ',downloads.scandinavianhacking.dedyn.io&myipv4=' "$DDNS_REQUEST_LOG"
! grep -Fq 'hostname=scandinavianhacking.dedyn.io' "$DDNS_REQUEST_LOG"
! grep -Fq "ai.$DOMAIN" "$DDNS_REQUEST_LOG"
! grep -Fq "dns.$DOMAIN" "$DDNS_REQUEST_LOG"
grep -Fxq 'header = "Authorization: Token abcdefghijklmnopqrstuvwxyz12"' "$DDNS_CURL_CONFIG"
[[ "$(head -1 "$STATE_FILE")" == "$DDNS_TEST_IP" ]]

rm -f "$DDNS_REQUEST_LOG"
bash "$ROOT/templates/ddns-update.sh" "$STATE_FILE" | grep -Fq 'unchanged'
[[ ! -e "$DDNS_REQUEST_LOG" ]]

printf '%s\n' "$DDNS_TEST_IP" > "$STATE_FILE"
bash "$ROOT/templates/ddns-update.sh" "$STATE_FILE"
grep -Fq 'hostname=vpn.' "$DDNS_REQUEST_LOG"

export FLUXER_ENABLED=no
export QBITTORRENT_ENABLED=no
: > "$DDNS_REQUEST_LOG"
bash "$ROOT/templates/ddns-update.sh" "$STATE_FILE"
! grep -Fq 'chat.scandinavianhacking.dedyn.io' "$DDNS_REQUEST_LOG"
! grep -Fq 'downloads.scandinavianhacking.dedyn.io' "$DDNS_REQUEST_LOG"
grep -Fq "myipv4=$DDNS_TEST_IP" "$DDNS_REQUEST_LOG"
[[ "$(head -1 "$STATE_FILE")" == "$DDNS_TEST_IP" ]]

export DDNS_TEST_IP=999.66.61.107
if bash "$ROOT/templates/ddns-update.sh" "$STATE_FILE" 2>/dev/null; then
    printf 'Accepted an invalid public IPv4 address.\n' >&2
    exit 1
fi
printf 'deSEC DDNS updater checks passed.\n'
