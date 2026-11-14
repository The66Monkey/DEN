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
    while IFS= read -r path; do
        if mountpoint -q "$DATA_DIR/$path"; then
            umount "$DATA_DIR/$path" || result=1
        fi
    done < <(secondary_storage_directories)
    for path in /etc/systemd/system "$TEMP/disk" "$TEMP/backup"; do
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
DESEC_TOKEN=abcdefghijklmnopqrstuvwxyz12
MEDIA_MOUNT="$TEMP/disk"
BACKUP_MOUNT="$TEMP/backup"
write_environment "$DEPLOY_DIR"

# tmpfs supplies an isolated secondary filesystem; Fedora filesystem/SELinux
# acceptance remains a live-host check.
findmnt() { printf 'ext4\n'; }
systemctl() {
    local directory
    if [[ "$1" == daemon-reload && -e /etc/systemd/system/docker.service.d/den-storage.conf ]]; then
        while IFS= read -r directory; do
            mountpoint -q "$DATA_DIR/$directory" || fail 'Attached Docker storage dependency before its mount was active.'
        done < <(secondary_storage_directories)
    fi
    if [[ "$1" == enable ]]; then
        local source target
        source="$(sed -n 's/^What=//p' "/etc/systemd/system/$3")"
        target="$(sed -n 's/^Where=//p' "/etc/systemd/system/$3")"
        [[ -n "$source" && -n "$target" ]] || fail 'Unexpected storage unit.'
        mount --bind "$source" "$target"
    fi
}
mkdir -p "$DATA_DIR/cache/jellyfin"
printf 'Existing cache\n' > "$DATA_DIR/cache/jellyfin/existing"
if (configure_media_storage) >/dev/null 2>&1; then fail 'Hid existing cache data with a mount.'; fi
grep -Fxq 'Existing cache' "$DATA_DIR/cache/jellyfin/existing"
rm "$DATA_DIR/cache/jellyfin/existing"
configure_media_storage
ensure_media_storage
while IFS= read -r directory; do
    unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
    grep -Fxq "What=$MEDIA_MOUNT/den/$directory" "/etc/systemd/system/$unit"
    grep -Fq "$unit" /etc/systemd/system/den.service.d/den-storage.conf
done < <(secondary_storage_directories)
while IFS= read -r directory; do
    grep -Fq "$DATA_DIR/$directory" /etc/systemd/system/docker.service.d/den-storage.conf
done < <(secondary_storage_directories)
if grep -Eq '^(BindsTo|PartOf)=' /etc/systemd/system/docker.service.d/den-storage.conf; then
    fail 'Added strict mount lifetime coupling to the shared Docker daemon.'
fi
grep -Fq "$DATA_DIR/ai/ollama/models" /etc/systemd/system/den-ai-ollama.service.d/den-storage.conf
mkdir -p "$DATA_DIR/cache" "$DATA_DIR/jellyfin"
printf 'HDD media\n' > "$DATA_DIR/media/movie"
printf 'HDD completed download\n' > "$DATA_DIR/downloads/completed"
printf 'HDD partial download\n' > "$DATA_DIR/downloads/partial"
printf 'SSD metadata\n' > "$DATA_DIR/jellyfin/settings"
printf 'regenerable\n' > "$DATA_DIR/cache/model"
printf 'AI model\n' > "$DATA_DIR/ai/ollama/models/model"
mkdir -p "$DATA_DIR/ai/rag/database"
printf 'SSD database\n' > "$DATA_DIR/ai/rag/database/state"
[[ "$(stat -c %d "$DATA_DIR/ai/rag/database")" != "$(stat -c %d "$DATA_DIR/ai/ollama/models")" ]]
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
for path in media/movie downloads/completed downloads/partial jellyfin/settings ai/ollama/models/model ai/rag/database/state; do
    cmp "$DATA_DIR/$path" "$MEDIA_MOUNT/drill$DATA_DIR/$path"
