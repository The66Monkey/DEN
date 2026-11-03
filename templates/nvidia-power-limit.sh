#!/usr/bin/env bash
set -euo pipefail
: "${NVIDIA_GPU_ID:?NVIDIA_GPU_ID is required}"
: "${NVIDIA_POWER_LIMIT_W:?NVIDIA_POWER_LIMIT_W is required}"
[[ "$NVIDIA_GPU_ID" =~ ^([0-9]+|GPU-[a-fA-F0-9-]+)$ && "$NVIDIA_POWER_LIMIT_W" =~ ^[1-9][0-9]{1,2}$ ]] ||
    { printf 'DEN: invalid NVIDIA power-limit settings.\n' >&2; exit 1; }
limits="$(nvidia-smi -i "$NVIDIA_GPU_ID" --query-gpu=power.min_limit,power.max_limit,power.limit --format=csv,noheader,nounits)"
IFS=, read -r minimum maximum current <<< "$limits"
awk -v target="$NVIDIA_POWER_LIMIT_W" -v min="$minimum" -v max="$maximum" \
    'BEGIN {exit !(min ~ /^[ ]*[0-9.]+[ ]*$/ && max ~ /^[ ]*[0-9.]+[ ]*$/ && target >= min && target <= max)}' ||
    { printf 'DEN: power limit is outside the GPU supported range.\n' >&2; exit 1; }
if ! awk -v target="$NVIDIA_POWER_LIMIT_W" -v current="$current" \
    'BEGIN {exit !(current ~ /^[ ]*[0-9]+([.][0-9]+)?[ ]*$/ && current + 0 == target)}'; then
    nvidia-smi -i "$NVIDIA_GPU_ID" --power-limit="$NVIDIA_POWER_LIMIT_W"
fi
actual="$(nvidia-smi -i "$NVIDIA_GPU_ID" --query-gpu=power.limit --format=csv,noheader,nounits)"
awk -v target="$NVIDIA_POWER_LIMIT_W" -v actual="$actual" \
    'BEGIN {exit !(actual ~ /^[ ]*[0-9]+([.][0-9]+)?[ ]*$/ && actual + 0 == target)}' ||
    { printf 'DEN: NVIDIA power-limit verification failed.\n' >&2; exit 1; }
