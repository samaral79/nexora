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
- `scripts/build-bg.sh <fase>...` (sudo): compila fases em fundo (`NX_GAMING=1` para compilar enquanto se joga)
- `scripts/release/make-release.sh` (sudo): gera uma versão em `release/<versão>/`
- `scripts/iso/build-iso.sh` (sudo): faz a ISO a partir da última versão (`release/LATEST`)

## Versões e atualizações (A/B)
Cada versão é uma imagem do sistema inteiro, igual para todos:

- `nexora_<versão>.root.raw`: o sistema (squashfs, só de leitura). O mesmo ficheiro serve para o live, para instalar e para atualizar.
- `nexora_<versão>.efi`: UKI (kernel + initramfs + linha de comando) para o systemd-boot.
- `SHA256SUMS` + `SHA256SUMS.gpg`: assinados com a chave "Nexora Linux Releases". A privada fica em
  `~/.local/share/nexora-release/gnupg`, fora do repositório; a pública está em `tools/update/nexora-release.pgp`.

O disco instalado tem quatro partições: EFI, sistema A, sistema B e `nexora-data` (montada em `/var`). O `/home`,
o `/root` e o `/usr/local` vivem em `/var`, e o `/etc` é a imagem com as tuas alterações por cima (overlay).
O `systemd-sysupdate` descarrega a versão nova para a partição livre e o systemd-boot arranca-a no arranque
seguinte. Se falhar 3 vezes, volta sozinho à versão anterior. Nas Definições, a página Updates mostra o estado.

Publicar uma versão (sempre revisto antes): criar o repositório `samaral79/nexora` no GitHub e uma release com
os quatro ficheiros de `release/<versão>/` (sem a pasta `boot/`). As máquinas procuram em
`https://github.com/samaral79/nexora/releases/latest/download`.

Versões de teste: `make-release.sh --dev-key --url http://10.0.2.2:8000` (a chave SSH de desenvolvimento vai no
root e o URL aponta para um servidor no Fedora). Estas versões **nunca se publicam**.
