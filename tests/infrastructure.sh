#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
DEPLOY_DIR="$(mktemp -d)"
trap 'rm -rf "$DEPLOY_DIR"' EXIT
read_settings "$ROOT/config/example.env"
mkdir -p "$DEPLOY_DIR/templates" "$DEPLOY_DIR/private"
cp "$ROOT/templates/merge-routes.jq" "$ROOT/templates/compose.external-edge.yml" "$DEPLOY_DIR/templates/"
cp "$ROOT/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
write_routes
cp "$DEPLOY_DIR/routes.json" "$DEPLOY_DIR/original.json"
cat > "$DEPLOY_DIR/private/routes-custom.json" <<'JSON'
{"http": {
  "routers": {"business": {"rule": "Host(`erp.example.net`)", "service": "business", "tls": {"certResolver": "business"}}},
  "services": {"business": {"loadBalancer": {"servers": [{"url": "https://192.0.2.10"}], "serversTransport": "business"}}},
  "serversTransports": {"business": {"serverName": "erp.example.net"}}
},
"tcp": {
  "routers": {"basm-mail": {"rule": "HostSNI(`mx.example.net`)", "entryPoints": ["websecure"], "service": "basm-mail", "tls": {"passthrough": true}}},
  "services": {"basm-mail": {"loadBalancer": {"servers": [{"address": "192.0.2.20:443"}], "serversTransport": "basm-mail"}}},
  "serversTransports": {"basm-mail": {"proxyProtocol": {"version": 2}}}
}}
JSON
inode="$(stat -c %i "$DEPLOY_DIR/routes.json")"
write_routes
[[ "$(stat -c %i "$DEPLOY_DIR/routes.json")" == "$inode" ]]
jq -s -e '
  .[0] as $base | .[1] as $merged |
  all($base.http | to_entries[]; . as $section |
      all($section.value | to_entries[]; $merged.http[$section.key][.key] == .value)) and
  $merged.http.routers.business.tls.certResolver == "business" and
  $merged.http.serversTransports.business.serverName == "erp.example.net" and
  $merged.tcp.routers["basm-mail"].tls.passthrough == true and
  $merged.tcp.services["basm-mail"].loadBalancer.serversTransport == "basm-mail" and
  $merged.tcp.serversTransports["basm-mail"].proxyProtocol.version == 2
' "$DEPLOY_DIR/original.json" "$DEPLOY_DIR/routes.json" >/dev/null
cp "$DEPLOY_DIR/routes.json" "$DEPLOY_DIR/good.json"
for invalid in '{"http":{"routers":{"home":{}}}}' '{"udp":{}}' '{"tcp":{"services":[]}}' '{"http":{"services":[]}}' '{"http":{"routers":{"broken":null}}}' 'not json'; do
    printf '%s\n' "$invalid" > "$DEPLOY_DIR/private/routes-custom.json"
    if write_routes >"$DEPLOY_DIR/error" 2>&1; then
        fail 'Invalid or conflicting custom routes unexpectedly succeeded.'
    fi
    cmp "$DEPLOY_DIR/good.json" "$DEPLOY_DIR/routes.json"
    [[ -s "$DEPLOY_DIR/error" ]]
done
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$DEPLOY_DIR/env"
cp "$DEPLOY_DIR/env/.env" "$DEPLOY_DIR/.env"
compose config --services | grep -Fxq traefik
touch "$DEPLOY_DIR/private/external-edge"
if compose config --services | grep -Fxq traefik; then fail 'Embedded edge remains enabled.'; fi
rm "$DEPLOY_DIR/private/routes-custom.json"
write_routes
jq -e '.http.routers.dns == null and .http.services.dns == null' "$DEPLOY_DIR/routes.json" >/dev/null
mkdir -p "$DEPLOY_DIR/private/infrastructure"
cp "$ROOT/templates/compose.infrastructure.yml" "$DEPLOY_DIR/private/infrastructure/compose.yml"
write_routes
jq -e '
    .http.routers.dns.rule == "Host(`dns.home.example.net`)" and
    .http.routers.dns.entryPoints == ["websecure"] and
    .http.routers.dns.middlewares == ["private", "headers"] and
    .http.routers.dns.tls.certResolver == "home" and
    .http.services.dns.loadBalancer.servers == [{"url":"http://dns:3000"}]
