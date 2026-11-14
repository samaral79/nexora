#!/bin/bash
# Arranca a Nexora no QEMU (UEFI via OVMF, KVM). Não precisa de root.
# Uso: ./scripts/run-vm.sh            -> janela gráfica (3D por virgl) + consola série neste terminal
#      ./scripts/run-vm.sh --headless -> só série, log em vm/serial.log (para testes)
set -euo pipefail
source "$(dirname "$0")/config.sh"

# Nunca arrancar com o disco montado no Fedora (estragava o ext4)
if mountpoint -q "$LFS" || [ -n "$(losetup -j "$IMG" 2>/dev/null)" ]; then
    echo "O lfs.img ainda está montado no Fedora. Primeiro: sudo ./scripts/umount.sh"; exit 1
fi

OVMF=/usr/share/edk2/ovmf
VM=$PROJ/vm; mkdir -p "$VM"
[ -f "$VM/OVMF_VARS.fd" ] || cp "$OVMF/OVMF_VARS.fd" "$VM/OVMF_VARS.fd"

ARGS=(-enable-kvm -machine q35 -cpu host -smp 4 -m 4G -name "Nexora Linux"
      -drive if=pflash,format=raw,readonly=on,file=$OVMF/OVMF_CODE.fd
      -drive if=pflash,format=raw,file=$VM/OVMF_VARS.fd
      -drive file=$IMG,format=raw,if=virtio,cache=writeback
      -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
      -device virtio-rng-pci
      -device qemu-xhci -device usb-tablet
      -qmp unix:$VM/qmp.sock,server=on,wait=off)

if [ "${1:-}" = --headless ]; then
    exec qemu-system-x86_64 "${ARGS[@]}" -device virtio-vga-gl -display egl-headless \
        -serial file:$VM/serial.log -monitor none
else
    exec qemu-system-x86_64 "${ARGS[@]}" -device virtio-vga-gl,xres=1600,yres=900 -display gtk,gl=on \
        -serial mon:stdio
fi
