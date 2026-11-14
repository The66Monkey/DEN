#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/deploy.sh"
source "$ROOT/lib/backup.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
DATA_DIR="$TEMP/data"
MEDIA_MOUNT="$TEMP/disk"
BACKUP_MOUNT="$TEMP/backup"
mkdir -p "$DATA_DIR" "$MEDIA_MOUNT/den/media" "$MEDIA_MOUNT/den/downloads" "$BACKUP_MOUNT"
ln -s "$MEDIA_MOUNT/den/media" "$DATA_DIR/media"
ln -s "$MEDIA_MOUNT/den/downloads" "$DATA_DIR/downloads"
MISSING=
WRONG_FILESYSTEM=false
FILESYSTEM=ext4
mountpoint() { [[ "${2:-}" != "$MISSING" ]]; }
findmnt() { printf '%s\n' "$FILESYSTEM"; }
stat() {
    if [[ "${*: -1}" == "$MEDIA_MOUNT" && "$WRONG_FILESYSTEM" == false ]]; then
        printf '2\n'
    else
        printf '1\n'
    fi
}
check_media_disk
ensure_media_storage
for path in "$MEDIA_MOUNT" "$DATA_DIR/media" "$DATA_DIR/downloads"; do
    MISSING="$path"
    if (ensure_media_storage) 2>/dev/null; then fail "Accepted missing mount: $path"; fi
done
MISSING=
WRONG_FILESYSTEM=true
if (check_media_disk) 2>/dev/null; then fail 'Accepted OS filesystem as secondary storage.'; fi
WRONG_FILESYSTEM=false
for FILESYSTEM in nfs vfat exfat; do
    if (check_media_disk) 2>/dev/null; then fail "Accepted unsuitable filesystem: $FILESYSTEM"; fi
done
FILESYSTEM=xfs
check_media_disk
FILESYSTEM=btrfs
check_media_disk
FILESYSTEM=ext4
SAVED_BACKUP_MOUNT="$BACKUP_MOUNT"
BACKUP_MOUNT="$MEDIA_MOUNT"
if (check_media_disk) 2>/dev/null; then fail 'Accepted shared media/backup storage without consent.'; fi
ALLOW_SHARED_MEDIA_BACKUP=yes
[[ -z "$(check_media_disk 2>&1)" ]] || fail 'Accepted shared storage produced unexpected output.'
[[ -z "$(ensure_media_storage 2>&1)" ]] || fail 'Accepted shared storage warned during normal use.'
WRONG_FILESYSTEM=true
if (check_media_disk) 2>/dev/null; then fail 'Shared-storage consent allowed the OS filesystem.'; fi
WRONG_FILESYSTEM=false
ALLOW_SHARED_MEDIA_BACKUP=no
BACKUP_MOUNT="$SAVED_BACKUP_MOUNT"
mv "$MEDIA_MOUNT/den/media" "$MEDIA_MOUNT/den/other"
mkdir "$MEDIA_MOUNT/den/media"
rm "$DATA_DIR/media"
ln -s "$MEDIA_MOUNT/den/other" "$DATA_DIR/media"
if (ensure_media_storage) 2>/dev/null; then fail 'Accepted wrong bind-mount source.'; fi
rm "$DATA_DIR/media"
ln -s "$MEDIA_MOUNT/den/media" "$DATA_DIR/media"
rmdir "$MEDIA_MOUNT/den/media"
mv "$MEDIA_MOUNT/den/other" "$MEDIA_MOUNT/den/media"

SECONDARY_CACHE_ENABLED=yes
for directory in cache/jellyfin cache/immich ai/ollama/models ai/webui/cache ai/rag/embedding; do
    mkdir -p "$MEDIA_MOUNT/den/$directory" "$(dirname "$DATA_DIR/$directory")"
    ln -s "$MEDIA_MOUNT/den/$directory" "$DATA_DIR/$directory"
done
ensure_media_storage
while IFS= read -r directory; do
    MISSING="$DATA_DIR/$directory"
    if (ensure_media_storage) 2>/dev/null; then fail "Accepted missing bulk storage: $directory"; fi
done < <(secondary_storage_directories)
MISSING=
mv "$MEDIA_MOUNT/den/ai/rag/embedding" "$MEDIA_MOUNT/den/ai/rag/other"
mkdir "$MEDIA_MOUNT/den/ai/rag/embedding"
rm "$DATA_DIR/ai/rag/embedding"
ln -s "$MEDIA_MOUNT/den/ai/rag/other" "$DATA_DIR/ai/rag/embedding"
if (ensure_media_storage) 2>/dev/null; then fail 'Accepted wrong AI cache bind source.'; fi
SECONDARY_CACHE_ENABLED=no
ensure_media_storage

media_mount_unit media > "$TEMP/media.mount"
grep -Fxq "What=$MEDIA_MOUNT/den/media" "$TEMP/media.mount"
grep -Fxq "Where=$DATA_DIR/media" "$TEMP/media.mount"
grep -Fxq "RequiresMountsFor=$MEDIA_MOUNT/den/media" "$TEMP/media.mount"
grep -Fxq "BindsTo=$(systemd-escape --path --suffix=mount "$MEDIA_MOUNT")" "$TEMP/media.mount"
grep -Fxq 'Options=bind' "$TEMP/media.mount"
grep -Fxq 'WantedBy=multi-user.target' "$TEMP/media.mount"

ensure_backup_mount() { :; }
fluxer_backup() { fail 'Backup reached Fluxer without live storage.'; }
MISSING="$DATA_DIR/downloads"
if (backup_stack) 2>/dev/null; then fail 'Backup accepted missing download storage.'; fi

MEDIA_MOUNT=
ensure_media_storage
check_media_disk
printf 'Secondary storage validation, mount contract and missing-disk backup gates passed.\n'
