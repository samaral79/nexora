#!/bin/bash
# LFS 13.1, capítulo 10: fstab, kernel e GRUB (dentro do chroot, como root)
# O GRUB vai SÓ para a ESP do lfs.img (--removable, sem mexer na NVRAM do PC).
# Arranque por UEFI na VM (OVMF), sem initramfs: root=PARTUUID=...
source "$(dirname "$0")/lib.sh"

KVER=7.1.8
KNAME=vmlinuz-$KVER-nexora

# Partições do lfs.img, encontradas pelas labels (nunca pelo nome do disco)
ROOTDEV=$(blkid -L lfs-root)
ESPDEV=$(blkid -L LFS-ESP)
case "$ROOTDEV$ESPDEV" in */dev/loop*/dev/loop*) ;; *) echo "partições estranhas: $ROOTDEV $ESPDEV"; exit 1;; esac
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOTDEV")
[ -n "$ROOT_PARTUUID" ]

s_fstab() {
    cat > /etc/fstab << "EOF"
# Begin /etc/fstab

# file system     mount-point  type  options                                  dump fsck
LABEL=lfs-root    /            ext4  defaults                                 1    1
LABEL=LFS-ESP     /boot/efi    vfat  rw,relatime,codepage=437,iocharset=iso8859-1,umask=0077  0  2

# End /etc/fstab
EOF
}

p_kernel() {
    make mrproper
    make defconfig
    local c=scripts/config
    # o que o livro pede
    $c -d WERROR -e PSI -d PSI_DEFAULT_DISABLED -d IKHEADERS \
       -e CGROUPS -e MEMCG -e CGROUP_SCHED -d RT_GROUP_SCHED -d EXPERT \
       -e RELOCATABLE -e RANDOMIZE_BASE -e STACKPROTECTOR -e STACKPROTECTOR_STRONG \
       -e NET -e INET -e IPV6 \
       -d UEVENT_HELPER -e DEVTMPFS -e DEVTMPFS_MOUNT -d FW_LOADER_USER_HELPER \
       -e DMIID -e SYSFB_SIMPLEFB -e TTY -d LEGACY_TIOCSTI \
       -e DRM -e DRM_PANIC --set-str DRM_PANIC_SCREEN kmsg -e DRM_FBDEV_EMULATION \
       -e DRM_SIMPLEDRM -e FRAMEBUFFER_CONSOLE \
       -e INOTIFY_USER -e TMPFS -e TMPFS_POSIX_ACL \
       -e PCI -e PCI_MSI -e IOMMU_SUPPORT -e IRQ_REMAP -e X86_X2APIC
    # UEFI
    $c -e EFI -e EFI_STUB -e EFI_PARTITION -e VFAT_FS -e EFIVAR_FS \
       -e NLS_CODEPAGE_437 -e NLS_ISO8859_1
    # Nexora: correr bem em VM (KVM/QEMU) sem initramfs -> tudo built-in
    $c --set-str LOCALVERSION "-nexora" -d LOCALVERSION_AUTO \
       -e HYPERVISOR_GUEST -e PARAVIRT -e KVM_GUEST \
       -e VIRTIO -e VIRTIO_MENU -e VIRTIO_PCI -e VIRTIO_BLK -e VIRTIO_NET \
       -e VIRTIO_CONSOLE -e VIRTIO_BALLOON -e HW_RANDOM_VIRTIO \
       -e SCSI_VIRTIO -e DRM_VIRTIO_GPU -e DRM_BOCHS \
       -e BLK_DEV_NVME -e EXT4_FS -e EXT4_FS_POSIX_ACL -e EXT4_FS_SECURITY \
       -e SERIAL_8250 -e SERIAL_8250_CONSOLE \
       -e AUTOFS_FS -e FANOTIFY -e SECCOMP -e BPF_SYSCALL -e CGROUP_BPF
    # BLFS: llvmpipe precisa de VGEM; polkit/upower de user namespaces; libinput de evdev
    $c -e DRM_VGEM -e NAMESPACES -e USER_NS -e INPUT_EVDEV -e INPUT_UINPUT \
       -e SND -e SND_HDA_INTEL -e SND_HDA_CODEC_GENERIC -e HID_GENERIC -e USB_HID
    # live/ISO e instalação em hardware real: tudo built-in (o initramfs não carrega módulos)
    $c -e BLK_DEV_INITRD -e RD_ZSTD -e SQUASHFS -e SQUASHFS_XZ -e SQUASHFS_ZSTD -e SQUASHFS_XATTR \
       -e OVERLAY_FS -e ISO9660_FS -e JOLIET -e ZISOFS -e BLK_DEV_LOOP -e BLK_DEV_SR \
       -e ATA -e SATA_AHCI -e ATA_PIIX -e BLK_DEV_SD -e SCSI \
       -e USB_STORAGE -e USB_UAS -e USB_XHCI_HCD -e USB_EHCI_HCD -e USB_OHCI_HCD -e USB_UHCI_HCD \
       -e MMC -e MMC_SDHCI -e MMC_SDHCI_PCI -e MMC_BLOCK \
       -e FB_EFI -e SYSFB_SIMPLEFB -e DRM_SIMPLEDRM
    # hardware real (módulos; o firmware vem do linux-firmware, comprimido em zstd)
    $c -e FW_LOADER -e FW_LOADER_COMPRESS -e FW_LOADER_COMPRESS_ZSTD -e FW_LOADER_COMPRESS_XZ \
       -m ACPI_VIDEO -e BACKLIGHT_CLASS_DEVICE \
       -m DRM_AMDGPU -e DRM_AMDGPU_SI -e DRM_AMDGPU_CIK -e DRM_AMD_DC -m DRM_RADEON \
       -m DRM_I915 -m DRM_XE -m DRM_NOUVEAU \
       -m CFG80211 -m MAC80211 -e WLAN -e WIRELESS \
       -m IWLWIFI -m IWLDVM -m IWLMVM -m IWLMLD \
       -m ATH9K -m ATH10K -m ATH10K_PCI -m ATH11K -m ATH11K_PCI -m ATH12K \
       -m RTW88 -m RTW88_8822BE -m RTW88_8822CE -m RTW88_8821CE -m RTW88_8723DE \
       -m RTW89 -m RTW89_8852AE -m RTW89_8852BE -m RTW89_8852CE -m RTW89_8922AE -m RTL8XXXU \
       -m MT7921E -m MT7925E -m BRCMFMAC -e BRCMFMAC_PCIE -e BRCMFMAC_USB -m BRCMSMAC \
       -m R8169 -m E1000E -m IGB -m IGC -m ALX -m ATL1C -m TIGON3 \
       -m USB_USBNET -m USB_RTL8152 -m USB_NET_CDCETHER -m USB_NET_RNDIS_HOST \
       -m BT -m BT_HCIBTUSB -e BT_HCIBTUSB_RTL -e BT_HCIBTUSB_MTK \
       -m SND_HDA_CODEC_REALTEK -m SND_HDA_CODEC_HDMI -m SND_HDA_CODEC_CONEXANT \
       -m I2C_HID_ACPI -m HID_MULTITOUCH -m INPUT_TOUCHSCREEN
    # Flatpak/portais (FUSE), GTK4 (udmabuf), som USB e codecs HDA comuns
    $c -e FUSE_FS -m CUSE -e UDMABUF -m SND_USB_AUDIO -m SND_HDA_CODEC_ANALOG \
       -m SND_HDA_CODEC_CIRRUS -m SND_HDA_CODEC_VIA -m SND_HDA_CODEC_CA0132
    make olddefconfig
    # confirmar que o essencial ficou mesmo ligado
    for o in FW_LOADER_COMPRESS_ZSTD SQUASHFS OVERLAY_FS ISO9660_FS BLK_DEV_LOOP BLK_DEV_SR USB_STORAGE SATA_AHCI BLK_DEV_INITRD DRM_VGEM USER_NS INPUT_EVDEV DEVTMPFS DEVTMPFS_MOUNT EFI_STUB VIRTIO_BLK VIRTIO_PCI EXT4_FS VFAT_FS EFI_PARTITION CGROUPS FUSE_FS UDMABUF; do
        grep -qx "CONFIG_$o=y" .config || { echo "CONFIG_$o não ficou =y"; exit 1; }
    done
    make
    make modules_install
    cp -v arch/x86/boot/bzImage /boot/$KNAME
    cp -v System.map /boot/System.map-$KVER
    cp -v .config /boot/config-$KVER
    install -v -m755 -d /etc/modprobe.d
    cat > /etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
# End /etc/modprobe.d/usb.conf
EOF
}

