#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/hosts/fedora.sh"
source "$ROOT/lib/keepass.sh"
source "$ROOT/lib/fluxer.sh"
source "$ROOT/lib/backup.sh"
source "$ROOT/lib/maintenance.sh"
DEPLOY_DIR=/opt/den
DATA_DIR=/srv/den
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    printf 'Usage: sudo bash install.sh /path/to/den.env\nInstalls the fixed DEN stack on Fedora Server. Read docs/installation.md first.\n'
    exit 0
fi
[[ $# == 1 ]] || fail 'Supply a config file; see config/example.env.'
read_settings "$1"
check_host
request_server_hostname
request_ddns_token
install_packages
GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code "$UPDATE_REPOSITORY" refs/heads/main >/dev/null || fail 'Automatic updates need root Git access to UPDATE_REPOSITORY; configure a read-only deploy key before installing.'
copy_release "$ROOT" "$DEPLOY_DIR"
write_environment "$DEPLOY_DIR"
unset DESEC_TOKEN
configure_media_storage
prepare_storage
cp "$DEPLOY_DIR/templates/compose.yml" "$DEPLOY_DIR/compose.yml"
write_homepage
write_routes
write_vpn
ai_prepare
sync_keepass
ln -sfn /opt/den/bin/den /usr/local/bin/den
compose config --quiet
compose pull
initialize_backup
install_host_config
ai_install
hostnamectl set-hostname "$SERVER_HOSTNAME" || fail "Could not set the server hostname to $SERVER_HOSTNAME."
systemctl start den.service
fluxer_install
backup_stack
systemctl enable --now den-backup.timer den-check.timer
enable_update_timer
systemctl start den-ddns.service || log 'Initial deSEC update failed; the timer will retry in four hours. Check: sudo journalctl -u den-ddns'
show_summary
log 'DEN is installed. Verify HTTPS and finish first-user setup before inviting your household.'