' "$DEPLOY_DIR/routes.json" >/dev/null
write_vpn_dns | grep -Fxq 'host-record=dns.home.example.net,192.168.1.10'
printf '{"http":{"routers":{"dns":{}}}}\n' > "$DEPLOY_DIR/private/routes-custom.json"
cp "$DEPLOY_DIR/routes.json" "$DEPLOY_DIR/good.json"
if write_routes >"$DEPLOY_DIR/error" 2>&1; then fail 'Custom route replaced managed DNS administration.'; fi
cmp "$DEPLOY_DIR/good.json" "$DEPLOY_DIR/routes.json"
rm "$DEPLOY_DIR/private/external-edge"
rm "$DEPLOY_DIR/private/routes-custom.json"
write_routes
jq -e '.http.routers.dns == null' "$DEPLOY_DIR/routes.json" >/dev/null
if write_vpn_dns | grep -q 'host-record=dns\.'; then fail 'DNS administration advertised without the independent edge.'; fi
cp "$ROOT/templates/compose.infrastructure.yml" "$DEPLOY_DIR/infrastructure.yml"
env -i PATH="$PATH" HOME="${HOME:-/root}" docker compose --env-file "$DEPLOY_DIR/.env" \
    -f "$DEPLOY_DIR/infrastructure.yml" config --format json > "$DEPLOY_DIR/infra.json"
jq -e '
    (.services | keys) == ["dns", "edge"] and
    .networks.home.external == true and
    .services.edge.networks.home.ipv4_address == "172.30.44.2" and
    (.services.edge.command | index("--certificatesresolvers.business.acme.dnschallenge.provider=desec") != null) and
    (.services.edge.command | index("--certificatesresolvers.business.acme.dnschallenge.propagation.requireallrns=true") != null) and
    (all(.services.edge.command[]; contains("certificatesresolvers.business.acme.tlschallenge") | not)) and
    (any(.services.edge.volumes[]; .target == "/etc/traefik/cockpit" and .read_only == true)) and
    (.services.edge.networks | has("dns")) and
    (.services.dns.networks | keys) == ["dns"] and
    ([.services.edge.ports[].published] == ["80", "443"]) and
    (all(.services.dns.ports[] | select(.target == 53); .host_ip == "192.168.1.10")) and
    (all(.services.dns.ports[] | select(.target == 3000); .host_ip == "127.0.0.1")) and
    (all(.services[]; .image | test("@sha256:[a-f0-9]{64}$"))) and
    (all(.services[] | .volumes[]; (.source | contains("docker.sock") | not)))
' "$DEPLOY_DIR/infra.json" >/dev/null
touch "$DEPLOY_DIR/private/external-edge"
cp "$DEPLOY_DIR/.env" "$DEPLOY_DIR/private/infrastructure/.env"
cockpit_prepare_infrastructure
infrastructure_compose config --format json > "$DEPLOY_DIR/migrated.json"
jq -e --arg path "$DEPLOY_DIR/private/cockpit" '
    [.services.edge.volumes[] | select(.target == "/etc/traefik/cockpit")] |
    length == 1 and .[0].source == $path and .[0].read_only == true
' "$DEPLOY_DIR/migrated.json" >/dev/null
cockpit_prepare_infrastructure
cp "$DEPLOY_DIR/private/infrastructure/compose.yml" "$DEPLOY_DIR/good-compose"
mkdir "$DEPLOY_DIR/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$DEPLOY_DIR/bin/docker"
chmod +x "$DEPLOY_DIR/bin/docker"
if PATH="$DEPLOY_DIR/bin:$PATH" cockpit_prepare_infrastructure 2>/dev/null; then fail 'Failed infrastructure render returned success.'; fi
cmp "$DEPLOY_DIR/good-compose" "$DEPLOY_DIR/private/infrastructure/compose.yml"
printf 'Independent infrastructure, exact custom routes, error preservation and private bindings passed.\n'
