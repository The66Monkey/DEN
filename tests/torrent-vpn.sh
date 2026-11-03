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
cp "$ROOT/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
mkdir -p "$DEPLOY_DIR/templates"
cp "$ROOT/templates/compose.torrents.yml" "$ROOT/templates/compose.torrent-vpn.yml" \
    "$ROOT/templates/import-torrent-wireguard.py" "$ROOT/templates/torrent-resolv.conf" "$DEPLOY_DIR/templates/"
QBITTORRENT_ENABLED=yes
QBITTORRENT_VPN_ENABLED=yes
write_routes
jq -e '.http.services.downloads.loadBalancer.servers[0].url == "http://torrent-vpn:18427"
    and .http.routers.downloads.middlewares == ["private", "headers"]' "$DEPLOY_DIR/routes.json" >/dev/null
if [[ -n "${COMPOSE_BIN:-}" ]]; then
    "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" \
        -f "$DEPLOY_DIR/templates/compose.torrents.yml" -f "$DEPLOY_DIR/templates/compose.torrent-vpn.yml" \
        --profile torrents config --format json > "$TEMP/compose.json"
else
    compose config --format json > "$TEMP/compose.json"
fi
jq -e '
    (.services.qbittorrent.network_mode == "service:torrent-vpn") and
    (.services.qbittorrent.networks == null) and
    (.services.qbittorrent.ports == null) and
    (any(.services.qbittorrent.volumes[];
        .target == "/etc/resolv.conf" and .read_only == true)) and
    (.services.qbittorrent.depends_on["torrent-vpn"].condition == "service_healthy") and
    (.services["torrent-vpn"].ports == null) and
    (.services["torrent-vpn"].privileged != true) and
    (.services["torrent-vpn"].cap_add == ["NET_ADMIN"]) and
    (.services["torrent-vpn"].environment.FIREWALL == "on") and
    (.services["torrent-vpn"].environment.FIREWALL_INPUT_PORTS == "18427") and
    (.services["torrent-vpn"].environment.FIREWALL_OUTBOUND_SUBNETS == null) and
    (.services["torrent-vpn"].sysctls["net.ipv6.conf.all.disable_ipv6"] == "1") and
    (.services["torrent-vpn"].image | test("@sha256:[a-f0-9]{64}$")) and
    (any(.services["torrent-vpn"].volumes[];
        .target == "/gluetun/wireguard/wg0.conf" and .read_only == true
        and .bind.create_host_path == false and .bind.selinux == "z"))
' "$TEMP/compose.json" >/dev/null
PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT" "$TEMP" <<'PY'
import base64
import importlib.util
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch
import socket

