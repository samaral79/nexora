#!/bin/bash
# Desmonta tudo em $LFS e solta o loop device (root).
set -euo pipefail
source "$(dirname "$0")/config.sh"
umount -R $LFS 2>/dev/null || true
for l in $(losetup -j "$IMG" | cut -d: -f1); do losetup -d "$l"; done
echo "desmontado"
