#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/fluxer.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DEPLOY_DIR="$TEMP/deployment"
DATA_DIR="$TEMP/data"
mkdir -p "$DEPLOY_DIR" "$DATA_DIR"
DOMAIN=home.example.net
LAN_CIDR=192.168.1.0/24
FLUXER_ENABLED=no
write_routes
jq -e '(.http.routers | keys | sort) == ["files", "git", "media", "photos"]' "$DEPLOY_DIR/routes.json" >/dev/null
FLUXER_ENABLED=yes
write_routes
jq -e '
    .http.routers.chat.rule == "Host(`chat.home.example.net`)" and
    .http.routers.chat.middlewares == ["private", "headers"] and
    .http.middlewares.private.ipAllowList.sourceRange == ["192.168.1.0/24", "10.44.0.0/24"] and
    .http.services.chat.loadBalancer.servers[0].url == "http://172.30.44.1:29461"
' "$DEPLOY_DIR/routes.json" >/dev/null

REXCTL_BIN="$TEMP/rexctl"
REXCTL_LOG="$TEMP/rexctl.log"
export REXCTL_LOG
cat > "$REXCTL_BIN" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REXCTL_LOG"
EOF
chmod 700 "$REXCTL_BIN"
LAN_IP=192.168.1.10
install_rexctl() { :; }
fluxer_install
grep -Fq -- "--dir $DEPLOY_DIR/fluxer install --domain chat.$DOMAIN" "$REXCTL_LOG"
grep -Fq -- '--setup browser' "$REXCTL_LOG"
if grep -Eq -- '--name|--registration|--sign-in|--skip-email' "$REXCTL_LOG"; then
    fail 'Browser setup received terminal-only options.'
fi
grep -Fq -- "--dir $DEPLOY_DIR/fluxer registration set invite" "$REXCTL_LOG"
fluxer_backup
grep -Fq -- "--dir $DEPLOY_DIR/fluxer backup location $DATA_DIR/fluxer/backups" "$REXCTL_LOG"
grep -Fq -- "--dir $DEPLOY_DIR/fluxer backup" "$REXCTL_LOG"
mkdir -p "$DATA_DIR/fluxer/backups"
printf 'full archive\n' > "$DATA_DIR/fluxer/backups/old.tar.zst"
printf 'new full archive\n' > "$DATA_DIR/fluxer/backups/new.tar.zst"
touch -d '2 minutes ago' "$DATA_DIR/fluxer/backups/old.tar.zst"
fluxer_restore
grep -Fq -- "--dir $DEPLOY_DIR/fluxer restore $DATA_DIR/fluxer/backups/new.tar.zst --confirm chat.$DOMAIN --yes" "$REXCTL_LOG"
printf 'Fluxer optional route and backup hooks passed.\n'