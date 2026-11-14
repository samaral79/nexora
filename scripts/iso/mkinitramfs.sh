#!/bin/bash
# Gera o initramfs do live a partir dos binários da própria Nexora (root, no Fedora).
# Uso: sudo ./scripts/iso/mkinitramfs.sh <raiz da Nexora> <saída.img>
set -euo pipefail
ROOT=${1:?raiz}; OUT=${2:?saída}
HERE=$(cd "$(dirname "$0")" && pwd)
PROJ=$(cd "$HERE/../.." && pwd)
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p $W/usr/{bin,sbin,lib} $W/{dev,proc,sys,run,sysroot,etc}
ln -s usr/bin $W/bin; ln -s usr/sbin $W/sbin; ln -s usr/lib $W/lib
mkdir -p $W/lib64

BINS="bash mount umount switch_root blkid losetup mkdir sleep cat ls ln seq dmesg findmnt"
copy_file() {   # copia um ficheiro da raiz da Nexora mantendo o caminho (segue symlinks)
    local f=$1
    mkdir -p "$W$(dirname "$f")"
    cp -L "$ROOT$f" "$W$f"
}
for b in $BINS; do
    p=$(chroot "$ROOT" /usr/bin/bash -c "command -v $b") || { echo "falta $b na Nexora"; exit 1; }
    copy_file "$p"
    # bibliotecas (resolvidas pelo ldd da própria Nexora)
    chroot "$ROOT" /usr/bin/ldd "$p" 2>/dev/null | grep -oE '/[^ ]+' | while read -r lib; do
        [ -e "$W$lib" ] || copy_file "$lib"
    done
done
ln -sf bash $W/usr/bin/sh
install -m755 "$PROJ/tools/iso/live-init" $W/init
mknod -m 600 $W/dev/console c 5 1
mknod -m 666 $W/dev/null c 1 3

(cd $W && find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet) | zstd -q -19 -T0 > "$OUT"
echo "✔ initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
