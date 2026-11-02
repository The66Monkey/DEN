#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/hosts/fedora.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
CALLS="$TEMP/calls"
FREE_INSTALLED=no
FAIL_DNF=no
rpm() {
    case "$*" in
        '-E %fedora') printf '44\n' ;;
        '-q ffmpeg-free') [[ "$FREE_INSTALLED" == yes ]] ;;
        '-q ffmpeg') return 0 ;;
        *) return 1 ;;
    esac
}
dnf() { printf '%s\n' "$*" >> "$CALLS"; [[ "$FAIL_DNF" == no ]]; }
ffmpeg() { [[ "$*" == -version ]]; }
install_media_codecs
grep -Fxq 'install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm' "$CALLS"
grep -Fxq 'install -y ffmpeg --allowerasing' "$CALLS"
FREE_INSTALLED=yes
: > "$CALLS"
install_media_codecs
grep -Fxq 'swap -y ffmpeg-free ffmpeg --allowerasing' "$CALLS"
FAIL_DNF=yes
if install_media_codecs; then fail 'Failed codec installation returned success.'; fi
GPU_VENDOR=10de
DRIVER_OK=yes
lspci() { printf '0000:01:00.0 0300: %s:13c2 (rev a1)\n' "$GPU_VENDOR"; }
nvidia-smi() { [[ "$DRIVER_OK" == yes ]]; }
check_nvidia_driver > "$TEMP/driver"
grep -Fq 'NVIDIA driver responds' "$TEMP/driver"
grep -Fq 'container-toolkit/device access' "$TEMP/driver"
DRIVER_OK=no
check_nvidia_driver > "$TEMP/driver"
grep -Fq 'nvidia-smi failed or is missing' "$TEMP/driver"
GPU_VENDOR=8086
check_nvidia_driver > "$TEMP/driver"
[[ ! -s "$TEMP/driver" ]]
printf 'Full FFmpeg install/swap, failure propagation and NVIDIA driver warnings passed.\n'
