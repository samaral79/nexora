#!/bin/bash
# Snapshot do sistema da Nexora (root). Uso: sudo ./scripts/backup.sh <nome>
# Desmonta os FS virtuais primeiro. Não inclui /sources (descarrega-se de novo) nem a ESP.
set -euo pipefail
source "$(dirname "$0")/config.sh"
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
NAME=${1:?uso: $0 <nome>}
mountpoint -q $LFS/sources/blfs && umount $LFS/sources/blfs
mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm
mountpoint -q $LFS/dev/pts && umount $LFS/dev/pts
for d in sys proc run dev; do mountpoint -q $LFS/$d && umount $LFS/$d; done
mkdir -p $PROJ/backups
OUT=$PROJ/backups/nexora-$NAME.tar.xz
tar -C $LFS --exclude=./sources --exclude='./boot/efi/*' -cpf - . | xz -T0 -6 > "$OUT"
chown samaral79: $PROJ/backups "$OUT"
ls -lh "$OUT"
