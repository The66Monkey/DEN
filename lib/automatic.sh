#!/usr/bin/env bash

fedora_version_id() (
    . /etc/os-release
    printf '%s\n' "$VERSION_ID"
)

automatic_releases() (
    local stage tag version current
    stage="$(mktemp -d /opt/den-upstream.XXXXXX)" || return 1
    trap 'rm -rf "$stage"' EXIT
    GIT_TERMINAL_PROMPT=0 git clone --quiet --branch main "$UPDATE_REPOSITORY" "$stage/repository" || return 1
    current="$(cat "$DEPLOY_DIR/VERSION")" || return 1
    [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Installed VERSION must be numeric major.minor.patch.'
    git -C "$stage/repository" tag --merged origin/main --sort=version:refname > "$stage/tags" || return 1
    while IFS= read -r tag; do
        [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        version="${tag#v}"
        [[ "$version" != "$current" ]] || continue
        [[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | head -1)" == "$current" ]] || continue
        git -C "$stage/repository" checkout --quiet --detach "$tag" || return 1
        [[ "$(cat "$stage/repository/VERSION")" == "$version" ]] || fail "Release tag $tag disagrees with VERSION."
        log "Automatically applying DEN $version."
        update_release "$stage/repository" || return 1
        current="$version"
    done < "$stage/tags"
    git -C "$stage/repository" checkout --quiet --detach origin/main || return 1
    version="$(cat "$stage/repository/VERSION")" || return 1
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Upstream VERSION must be numeric major.minor.patch.'
    if [[ "$version" != "$current" ]]; then
        [[ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | head -1)" == "$current" ]] || fail 'Upstream release would downgrade DEN.'
        update_release "$stage/repository" || return 1
    fi
)

automatic_update() (
    local stage current next status
    [[ ! -e "$DEPLOY_DIR/private/update-in-progress" ]] || fail 'A previous release update was interrupted; maintenance requires recovery.'
    health_check || return 1
    backup_stack || return 1
    dnf -y install git dnf5-plugins || return 1
    automatic_releases || return 1
    # Refresh implementations after an upstream release replaces installed code.
    source "$DEPLOY_DIR/lib/core.sh"
    source "$DEPLOY_DIR/lib/deploy.sh"
    source "$DEPLOY_DIR/lib/maintenance.sh"
    source "$DEPLOY_DIR/lib/fluxer.sh"
    source "$DEPLOY_DIR/lib/backup.sh"
    read_settings "$DEPLOY_DIR/.env" || return 1
    if [[ "${FLUXER_ENABLED:-no}" == yes ]]; then
        fluxer_upgrade || return 1
    fi
    health_check || return 1
    dnf -y --refresh upgrade || return 1
    health_check || return 1
    stage="$(mktemp -d /opt/den-fedora.XXXXXX)" || return 1
    trap 'rm -rf "$stage"' EXIT
    curl -fsSL --retry 3 --connect-timeout 30 --max-time 180 \
        https://fedoraproject.org/releases.json -o "$stage/releases.json" || return 1
    current="$(fedora_version_id)" || return 1
    [[ "$current" =~ ^[0-9]+$ ]] || fail 'Fedora VERSION_ID is not numeric.'
    next=$((current + 1))
    jq -e 'type == "array" and length > 0 and all(.[]; (.version | type) == "string" and (.arch | type) == "string" and (.variant | type) == "string")' "$stage/releases.json" >/dev/null || fail 'Invalid Fedora release metadata.'
    if jq -e --arg version "$next" 'any(.[]; .version == $version and .arch == "x86_64" and .variant == "Server")' "$stage/releases.json" >/dev/null; then
        log "Preparing unattended Fedora $current to $next upgrade."
        dnf -y system-upgrade download --releasever "$next" || return 1
        backup_stack || return 1
        health_check || return 1
        log 'Rebooting into the verified Fedora offline upgrade transaction.'
        dnf -y offline reboot || return 1
    else
        status=0
        dnf needs-restarting --reboothint || status=$?
        case "$status" in
            0) log 'Monthly automatic maintenance completed; no reboot needed.' ;;
            1) log 'Monthly maintenance completed; rebooting to apply host updates.'; systemctl reboot || return 1 ;;
            *) fail "Reboot requirement check failed with exit code $status." ;;
        esac
    fi
)
