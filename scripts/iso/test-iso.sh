#!/bin/bash
# Testa a ISO da Nexora no QEMU com um disco vazio de 24 GB para instalar (não precisa de root).
# O disco arranca primeiro: vazio cai para a ISO, depois de instalar arranca o sistema (como tirar a pen).
# Uso: ./scripts/iso/test-iso.sh [--bios] [--disk] [--headless] [--fresh]
#   --bios      arranca em BIOS (SeaBIOS) em vez de UEFI
#   --disk      arranca só do disco instalado (sem a ISO)
#   --headless  sem janela; consola série em vm/iso-serial.log
#   --fresh     apaga o disco de teste antes de arrancar
set -euo pipefail
source "$(dirname "$0")/../config.sh"
ISO=$PROJ/iso/nexora-13.1-x86_64.iso
VM=$PROJ/vm
DISK=$VM/test-install.img
BIOS= ; ONLYDISK= ; HEADLESS= ; FRESH=
for a in "$@"; do case $a in
    --bios) BIOS=1 ;; --disk) ONLYDISK=1 ;; --headless) HEADLESS=1 ;; --fresh) FRESH=1 ;;
    *) echo "opção desconhecida: $a"; exit 1 ;; esac; done

mkdir -p $VM
[ -n "$FRESH" ] && rm -f $DISK $VM/test-OVMF_VARS.fd
[ -f $DISK ] || { truncate -s 24G $DISK; chattr +C $DISK 2>/dev/null || true; }
ARGS=(-enable-kvm -machine q35 -cpu host -smp 4 -m 4G -name "Nexora (teste da ISO)"
      -drive file=$DISK,format=raw,if=none,id=hd,cache=writeback -device virtio-blk-pci,drive=hd,bootindex=0
      -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2223-:22
      -device virtio-rng-pci -device qemu-xhci -device usb-tablet
      -qmp unix:$VM/test-qmp.sock,server=on,wait=off)
if [ -z "$BIOS" ]; then
    OVMF=/usr/share/edk2/ovmf
    [ -f $VM/test-OVMF_VARS.fd ] || cp $OVMF/OVMF_VARS.fd $VM/test-OVMF_VARS.fd
    ARGS+=(-drive if=pflash,format=raw,readonly=on,file=$OVMF/OVMF_CODE.fd
           -drive if=pflash,format=raw,file=$VM/test-OVMF_VARS.fd)
fi
[ -z "$ONLYDISK" ] && ARGS+=(-drive file=$ISO,media=cdrom,if=none,id=cd -device ide-cd,drive=cd,bootindex=1)

if [ -n "$HEADLESS" ]; then
    exec qemu-system-x86_64 "${ARGS[@]}" -device virtio-vga-gl -display egl-headless \
        -serial file:$VM/iso-serial.log -monitor none
else
    exec qemu-system-x86_64 "${ARGS[@]}" -device virtio-vga-gl,xres=1600,yres=900 -display gtk,gl=on -serial mon:stdio
fi
