#!/usr/bin/env bash

sync_keepass() {
    [[ "${KEEPASS_ENABLED:-no}" == yes ]] || return 0
    python3 "$DEPLOY_DIR/templates/keepass-sync.py" "$DEPLOY_DIR"
}

require_keepass() {
    [[ "${KEEPASS_ENABLED:-no}" == yes ]] || fail 'KeePass is not enabled for this DEN installation.'
    [[ -f "$DEPLOY_DIR/private/credentials.kdbx" && -f "$DEPLOY_DIR/private/keepass-master-password" ]] || fail 'KeePass vault is missing; run sudo den keepass-sync.'
}

keepass_export() {
    local destination="$1" parent
    require_keepass
    [[ "$destination" == /* && ! -e "$destination" && ! -L "$destination" ]] || fail 'Choose a new absolute destination file.'
    parent="$(dirname "$destination")"
    [[ -d "$parent" && ! -L "$parent" ]] || fail 'Export directory must already exist and cannot be a symlink.'
    [[ "$(stat -c %d "$parent")" != "$(stat -c %d "$DEPLOY_DIR")" ]] || fail 'Export the vault to a separate filesystem.'
    install -m 600 "$DEPLOY_DIR/private/credentials.kdbx" "$destination"
    log "KeePass vault exported to $destination. Retrieve its password separately with sudo den keepass-password."
}

keepass_password() {
    require_keepass
    cat "$DEPLOY_DIR/private/keepass-master-password"
}

keepass_sync_command() {
    require_keepass
    sync_keepass
}