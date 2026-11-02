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

for enabled in no yes; do
    QBITTORRENT_ENABLED="$enabled"
    write_routes
    if [[ -n "${COMPOSE_BIN:-}" ]]; then
        profiles=()
        [[ "$enabled" != yes ]] || profiles=(--profile torrents)
        "$COMPOSE_BIN" --env-file "$DEPLOY_DIR/.env" -f "$DEPLOY_DIR/compose.yml" \
            "${profiles[@]}" config --format json > "$TEMP/rendered.json"
    else
        compose config --format json > "$TEMP/rendered.json"
    fi
    if [[ "$enabled" == no ]]; then
        jq -e '.services | length == 11 and (has("qbittorrent") | not)' "$TEMP/rendered.json" >/dev/null
        jq -e '.http.routers | has("downloads") | not' "$DEPLOY_DIR/routes.json" >/dev/null
    else
        jq -e '
            (.services | length == 12) and
            (.services.qbittorrent.ports == null) and
            (.services.qbittorrent.profiles == ["torrents"]) and
            (.services.qbittorrent.environment.WEBUI_PORT == "18427") and
            (.services.qbittorrent.image | test(":5\\.3\\.0_v2\\.1\\.2-ls485@sha256:[a-f0-9]{64}$")) and
            (.services.qbittorrent.healthcheck.test | index("Host: downloads.home.example.net") != null) and
            ([.services.qbittorrent.volumes[].source] == ["/srv/den/qbittorrent", "/srv/den/downloads"]) and
            (all(.services.qbittorrent.volumes[]; .type == "bind" and .bind.selinux == "z"))
        ' "$TEMP/rendered.json" >/dev/null
        jq -e '
            (.http.routers | length == 5) and
            (.http.routers.downloads.rule == "Host(`downloads.home.example.net`)") and
            (.http.routers.downloads.tls.certResolver == "home") and
            (.http.routers.downloads.middlewares == ["private", "headers"]) and
            (.http.services.downloads.loadBalancer.servers[0].url == "http://qbittorrent:18427")
        ' "$DEPLOY_DIR/routes.json" >/dev/null
    fi
done
FLUXER_ENABLED=yes
write_routes
jq -e '(.http.routers | length == 6) and (.http.routers.chat != null) and (.http.routers.downloads != null)' "$DEPLOY_DIR/routes.json" >/dev/null

prepare_qbittorrent_config "$TEMP/config" downloads.home.example.net
config="$TEMP/config/qBittorrent/qBittorrent.conf"
[[ "$(stat -c %a "$config")" == 600 ]]
grep -Fxq 'Session\UseUPnP=false' "$config"
grep -Fxq 'Session\TempPathEnabled=true' "$config"
grep -Fxq 'WebUI\ServerDomains=downloads.home.example.net' "$config"
grep -Fxq 'WebUI\HostHeaderValidation=true' "$config"
grep -Fxq 'WebUI\CSRFProtection=true' "$config"
grep -Fxq 'WebUI\LocalHostAuth=true' "$config"
printf '\nexisting user preferences and password\n' >> "$config"
cp "$config" "$TEMP/saved.conf"
prepare_qbittorrent_config "$TEMP/config" changed.example.net
cmp "$config" "$TEMP/saved.conf"
mkdir -p "$TEMP/symlink"
ln -s "$TEMP/config/qBittorrent" "$TEMP/symlink/qBittorrent"
if (prepare_qbittorrent_config "$TEMP/symlink" downloads.home.example.net) 2>/dev/null; then
    fail 'Accepted a symlink qBittorrent configuration.'
fi

mkdir -p "$TEMP/bin"
cat > "$TEMP/bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEMP/compose-args"
EOF
chmod 700 "$TEMP/bin/docker"
QBITTORRENT_ENABLED=no PATH="$TEMP/bin:$PATH" compose ps
if grep -Fxq -- --profile "$TEMP/compose-args"; then fail 'Disabled feature activated a profile.'; fi
MEDIA_MOUNT=
for action in 'up' 'pull' 'ps' 'stop' 'start' 'config' 'logs'; do
    QBITTORRENT_ENABLED=yes PATH="$TEMP/bin:$PATH" compose "$action"
    grep -Fxq -- --profile "$TEMP/compose-args"
    grep -Fxq torrents "$TEMP/compose-args"
    grep -Fxq "$action" "$TEMP/compose-args"
done
printf 'qBittorrent optional config, routes, profiles, lifecycle and recovery-safe settings passed.\n'
