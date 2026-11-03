#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
DEPLOY_DIR="$(mktemp -d)"
trap 'rm -rf "$DEPLOY_DIR"' EXIT
read_settings "$ROOT/config/example.env"
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
write_environment "$DEPLOY_DIR"
write_routes
cp "$ROOT/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
if [[ -n "${COMPOSE_BIN:-}" ]]; then
    "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" config --format json > "$DEPLOY_DIR/rendered.json"
else
    compose config --format json > "$DEPLOY_DIR/rendered.json"
fi
jq -e '
    .name == "den" and
    (.services | length == 12) and
    (.services.homepage.ports == null) and
    (any(.services.homepage.volumes[]; .target == "/usr/share/nginx/html" and .read_only == true and .bind.selinux == "z")) and
    ([.services | to_entries[] | select(.value.ports != null) | .key] == ["traefik"]) and
    ([.services.traefik.ports[].published] == ["80", "443"]) and
    (all(.services.traefik.ports[]; .host_ip == "192.168.1.10")) and
    (.networks.home.ipam.config[0].ip_range == "172.30.44.128/25") and
    (.networks.home.ipam.config[0].gateway == "172.30.44.1") and
    (.services.traefik.networks.home.ipv4_address == "172.30.44.2") and
    (.services.traefik.command | index("--providers.file.filename=/etc/traefik/routes.yml") != null) and
    (any(.services.traefik.volumes[]; .target == "/etc/traefik/routes.yml" and .read_only == true)) and
    (any(.services.traefik.volumes[]; .target == "/etc/traefik/cockpit" and .read_only == true)) and
    (all(.services[]; .restart == "unless-stopped")) and
    (all(.services[]; .healthcheck != null)) and
    (all(.services[]; (.image | test(":(latest|release|stable)$") | not))) and
    (all(.services[]; .image | test("@sha256:[a-f0-9]{64}$"))) and
    (.services["immich-server"].image | split("@")[0] | endswith(":v3.3.5")) and
    (.services.nextcloud.environment.TRUSTED_PROXIES == "172.30.44.2") and
    (all(.services[] | .volumes[]?; (.source | contains("docker.sock") | not))) and
    (all(.services[] | .volumes[]?; .type == "bind")) and
    (all(.services[] | .volumes[]? | select(.source | startswith("/srv/den/")); .bind.selinux == "z"))
' "$DEPLOY_DIR/rendered.json" >/dev/null
jq -e '
    (.http.routers | length == 7) and
    (all(.http.routers | to_entries[] | select(.key != "home-lan-ip");
        .value.tls.certResolver == "home" and .value.middlewares[0] == "private")) and
    (.http.routers["home-lan-ip"].rule == "Host(`192.168.1.10`)") and
    (.http.routers["home-lan-ip"].service == "home") and
    (.http.routers["home-lan-ip"].middlewares == ["private", "headers"]) and
    (.http.routers["home-lan-ip"].tls == {}) and
    (.http.middlewares.private.ipAllowList.sourceRange == ["192.168.1.0/24", "10.44.0.0/24"]) and
    (.http.routers.photos.rule == "Host(`photos.home.example.net`)") and
    (.http.routers.home.rule == "Host(`home.home.example.net`)") and
    (.http.routers.home.middlewares == ["private", "headers"]) and
    (.http.services.home.loadBalancer.servers[0].url == "http://homepage:80")
' "$DEPLOY_DIR/routes.json" >/dev/null
mkdir -p "$DEPLOY_DIR/templates"
cp "$ROOT/templates/compose.dns.yml" "$DEPLOY_DIR/templates/"
if [[ -n "${COMPOSE_BIN:-}" ]]; then
    "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" \
        -f "$DEPLOY_DIR/templates/compose.dns.yml" config --format json > "$DEPLOY_DIR/dns.json"
else
    ACME_CHALLENGE=dns-desec compose config --format json > "$DEPLOY_DIR/dns.json"
fi
jq -e '
    (.services.traefik.command | index("--certificatesresolvers.home.acme.dnschallenge.provider=desec") != null) and
    (all(.services.traefik.command[]; contains("httpchallenge") | not)) and
    (.services.traefik.environment.DESEC_TOKEN_FILE == "/run/secrets/desec-token") and
    (.services.traefik.environment.DESEC_PROPAGATION_TIMEOUT == "600") and
    (.services.traefik.command | index("--certificatesresolvers.home.acme.dnschallenge.propagation.requireallrns=true") != null) and
    (.services.traefik.environment.DESEC_TOKEN == null) and
    ([.services.traefik.volumes[] | select(.target == "/run/secrets/desec-token")] |
        length == 1 and .[0].read_only == true and .[0].bind.selinux == "z" and
        (.[0].source | endswith("/private/desec-token"))) and
    ([.services.traefik.ports[].published] == ["80", "443"])
' "$DEPLOY_DIR/dns.json" >/dev/null
jq -s -e '
    (.[0].services.traefik.command | map(select(contains("httpchallenge") | not))) ==
    (.[1].services.traefik.command | map(select(contains("dnschallenge") | not)))
' "$DEPLOY_DIR/rendered.json" "$DEPLOY_DIR/dns.json" >/dev/null
printf 'Compose, storage, routing and private-access checks passed.\n'