root, temporary = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location("profile", root / "templates/import-torrent-wireguard.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
key = base64.b64encode(bytes(range(32))).decode()
profile = f"""[Interface]
PrivateKey = {key}
Address = 10.64.1.2/32, fd00::2/128
DNS = 10.64.0.1
MTU = 1380

[Peer]
PublicKey = {key}
PresharedKey = {key}
Endpoint = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
rendered = module.parse(profile, "192.168.1.0/24")
assert "fd00" not in rendered and "::/0" not in rendered
assert "DNS" not in rendered
assert "AllowedIPs = 0.0.0.0/0" in rendered
assert f"PrivateKey = {key}" in rendered
hostname_profile = profile.replace("1.2.3.4:51820", "vpn.example.com:51820")
def answer(address):
    return (socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP, "", (address, 0))
with patch.object(module.socket, "getaddrinfo", return_value=[answer("1.2.3.4")]) as lookup:
    assert module.parse(hostname_profile, "192.168.1.0/24") == rendered
    lookup.assert_called_once_with("vpn.example.com", None, socket.AF_INET, socket.SOCK_DGRAM)
for answers in ([], [answer("192.168.1.1")], [answer("1.2.3.4"), answer("127.0.0.1")],
                [answer("100.64.0.1")], [answer("224.0.0.1")]):
    with patch.object(module.socket, "getaddrinfo", return_value=answers):
        try:
            module.parse(hostname_profile, "192.168.1.0/24")
        except module.EndpointError:
            pass
        else:
            raise AssertionError("Unsafe/empty DNS answer accepted")
with patch.object(module.socket, "getaddrinfo", side_effect=socket.gaierror("PRIVATE-DNS-DETAILS")):
    try:
        module.parse(hostname_profile, "192.168.1.0/24")
    except module.EndpointError as error:
        assert "PRIVATE-DNS-DETAILS" not in str(error)
    else:
        raise AssertionError("Failed DNS lookup accepted")
invalid = [
    profile.replace("1.2.3.4:51820", "invalid hostname:51820"),
    profile.replace("1.2.3.4:51820", "192.168.1.1:51820"),
    profile.replace("1.2.3.4:51820", "[2001:4860::1]:51820"),
    profile.replace("1.2.3.4:51820", "1.2.3.4:99999"),
    profile.replace("0.0.0.0/0, ::/0", "10.44.0.0/24"),
    profile.replace("10.64.1.2/32", "10.44.0.2/32"),
    profile.replace("10.64.1.2/32", "192.168.1.20/32"),
    profile.replace("10.64.1.2/32", "172.30.44.20/32"),
    profile.replace("10.64.1.2/32", "10.64.1.2/8"),
    profile.replace(f"PrivateKey = {key}", "PrivateKey = PRIVATE-INVALID-SECRET"),
    profile.replace("MTU = 1380", "PostUp = touch /tmp/den-unsafe"),
    profile.replace("MTU = 1380", "Table = off"),
    profile.replace("MTU = 1380", "SaveConfig = true"),
    profile + "\n[Peer]\nPublicKey = " + key,
    profile.replace("DNS = 10.64.0.1", "DNS = resolver.example.com"),
    profile.replace("MTU = 1380", "MTU = 9000"),
]
for data in invalid:
    try:
        module.parse(data, "192.168.1.0/24")
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid/unsafe profile accepted")
source = temporary / "provider.conf"
source.write_text(profile)
secret = temporary / "invalid.conf"
secret.write_text(profile.replace(f"PrivateKey = {key}", "PrivateKey = PRIVATE-INVALID-SECRET"))
result = subprocess.run([sys.executable, str(root / "templates/import-torrent-wireguard.py"),
                         str(secret), "192.168.1.0/24"], capture_output=True, text=True)
assert result.returncode != 0 and not result.stdout
assert "PRIVATE-INVALID-SECRET" not in result.stderr
link = temporary / "profile-link"
link.symlink_to(source)
result = subprocess.run([sys.executable, str(root / "templates/import-torrent-wireguard.py"),
                         str(link), "192.168.1.0/24"], capture_output=True, text=True)
assert result.returncode != 0
source.chmod(0o644)
result = subprocess.run([sys.executable, str(root / "templates/import-torrent-wireguard.py"),
                         str(source), "192.168.1.0/24"], capture_output=True, text=True)
assert result.returncode != 0
source.chmod(0o600)
large = temporary / "large.conf"
large.write_text("x" * 16385)
result = subprocess.run([sys.executable, str(root / "templates/import-torrent-wireguard.py"),
                         str(large), "192.168.1.0/24"], capture_output=True, text=True)
assert result.returncode != 0
PY
CALLS="$TEMP/calls"
FAIL_START=no
compose() {
    printf '%s vpn=%s\n' "$*" "$QBITTORRENT_VPN_ENABLED" >> "$CALLS"
    if [[ "$1" == up && "$FAIL_START" == yes ]]; then return 1; fi
}
torrent_vpn_setting no
if torrent_vpn "$TEMP/invalid.conf" >"$TEMP/error.log" 2>&1; then fail 'Invalid import succeeded.'; fi
[[ "$QBITTORRENT_VPN_ENABLED" == no ]]
[[ ! -e "$CALLS" ]]
torrent_vpn wait
[[ "$QBITTORRENT_VPN_ENABLED" == yes ]]
grep -Fq 'stop --timeout 120 qbittorrent vpn=no' "$CALLS"
grep -Fxq 'QBITTORRENT_VPN_ENABLED=yes' "$DEPLOY_DIR/.env"
[[ "$(stat -c %a "$DEPLOY_DIR/.env")" == 600 ]]
! torrent_vpn_profile_ready
torrent_vpn "$TEMP/provider.conf"
torrent_vpn_profile_ready
[[ "$(stat -c %a "$DEPLOY_DIR/private/torrent-vpn")" == 700 ]]
[[ "$(stat -c %a "$DEPLOY_DIR/private/torrent-vpn/wg0.conf")" == 600 ]]
grep -Fq 'up -d --force-recreate --wait --wait-timeout 180 torrent-vpn qbittorrent vpn=yes' "$CALLS"
FAIL_START=yes
if torrent_vpn "$TEMP/provider.conf" >"$TEMP/error.log" 2>&1; then fail 'Failed tunnel start succeeded.'; fi
[[ "$QBITTORRENT_VPN_ENABLED" == yes ]]
grep -Fxq 'QBITTORRENT_VPN_ENABLED=yes' "$DEPLOY_DIR/.env"
grep -q 'No direct fallback' "$TEMP/error.log"
[[ -s "$DEPLOY_DIR/private/torrent-vpn/previous.conf" ]]
FAIL_START=no
torrent_vpn off
[[ "$QBITTORRENT_VPN_ENABLED" == no ]]
grep -Fq 'up -d --no-deps --force-recreate --wait --wait-timeout 180 qbittorrent vpn=no' "$CALLS"
jq -e '.http.services.downloads.loadBalancer.servers[0].url == "http://qbittorrent:18427"' "$DEPLOY_DIR/routes.json" >/dev/null
QBITTORRENT_VPN_ENABLED=yes
mv "$DEPLOY_DIR/private/torrent-vpn/wg0.conf" "$TEMP/saved-profile"
: > "$CALLS"
compose() {
    printf '%s\n' "$*" >> "$CALLS"
    if [[ "$*" == 'config --services' ]]; then printf 'nextcloud\njellyfin\nqbittorrent\ntorrent-vpn\n'; fi
}
start_stack
grep -Fxq 'stop --timeout 120 qbittorrent torrent-vpn' "$CALLS"
grep -Fxq 'up -d --wait --wait-timeout 900 nextcloud jellyfin' "$CALLS"
if grep '^up ' "$CALLS" | grep -Eq 'qbittorrent|torrent-vpn'; then
    fail 'Started torrents without a required profile.'
fi
printf 'Torrent VPN isolation, private import, invalid profiles, failure states and explicit direct mode passed.\n'
