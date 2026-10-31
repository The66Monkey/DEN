#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/backup.sh"
source "$ROOT/lib/maintenance.sh"
DEPLOY_DIR=/opt/den
DATA_DIR=/srv/den
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: sudo bash install.sh /path/to/den.env\nInstalls the fixed DEN stack on fresh Debian 13. Read docs/installation.md first.\n'
    exit 0
fi
[[ $# == 1 ]] || fail 'Supply a config file; see config/example.env.'
read_settings "$1"
check_host
install_packages
copy_release "$ROOT" "$DEPLOY_DIR"
write_environment "$DEPLOY_DIR"
prepare_storage
cp "$DEPLOY_DIR/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
write_routes
write_vpn
ln -sfn /opt/den/bin/den /usr/local/bin/den
compose config --quiet
compose pull
initialize_backup
install_host_config
systemctl start den.service
backup_stack
systemctl enable --now den-backup.timer den-check.timer
show_summary
log 'DEN is installed. Verify HTTPS and finish first-user setup before inviting your household.'