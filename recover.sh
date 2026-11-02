#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/hosts/fedora.sh"
source "$ROOT/lib/fluxer.sh"
source "$ROOT/lib/backup.sh"
source "$ROOT/lib/maintenance.sh"
DEPLOY_DIR=/opt/den
DATA_DIR=/srv/den
[[ $# == 2 ]] || fail 'Usage: sudo bash recover.sh /external/den-recovery-kit/.env <snapshot-id>'
read_settings "$1"
[[ -n "${RESTIC_PASSWORD:-}" ]] || fail 'Recovery requires the saved generated .env, not the example config.'
check_host
install_packages
STAGING="/srv/den-restore-$(date +%s)"
if [[ -n "${MEDIA_MOUNT:-}" ]]; then
    STAGING="$MEDIA_MOUNT/den-restore-$(date +%s)"
fi
restore_snapshot "$2" "$STAGING"
promote_restored_data "$STAGING$DATA_DIR"
copy_release "$DATA_DIR/system/deployment" "$DEPLOY_DIR"
cp "$DATA_DIR/system/deployment/.env" "$DEPLOY_DIR/.env"
cp "$DATA_DIR/system/deployment/compose.yml" "$DEPLOY_DIR/compose.yml"
cp -a "$DATA_DIR/system/deployment/private" "$DEPLOY_DIR/"
read_settings "$DEPLOY_DIR/.env"
prepare_storage
write_homepage
write_routes
ln -sfn /opt/den/bin/den /usr/local/bin/den
compose config --quiet
compose pull
install_host_config
systemctl start den.service
fluxer_restore
systemctl enable --now den-backup.timer den-check.timer
enable_update_timer
systemctl start den-ddns.service || log 'Initial deSEC update failed; the timer will retry in four hours. Check: sudo journalctl -u den-ddns'
show_summary
log 'Recovery completed with the versions and keys saved in the snapshot.'