#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/fluxer.sh"
source "$ROOT/lib/backup.sh"
[[ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]] || fail 'Run this test in an isolated user/mount namespace, never on the host.'
mount --make-rprivate /
mount -t tmpfs tmpfs /tmp
chmod 1777 /tmp
TEMP="$(mktemp -d)"
DATA_DIR="$TEMP/data"
DEPLOY_DIR="$TEMP/deployment"
cleanup() {
    local result=$? path
    trap - EXIT
    for path in "$DATA_DIR/downloads" "$DATA_DIR/media" /etc/systemd/system "$TEMP/disk" "$TEMP/backup"; do
        if mountpoint -q "$path"; then
            umount "$path" || result=1
        fi
    done
    rm -rf "$TEMP"
    exit "$result"
}
trap cleanup EXIT
mkdir -p "$TEMP/units" "$TEMP/disk" "$TEMP/backup" "$DEPLOY_DIR"
mount --bind "$TEMP/units" /etc/systemd/system
mount -t tmpfs tmpfs "$TEMP/disk"
mount -t tmpfs tmpfs "$TEMP/backup"
read_settings "$ROOT/config/example.env"
MEDIA_MOUNT="$TEMP/disk"
BACKUP_MOUNT="$TEMP/backup"
write_environment "$DEPLOY_DIR"

# tmpfs supplies an isolated secondary filesystem; Fedora filesystem/SELinux
# acceptance remains a live-host check.
findmnt() { printf 'ext4\n'; }
systemctl() {
    if [[ "$1" == enable ]]; then
        case "$3" in
            *media.mount) mount --bind "$MEDIA_MOUNT/den/media" "$DATA_DIR/media" ;;
            *downloads.mount) mount --bind "$MEDIA_MOUNT/den/downloads" "$DATA_DIR/downloads" ;;
            *) fail 'Unexpected storage unit.' ;;
        esac
    fi
}
configure_media_storage
ensure_media_storage
for directory in media downloads; do
    unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
    grep -Fxq "What=$MEDIA_MOUNT/den/$directory" "/etc/systemd/system/$unit"
    grep -Fq "$unit" /etc/systemd/system/docker.service.d/den-storage.conf
done
grep -Fxq "RequiresMountsFor=$DATA_DIR/media $DATA_DIR/downloads" /etc/systemd/system/docker.service.d/den-storage.conf
mkdir -p "$DATA_DIR/cache" "$DATA_DIR/jellyfin"
printf 'HDD media\n' > "$DATA_DIR/media/movie"
printf 'HDD completed download\n' > "$DATA_DIR/downloads/completed"
printf 'HDD partial download\n' > "$DATA_DIR/downloads/partial"
printf 'SSD metadata\n' > "$DATA_DIR/jellyfin/settings"
printf 'regenerable\n' > "$DATA_DIR/cache/model"
[[ "$(stat -c %d "$DATA_DIR/jellyfin")" != "$(stat -c %d "$DATA_DIR/media")" ]]
cmp "$DATA_DIR/downloads/completed" "$MEDIA_MOUNT/den/downloads/completed"
compose() {
    case "$*" in
        'ps --status running --services') printf 'jellyfin\nqbittorrent\n' ;;
        *) return 0 ;;
    esac
}
if [[ -n "${RESTIC_BIN:-}" ]]; then
    restic_cmd() {
        RESTIC_REPOSITORY="$BACKUP_MOUNT/den-restic" RESTIC_PASSWORD="$RESTIC_PASSWORD" "$RESTIC_BIN" "$@"
    }
fi
initialize_backup >/dev/null
backup_stack >/dev/null
snapshot="$(restic_cmd snapshots --host den --tag den-v1 --json | jq -r 'last.id')"
restore_snapshot "$snapshot" "$MEDIA_MOUNT/drill" >/dev/null
for path in media/movie downloads/completed downloads/partial jellyfin/settings; do
    cmp "$DATA_DIR/$path" "$MEDIA_MOUNT/drill$DATA_DIR/$path"
done
[[ ! -e "$MEDIA_MOUNT/drill$DATA_DIR/cache/model" ]]
umount "$DATA_DIR/downloads"
if (backup_stack) >/dev/null 2>&1; then fail 'Real backup accepted an unmounted download folder.'; fi
umount "$DATA_DIR/media"
mv "$DATA_DIR" "$TEMP/old-data"
mv "$MEDIA_MOUNT/den/media" "$MEDIA_MOUNT/old-media"
mv "$MEDIA_MOUNT/den/downloads" "$MEDIA_MOUNT/old-downloads"
for directory in media downloads; do
    unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
    rm "/etc/systemd/system/$unit"
done
rm /etc/systemd/system/docker.service.d/den-storage.conf
inode="$(stat -c %i "$MEDIA_MOUNT/drill$DATA_DIR/media/movie")"
promote_restored_data "$MEDIA_MOUNT/drill$DATA_DIR"
ensure_media_storage
[[ "$inode" == "$(stat -c %i "$DATA_DIR/media/movie")" ]]
[[ "$(stat -c %d "$DATA_DIR/jellyfin")" != "$(stat -c %d "$DATA_DIR/media")" ]]
cmp "$DATA_DIR/downloads/completed" "$MEDIA_MOUNT/old-downloads/completed"
cmp "$DATA_DIR/jellyfin/settings" "$TEMP/old-data/jellyfin/settings"
umount "$DATA_DIR/downloads" "$DATA_DIR/media"
umount /etc/systemd/system
umount "$MEDIA_MOUNT" "$BACKUP_MOUNT"
printf 'Real isolated bind mounts, persistent units, encrypted restore and SSD/HDD recovery promotion passed.\n'
