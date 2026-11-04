#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
mkdir -p "$DEPLOY_DIR/private" "$DEPLOY_DIR/templates"
cp "$ROOT/templates/merge-routes.jq" "$DEPLOY_DIR/templates/"
read_settings "$ROOT/config/example.env"
addon_hook prepare
cat > "$DEPLOY_DIR/private/addon-hook" <<'EOF'
case "$1" in
    prepare|start|stop|check|before-backup|after-backup) printf '%s\n' "$1" ;;
    *) exit 1 ;;
esac
EOF
chmod 600 "$DEPLOY_DIR/private/addon-hook"
[[ "$(addon_hook prepare)" == prepare ]]
[[ "$(addon_hook after-backup)" == after-backup ]]
if addon_hook unknown; then fail 'Unknown add-on hook action accepted.'; fi
chmod 666 "$DEPLOY_DIR/private/addon-hook"
if (addon_hook start) 2>/dev/null; then fail 'Writable add-on hook accepted.'; fi
rm "$DEPLOY_DIR/private/addon-hook"
ln -s /dev/null "$DEPLOY_DIR/private/addon-hook"
if (addon_hook start) 2>/dev/null; then fail 'Symlink add-on hook accepted.'; fi
rm "$DEPLOY_DIR/private/addon-hook"
printf '{"http":{"services":{"extra":{"loadBalancer":{"servers":[{"url":"http://extra:80"}]}}}}}\n' > "$DEPLOY_DIR/private/routes-addon.json"
write_routes
jq -e '.http.services.extra.loadBalancer.servers[0].url == "http://extra:80"' "$DEPLOY_DIR/routes.json" >/dev/null
cp "$DEPLOY_DIR/private/routes-addon.json" "$DEPLOY_DIR/private/routes-custom.json"
if write_routes 2>/dev/null; then fail 'Conflicting custom and add-on routes accepted.'; fi
printf 'host-record=extra.%s,%s\n' "$DOMAIN" "$LAN_IP" > "$DEPLOY_DIR/private/dns-addon.conf"
write_vpn_dns > "$TEMP/dns"
grep -Fxq "host-record=extra.$DOMAIN,$LAN_IP" "$TEMP/dns"
for setting in AI_ENABLED=no AUDIOBOOKS_ENABLED=no NVIDIA_GPU_ID=0; do
    cp "$ROOT/config/example.env" "$TEMP/legacy.env"
    printf '\n%s\n' "$setting" >> "$TEMP/legacy.env"
    if (read_settings "$TEMP/legacy.env") 2>"$TEMP/error"; then fail 'Legacy add-on settings silently accepted.'; fi
    grep -Fq 'migration guide' "$TEMP/error"
done
printf 'Generic add-on hooks, route/DNS integration and migration checks passed.\n'
