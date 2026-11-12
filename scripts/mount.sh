#!/bin/bash
# Monta lfs.img em $LFS (root). Idempotente.
set -euo pipefail
source "$(dirname "$0")/config.sh"
mountpoint -q $LFS && { echo "$LFS já montado"; exit 0; }
LOOP=$(losetup -j "$IMG" | cut -d: -f1 | head -1)
[ -n "$LOOP" ] || LOOP=$(losetup -fP --show "$IMG")
mkdir -p $LFS
mount -v "${LOOP}p2" $LFS
mkdir -p $LFS/boot/efi
mount -v "${LOOP}p1" $LFS/boot/efi
