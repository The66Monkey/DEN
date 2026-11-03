#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/hosts/fedora.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$ROOT"
DEN_PROFILE_DIR="$TEMP/profile.d"
install_login_banner
cmp "$ROOT/templates/profile.d/den.sh" "$DEN_PROFILE_DIR/den.sh"
[[ "$(stat -c '%a' "$DEN_PROFILE_DIR/den.sh")" == 644 ]]
read_settings "$ROOT/config/example.env"
write_network_guard > "$TEMP/http.nft"
grep -Fq 'hook prerouting priority -110' "$TEMP/http.nft"
grep -Fq "ip saddr $LAN_CIDR return" "$TEMP/http.nft"
grep -Fq "ip daddr $LAN_IP tcp dport 80 return" "$TEMP/http.nft"
grep -Fq "fib daddr type local udp dport $WIREGUARD_PORT return" "$TEMP/http.nft"
grep -Fq 'iifname "wg0" goto vpn' "$TEMP/http.nft"
grep -Fq 'ip saddr != 10.44.0.0/24 counter drop' "$TEMP/http.nft"
if grep -Fq 'tcp dport { 443, 7881 }' "$TEMP/http.nft"; then fail 'Disabled Fluxer exposed public HTTPS/voice.'; fi
ACME_CHALLENGE=dns-desec
FLUXER_ENABLED=yes
write_network_guard > "$TEMP/dns.nft"
if grep -Fq 'tcp dport 80 return' "$TEMP/dns.nft"; then fail 'DNS certificates exposed public HTTP.'; fi
grep -Fq '22, 53, 80, 443, 9090, 7881' "$TEMP/dns.nft"
grep -Fq 'udp dport { 53, 7882 }' "$TEMP/dns.nft"
grep -Fq "ip daddr $LAN_IP tcp dport { 443, 7881 } return" "$TEMP/dns.nft"
grep -Fq "ip daddr $LAN_IP udp dport 7882 return" "$TEMP/dns.nft"
DEPLOY_DIR="$TEMP/external"
mkdir -p "$DEPLOY_DIR/private"
touch "$DEPLOY_DIR/private/external-edge"
FLUXER_ENABLED=no
write_network_guard > "$TEMP/external.nft"
grep -Fq "ip daddr $LAN_IP tcp dport 80 return" "$TEMP/external.nft"
grep -Fq "ip daddr $LAN_IP tcp dport 443 return" "$TEMP/external.nft"
if grep -Fq '7881' "$TEMP/external.nft"; then fail 'Shared edge exposed disabled Fluxer voice.'; fi
grep -Fxq 'Before=docker.service' "$ROOT/templates/systemd/den-firewall.service"
if grep -q '^ExecStop=' "$ROOT/templates/systemd/den-firewall.service"; then fail 'Stopping the guard removes protection.'; fi
nft() { return 1; }
install() { fail 'Invalid firewall reached installation.'; }
if configure_network_guard 2>/dev/null; then fail 'Invalid firewall returned success.'; fi
printf 'Network guard generation, VPN scope, certificate modes and failure gates passed.\n'
