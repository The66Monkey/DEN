#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/hosts/fedora.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deploy"
export DEN_COCKPIT_CONFIG_DIR="$TEMP/etc/cockpit"
export DEN_COCKPIT_SYSTEMD_DIR="$TEMP/systemd"
mkdir -p "$DEPLOY_DIR/templates" "$DEPLOY_DIR/private" "$DEN_COCKPIT_CONFIG_DIR"
cp "$ROOT/templates/configure-cockpit.py" "$DEPLOY_DIR/templates/"
read_settings "$ROOT/config/example.env"
[[ "$COCKPIT_ENABLED" == yes ]]
printf 'COCKPIT_ENABLED=invalid\n' > "$TEMP/invalid.env"
if (read_settings "$TEMP/invalid.env") 2>/dev/null; then fail 'Invalid Cockpit setting accepted.'; fi
printf '[Session]\nIdleTimeout=20\n' > "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
cp "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf" "$TEMP/original.conf"
printf 'host-record=other.example.net,192.168.1.20\n' > "$DEPLOY_DIR/private/dnsmasq.conf"
printf 'DOMAIN=%s\nDESEC_TOKEN=test-token\n' "$DOMAIN" > "$DEPLOY_DIR/private/ddns.env"
dnf() { printf 'dnf %s\n' "$*" >> "$TEMP/calls"; }
systemctl() { printf 'systemctl %s\n' "$*" >> "$TEMP/calls"; }
restorecon() { :; }
COCKPIT_ENABLED=no
mkdir -p "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d"
printf '[Socket]\nListenStream=9090\n' > "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/custom.conf"
cockpit_configure
cmp "$TEMP/original.conf" "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
[[ ! -e "$TEMP/calls" ]]
COCKPIT_ENABLED=yes
if cockpit_configure 2>/dev/null; then fail 'Custom Cockpit socket override overwritten.'; fi
rm "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/custom.conf"
cockpit_configure
grep -Fq 'systemctl enable --now cockpit.socket' "$TEMP/calls"
grep -Fxq 'ListenStream=172.30.44.1:9090' "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf"
grep -Fxq 'FreeBind=yes' "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf"
grep -Fxq "Origins = https://server.$DOMAIN" "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
grep -Fxq 'AllowUnencrypted = false' "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
grep -Fxq 'IdleTimeout = 20' "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
openssl verify -CAfile "$DEPLOY_DIR/private/cockpit/ca.crt" \
    -verify_hostname den-cockpit "$DEN_COCKPIT_CONFIG_DIR/ws-certs.d/99-den.cert"
[[ "$(stat -c '%a' "$DEN_COCKPIT_CONFIG_DIR/ws-certs.d/99-den.key")" == 600 ]]
[[ ! -f "$DEPLOY_DIR/private/cockpit/backend.key" ]]
grep -Fxq "host-record=server.$DOMAIN,$LAN_IP" "$DEPLOY_DIR/private/dnsmasq.conf"
grep -Fxq 'COCKPIT_ENABLED=yes' "$DEPLOY_DIR/private/ddns.env"
write_routes
jq -e --arg domain "$DOMAIN" '
    .http.routers.server.rule == ("Host(`server." + $domain + "`)") and
    .http.routers.server.middlewares == ["private", "headers"] and
    .http.services.server.loadBalancer.servers[0].url == "https://172.30.44.1:9090" and
    .http.services.server.loadBalancer.serversTransport == "cockpit" and
    .http.serversTransports.cockpit.serverName == "den-cockpit" and
    .http.serversTransports.cockpit.insecureSkipVerify == null
' "$DEPLOY_DIR/routes.json" >/dev/null
write_network_guard > "$TEMP/guard"
grep -Fq 'ip daddr 172.30.44.1 tcp dport 9090 ip saddr != 172.30.44.2 counter drop' "$TEMP/guard"
cockpit_configure
[[ "$(grep -c '^host-record=server.' "$DEPLOY_DIR/private/dnsmasq.conf")" == 1 ]]
cp "$DEPLOY_DIR/private/cockpit-state/backend.crt" "$TEMP/backend.crt"
rm "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf" "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf" \
    "$DEN_COCKPIT_CONFIG_DIR/ws-certs.d/99-den.cert" "$DEN_COCKPIT_CONFIG_DIR/ws-certs.d/99-den.key"
DEN_COCKPIT_RECOVERY=yes cockpit_configure
cmp "$TEMP/backend.crt" "$DEPLOY_DIR/private/cockpit/ca.crt"
cmp "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf" "$DEPLOY_DIR/private/cockpit-state/managed.conf"
cmp "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf" "$DEPLOY_DIR/private/cockpit-state/managed.socket"
printf '\n# operator edit\n' >> "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
if cockpit_configure 2>/dev/null; then fail 'Unmanaged Cockpit edit overwritten.'; fi
cp "$DEPLOY_DIR/private/cockpit-state/managed.conf" "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
COCKPIT_ENABLED=no
cockpit_configure
cmp "$TEMP/original.conf" "$DEN_COCKPIT_CONFIG_DIR/cockpit.conf"
[[ ! -e "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf" ]]
[[ ! -e "$DEN_COCKPIT_CONFIG_DIR/ws-certs.d/99-den.cert" ]]
grep -Fxq 'host-record=other.example.net,192.168.1.20' "$DEPLOY_DIR/private/dnsmasq.conf"
! grep -Fq 'host-record=server.' "$DEPLOY_DIR/private/dnsmasq.conf"
grep -Fxq 'COCKPIT_ENABLED=no' "$DEPLOY_DIR/private/ddns.env"
write_routes
jq -e '.http.routers.server == null and .http.services.server == null and .http.serversTransports == {}' "$DEPLOY_DIR/routes.json" >/dev/null
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$TEMP/saved"
grep -Fxq 'COCKPIT_ENABLED=no' "$TEMP/saved/.env"
read_settings "$TEMP/saved/.env"
[[ "$COCKPIT_ENABLED" == no ]]
grep -v '^COCKPIT_ENABLED=' "$TEMP/saved/.env" > "$TEMP/legacy.env"
read_settings "$TEMP/legacy.env"
[[ "$COCKPIT_ENABLED" == yes ]]
COCKPIT_ENABLED=yes
dnf() { return 1; }
if cockpit_configure 2>/dev/null; then fail 'Package failure returned success.'; fi
[[ ! -e "$DEN_COCKPIT_SYSTEMD_DIR/cockpit.socket.d/den.conf" ]]
printf 'Cockpit settings, verified TLS, private route, DNS, opt-out and failure checks passed.\n'
