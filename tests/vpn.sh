#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
read_settings "$ROOT/config/example.env"
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$DEPLOY_DIR"
CALLS="$TEMP/calls"
wg() {
    case "$1" in
        genkey) openssl rand -base64 32 ;;
        pubkey) tr -d '\n' | openssl dgst -sha256 -r | cut -d ' ' -f 1 ;;
        show) awk '$1 == "PrivateKey" {print $3}' "$DEPLOY_DIR/private/wg0.conf" | wg pubkey ;;
        set) printf '%s\n' "$*" >> "$CALLS" ;;
        *) fail 'Unexpected mocked wg command.' ;;
    esac
}
install() { cp "$3" "$TEMP/installed-wg0.conf"; }
write_vpn
grep -Fq 'AllowedIPs = 10.44.0.2/32' "$DEPLOY_DIR/private/wg0.conf"
grep -Fq 'Endpoint = home.home.example.net:41873' "$DEPLOY_DIR/private/home.conf"
vpn_add phone >/dev/null
grep -Fq 'Address = 10.44.0.3/32' "$DEPLOY_DIR/private/phone.conf"
[[ "$(stat -c %a "$DEPLOY_DIR/private/phone.conf")" == 600 ]]
[[ "$(stat -c %a "$DEPLOY_DIR/private")" == 700 ]]
[[ "$(grep '^PrivateKey' "$DEPLOY_DIR/private/home.conf")" != "$(grep '^PrivateKey' "$DEPLOY_DIR/private/phone.conf")" ]]
if (vpn_add phone) >/dev/null 2>&1; then fail 'Duplicate VPN device accepted.'; fi
if (vpn_add '../escape') >/dev/null 2>&1; then fail 'Unsafe device name accepted.'; fi
vpn_remove phone >/dev/null
[[ ! -f "$DEPLOY_DIR/private/phone.conf" ]]
if grep -Fq 'AllowedIPs = 10.44.0.3/32' "$DEPLOY_DIR/private/wg0.conf"; then fail 'Revoked peer persisted.'; fi
grep -Fq 'AllowedIPs = 10.44.0.2/32' "$DEPLOY_DIR/private/wg0.conf"
cmp "$DEPLOY_DIR/private/wg0.conf" "$TEMP/installed-wg0.conf"
grep -q 'remove$' "$CALLS"
printf 'VPN profiles, separate addresses, permissions and revocation checks passed.\n'