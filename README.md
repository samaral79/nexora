# Nexora Linux

Distro feita do zero, com base no Linux From Scratch 13.1 (systemd).

## Regras
- O Fedora do shrek **não é tocado**. Tudo é compilado dentro de `lfs.img`, um disco virtual
  (ficheiro) montado em `/mnt/lfs` só durante o build.
- Nada de GRUB, partições ou bootloader no disco real. A Nexora arranca numa VM (QEMU) a partir de `lfs.img`.

## Scripts
- `scripts/00-host-setup.sh` (sudo): instala as dependências, cria e monta o `lfs.img` e cria o utilizador `lfs`
- `scripts/01-download.sh`: descarrega as fontes e verifica o md5
- `scripts/mount.sh` / `scripts/umount.sh` (sudo): montam e desmontam o disco virtual
