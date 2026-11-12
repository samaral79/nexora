#!/bin/bash
# Descarrega todas as fontes e patches do LFS para $LFS/sources e verifica md5.
set -euo pipefail
source "$(dirname "$0")/config.sh"
BASE=https://www.linuxfromscratch.org/lfs/downloads/$LFS_VERSION-systemd
[ "$LFS_VERSION" = 13.1 ] && BASE=https://www.linuxfromscratch.org/lfs/downloads/stable-systemd
cd $LFS/sources
wget -q -O wget-list "$BASE/wget-list"
wget -q -O md5sums "$BASE/md5sums"
wget --input-file=wget-list --continue --no-verbose
md5sum -c md5sums | grep -v ': OK$' || echo "✔ todas as fontes OK"
