#!/bin/bash
# Gera a ISO live/instalável da Nexora Linux (root, no Fedora). Híbrida: BIOS + UEFI, CD ou pen.
#
# Uso: sudo ./scripts/iso/build-iso.sh [--dev-key]
#   --dev-key  põe a chave SSH do projeto no root do live (só para testes; não publicar essa ISO)
#
# A imagem de desenvolvimento (lfs.img) não é alterada: as mudanças do live vão para uma camada
# overlay em iso-work/, e é dessa vista que sai o squashfs.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config.sh"
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
DEVKEY=; [ "${1:-}" = --dev-key ] && DEVKEY=1

VER=13.1
LABEL=NEXORA_LIVE
W=$PROJ/iso-work
OUTDIR=$PROJ/iso
ISO=$OUTDIR/nexora-$VER-x86_64.iso
M=$W/merged
R=$W/iso-root

if pgrep -f "qemu-system.*file=$IMG" >/dev/null; then echo "Desliga a VM primeiro"; exit 1; fi
mountpoint -q $LFS || "$HERE/../mount.sh"
# sem os sistemas de ficheiros virtuais do chroot pendurados na imagem
for d in sources/blfs dev/shm dev/pts dev proc sys run; do mountpoint -q $LFS/$d && umount $LFS/$d; done

cleanup() {
    for d in dev/pts dev proc sys run; do mountpoint -q $M/$d && umount -l $M/$d || true; done
    mountpoint -q $M && umount -l $M || true
}
trap cleanup EXIT

echo "== 1/6 camada overlay por cima da Nexora"
cleanup
rm -rf $W/upper $W/work $R
mkdir -p $W/upper $W/work $M $R/nexora $R/boot/grub $OUTDIR
mount -t overlay overlay -o lowerdir=$LFS,upperdir=$W/upper,workdir=$W/work $M

echo "== 2/6 preparar a sessão live"
mount --bind /dev $M/dev; mount -t devpts devpts $M/dev/pts
mount -t proc proc $M/proc; mount -t sysfs sysfs $M/sys; mount -t tmpfs tmpfs $M/run
install -m755 "$PROJ/tools/iso/live-setup.sh" $M/tmp/live-setup.sh
[ -n "$DEVKEY" ] && install -m644 "$PROJ/vm/nexora_ed25519.pub" $M/tmp/nexora-dev-key.pub
chroot $M /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/root /bin/bash /tmp/live-setup.sh
rm -f $M/tmp/live-setup.sh
for d in dev/pts dev proc sys run; do umount $M/$d; done

echo "== 3/6 squashfs (zstd)"
mksquashfs $M $R/nexora/rootfs.sfs -noappend -comp zstd -Xcompression-level 15 -b 1M -quiet -progress \
    -wildcards -e 'sources' 'tools' 'lost+found' 'boot/efi/*' 'tmp/*' 'var/tmp/*' 'var/log/journal/*' \
                  'usr/share/doc/*' 'usr/share/gtk-doc/*' 'usr/lib/libLLVM*.a'
du -h $R/nexora/rootfs.sfs

echo "== 4/6 kernel e initramfs"
KERNEL=$(cd $LFS/boot && ls vmlinuz-* | sort -V | tail -1)
cp $LFS/boot/$KERNEL $R/boot/vmlinuz
"$HERE/mkinitramfs.sh" $LFS $R/boot/initramfs.img

echo "== 5/6 GRUB da Nexora (BIOS eltorito + UEFI)"
G=$W/grub; rm -rf $G; mkdir -p $G
cat > $G/early.cfg << EOF
search --no-floppy --set=root --label $LABEL
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF
MODS="normal configfile search search_label search_fs_file iso9660 part_gpt part_msdos fat ext2 linux echo test ls cat all_video gfxterm gzio"
cp $G/early.cfg $LFS/tmp/nexora-early.cfg
chroot $LFS /usr/bin/grub-mkimage -O i386-pc-eltorito -o /tmp/nexora-eltorito.img -p /boot/grub \
    -c /tmp/nexora-early.cfg biosdisk $MODS
chroot $LFS /usr/bin/grub-mkimage -O x86_64-efi -o /tmp/nexora-bootx64.efi -p /boot/grub \
    -c /tmp/nexora-early.cfg efi_gop efi_uga $MODS
mv $LFS/tmp/nexora-eltorito.img $R/boot/grub/eltorito.img
mv $LFS/tmp/nexora-bootx64.efi $G/BOOTX64.EFI
rm -f $LFS/tmp/nexora-early.cfg
for p in i386-pc x86_64-efi; do
    mkdir -p $R/boot/grub/$p
    cp $LFS/usr/lib/grub/$p/*.mod $LFS/usr/lib/grub/$p/*.lst $R/boot/grub/$p/
done
mkdir -p $R/EFI/BOOT && cp $G/BOOTX64.EFI $R/EFI/BOOT/BOOTX64.EFI
# imagem FAT da partição EFI da ISO
rm -f $G/efiboot.img
mkfs.vfat -C -n NEXORA_EFI $G/efiboot.img 4096 >/dev/null
mmd -i $G/efiboot.img ::/EFI ::/EFI/BOOT
mcopy -i $G/efiboot.img $G/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI

CMD="nexora.label=$LABEL"
cat > $R/boot/grub/grub.cfg << EOF
set default=0
set timeout=5
insmod all_video
set menu_color_normal=light-gray/black
set menu_color_highlight=black/cyan
set color_normal=light-gray/black

menuentry "Nexora Linux $VER  (live / install)" {
        linux  /boot/vmlinuz $CMD quiet loglevel=3 console=ttyS0,115200 console=tty0
        initrd /boot/initramfs.img
}
menuentry "Nexora Linux $VER  (live, safe graphics)" {
        linux  /boot/vmlinuz $CMD nomodeset quiet loglevel=3 console=ttyS0,115200 console=tty0
        initrd /boot/initramfs.img
}
menuentry "Nexora Linux $VER  (live, verbose boot)" {
        linux  /boot/vmlinuz $CMD console=ttyS0,115200 console=tty0
        initrd /boot/initramfs.img
}
EOF
echo "Nexora Linux $VER — $(date -u +%F)" > $R/nexora/VERSION

echo "== 6/6 ISO híbrida"
rm -f "$ISO"
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid $LABEL -appid "Nexora Linux $VER" -publisher "Nexora Linux" \
    -partition_offset 16 --mbr-force-bootable \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B $G/efiboot.img -appended_part_as_gpt \
    -c boot/boot.catalog \
    -b boot/grub/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    --grub2-mbr $LFS/usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot \
    -o "$ISO" $R 2>&1 | grep -vE '^xorriso : UPDATE|^$' | tail -5
(cd $OUTDIR && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
chown -R "${SUDO_USER:-samaral79}": $OUTDIR
[ -n "$DEVKEY" ] && echo "⚠  ISO de TESTE (tem a chave SSH de desenvolvimento no root)"
ls -lh "$ISO"