s_grub() {
    mountpoint -q /boot/efi
    [ -f /boot/$KNAME ]
    # só ficheiros na ESP do lfs.img; --no-nvram = não toca nas entradas UEFI do PC
    grub-install --target=x86_64-efi --efi-directory=/boot/efi \
                 --boot-directory=/boot --removable --no-nvram
    [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]
    cat > /boot/grub/grub.cfg << EOF
# Begin /boot/grub/grub.cfg
set default=0
set timeout=3

insmod part_gpt
insmod ext2
insmod all_video
search --no-floppy --label lfs-root --set=root
set gfxpayload=keep

menuentry "Nexora Linux 13.1 (Linux $KVER)" {
        linux   /boot/$KNAME root=PARTUUID=$ROOT_PARTUUID ro quiet loglevel=3 console=ttyS0,115200 console=tty0
}
menuentry "Nexora Linux 13.1 (modo de recuperação)" {
        linux   /boot/$KNAME root=PARTUUID=$ROOT_PARTUUID ro console=ttyS0,115200 console=tty0 systemd.unit=rescue.target
}
EOF
}

T0=$SECONDS
step 10.2-fstab  s_fstab
pkg  10.3-kernel linux-$KVER.tar.xz p_kernel
step 10.4-grub   s_grub
echo "🎉 Capítulo 10 completo em $(( (SECONDS - T0) / 60 )) min"