done
[[ ! -e "$MEDIA_MOUNT/drill$DATA_DIR/cache/model" ]]
umount "$DATA_DIR/downloads"
if (backup_stack) >/dev/null 2>&1; then fail 'Real backup accepted an unmounted download folder.'; fi
while IFS= read -r directory; do
    if mountpoint -q "$DATA_DIR/$directory"; then umount "$DATA_DIR/$directory"; fi
done < <(secondary_storage_directories)
mv "$DATA_DIR" "$TEMP/old-data"
mv "$MEDIA_MOUNT/den/media" "$MEDIA_MOUNT/old-media"
mv "$MEDIA_MOUNT/den/downloads" "$MEDIA_MOUNT/old-downloads"
mv "$MEDIA_MOUNT/den/ai/ollama/models" "$MEDIA_MOUNT/old-models"
while IFS= read -r directory; do
    case "$directory" in media|downloads|ai/ollama/models) ;; *) rmdir "$MEDIA_MOUNT/den/$directory" ;; esac
    unit="$(systemd-escape --path --suffix=mount "$DATA_DIR/$directory")"
    rm "/etc/systemd/system/$unit"
done < <(secondary_storage_directories)
rm /etc/systemd/system/den.service.d/den-storage.conf
rm /etc/systemd/system/docker.service.d/den-storage.conf
inode="$(stat -c %i "$MEDIA_MOUNT/drill$DATA_DIR/media/movie")"
promote_restored_data "$MEDIA_MOUNT/drill$DATA_DIR"
ensure_media_storage
[[ "$inode" == "$(stat -c %i "$DATA_DIR/media/movie")" ]]
[[ "$(stat -c %d "$DATA_DIR/jellyfin")" != "$(stat -c %d "$DATA_DIR/media")" ]]
cmp "$DATA_DIR/downloads/completed" "$MEDIA_MOUNT/old-downloads/completed"
cmp "$DATA_DIR/jellyfin/settings" "$TEMP/old-data/jellyfin/settings"
cmp "$DATA_DIR/ai/ollama/models/model" "$MEDIA_MOUNT/old-models/model"
cmp "$DATA_DIR/ai/rag/database/state" "$TEMP/old-data/ai/rag/database/state"
[[ "$(stat -c %d "$DATA_DIR/ai/rag/database")" != "$(stat -c %d "$DATA_DIR/ai/ollama/models")" ]]
SAVED_BACKUP_MOUNT="$BACKUP_MOUNT"
BACKUP_MOUNT="$MEDIA_MOUNT"
if (initialize_backup) >/dev/null 2>&1; then fail 'Real shared-disk backup accepted without consent.'; fi
ALLOW_SHARED_MEDIA_BACKUP=yes
initialize_backup >/dev/null
backup_stack >/dev/null
snapshot="$(restic_cmd snapshots --host den --tag den-v1 --json | jq -r 'last.id')"
restore_snapshot "$snapshot" "$TEMP/shared-drill" >/dev/null
for path in media/movie downloads/completed downloads/partial jellyfin/settings ai/ollama/models/model ai/rag/database/state; do
    cmp "$DATA_DIR/$path" "$TEMP/shared-drill$DATA_DIR/$path"
done
[[ ! -e "$TEMP/shared-drill$DATA_DIR/den-restic" ]]
restic_cmd ls --json "$snapshot" | jq -s -e --arg completed "$DATA_DIR/downloads/completed" '
    any(.[]; .path? == $completed) and
    all(.[]; ((.path? // "") | contains("/den-restic") | not))
' >/dev/null
BACKUP_MOUNT="$SAVED_BACKUP_MOUNT"
while IFS= read -r directory; do
    umount "$DATA_DIR/$directory"
done < <(secondary_storage_directories)
umount /etc/systemd/system
umount "$MEDIA_MOUNT" "$BACKUP_MOUNT"
printf 'Real isolated bind mounts, persistent units, encrypted restore and SSD/HDD recovery promotion passed.\n'
