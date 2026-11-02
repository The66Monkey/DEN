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
    (.services | length == 11) and
    ([.services | to_entries[] | select(.value.ports != null) | .key] == ["traefik"]) and
    ([.services.traefik.ports[].published] == ["80", "443"]) and
    (all(.services.traefik.ports[]; .host_ip == "192.168.1.10")) and
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
    (.http.routers | length == 4) and
    (all(.http.routers[]; .tls.certResolver == "home" and .middlewares[0] == "private")) and
    (.http.middlewares.private.ipAllowList.sourceRange == ["192.168.1.0/24", "10.44.0.0/24"]) and
    (.http.routers.photos.rule == "Host(`photos.home.example.net`)")
' "$DEPLOY_DIR/routes.json" >/dev/null
printf 'Compose, storage, routing and private-access checks passed.\n'