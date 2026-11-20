#!/bin/bash
# Gera o initramfs da Nexora (live e sistema instalado) a partir dos binários da própria Nexora.
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

BINS="bash mount umount switch_root blkid losetup mkdir sleep cat ls ln seq dmesg findmnt cp chroot chmod head tail e2fsck"
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
install -m755 "$PROJ/tools/iso/nexora-init" $W/init
mknod -m 600 $W/dev/console c 5 1
mknod -m 666 $W/dev/null c 1 3

(cd $W && find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet) | zstd -q -19 -T0 > "$OUT"
echo "✔ initramfs: $OUT ($(du -h "$OUT" | cut -f1))"

# microcódigo do CPU (AMD e Intel): cpio sem compressão, que tem de vir antes do initramfs
# (o UKI junta os dois; o kernel aplica-o logo no arranque)
if [ -n "${3:-}" ]; then
    U=$(mktemp -d); trap 'rm -rf "$W" "$U"' EXIT
    mkdir -p $U/kernel/x86/microcode
    cat "$ROOT"/usr/lib/firmware/amd-ucode/microcode_amd*.bin > $U/kernel/x86/microcode/AuthenticAMD.bin
    cat "$ROOT"/usr/lib/firmware/intel-ucode/* > $U/kernel/x86/microcode/GenuineIntel.bin
    [ -s $U/kernel/x86/microcode/AuthenticAMD.bin ] && [ -s $U/kernel/x86/microcode/GenuineIntel.bin ]
    (cd $U && find . -print0 | sort -z | cpio --null -o -H newc --owner=0:0 --quiet) > "$3"
    echo "✔ microcódigo: $3 ($(du -h "$3" | cut -f1))"
fi
