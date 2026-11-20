# Nexora Linux

Distro pessoal feita do zero, primeiro a partir do **Linux From Scratch 13.1 (systemd)** e agora também
como derivada do **CachyOS**, com o mesmo ambiente de trabalho: o **Nexora Flow** (niri com barra e doca
próprias), o tema ciano/azul-noite, o instalador gráfico e as afinações para jogos.

## Transferir

As ISOs estão nas [releases](https://github.com/samaral79/nexora/releases):

| Edição | O que é | Atualiza com |
|---|---|---|
| **Nexora (base CachyOS)** — a principal | pacotes do CachyOS e do Arch, kernel `linux-cachyos` (BORE), btrfs com snapshots | `pacman` (snapshot antes de cada atualização, escolhido no menu do Limine se algo partir) |
| **Nexora LFS 13.1** | tudo compilado de raiz por estes scripts, sistema só de leitura | imagens A/B (`systemd-sysupdate`) |

As duas arrancam em live (Xfce) com o instalador, precisam de UEFI e de um disco com 30 GB ou mais.
O instalador apaga o disco escolhido.

## O processo, passo a passo

Cada fase é um script; o histórico do git segue a mesma ordem.

| Fase | Script | O que junta |
|---|---|---|
| Caps. 4–10 do LFS | `scripts/build/` | toolchain, sistema base em terminal, kernel, arranque |
| A–F | `scripts/blfs/blfs-a.sh` … `blfs-f.sh` | BLFS: rede, PAM, sudo, Xorg, Xfce, Firefox, instalador |
| G–I | `blfs-g.sh` … `blfs-i.sh` | tema Nexora, Wayland, niri e o Nexora Flow |
| J–O | `blfs-j.sh` … `blfs-o.sh` | apps GTK4, Flatpak e loja, vídeo, cara nova, acertos |
| P | `blfs-p.sh` + `tools/aur/` | AUR isolado num contentor Arch (`nexora-aur`) |
| Q | `blfs-q.sh` | hardware real: portáteis, Bluetooth, som SOF, discos, zram |
| R | `blfs-r.sh` | jogos: kernel CachyOS + BORE, Mesa completo, GameMode |
| S–T | `blfs-s.sh`, `blfs-t.sh` | NVIDIA/Intel, impressoras, firewall, bloqueio de ecrã |
| U | `blfs-u.sh` + `tools/update/` | atualizações por imagem A/B |
| V | `blfs-v.sh` | desempenho: squashfs em todos os núcleos, MGLRU, schedutil, oomd, TRIM |
| W | `blfs-w.sh` | microcódigo do CPU, limites da sessão (GameMode, PipeWire), memória |
| Base CachyOS | `cachy/` | a Nexora como derivada do CachyOS, com `pacman` |

## Edição CachyOS (`cachy/`)

```bash
./cachy/build.sh            # ISO em cachy-out/ (Docker, contentor cachyos/cachyos)
```

- `cachy/pkgs/`: os pacotes da Nexora — `nexora-base` (marca, firewall, seletor NVIDIA, GameMode),
  `nexora-flow` (ambiente de trabalho e Definições), `nexora-theme`, `nexora-installer` e `eww`
  (não está nos repositórios do Arch).
- `cachy/iso/`: perfil do `mkarchiso`. A imagem vai em squashfs xz com filtro x86 para a ISO caber
  nos 2 GiB de uma release do GitHub.
- Instalação: partição EFI de 2 GiB e btrfs (`@`, `@home`, `@root`, `@srv`, `@cache`, `@log`, `@tmp`),
  Limine, snapper e snap-pac.

## Edição LFS

Compila-se dentro de `lfs.img`, um disco virtual montado em `/mnt/lfs` só durante o build; o sistema
onde se compila não é tocado.

- `scripts/00-host-setup.sh` (sudo): instala as dependências, cria e monta o `lfs.img` e cria o utilizador `lfs`
- `scripts/01-download.sh`: descarrega as fontes e verifica o md5
- `scripts/mount.sh` / `scripts/umount.sh` (sudo): montam e desmontam o disco virtual
- `scripts/build-bg.sh <fase>...` (sudo): compila fases em fundo (`NX_GAMING=1` para compilar enquanto se joga)
- `scripts/release/make-release.sh` (sudo): gera uma versão em `release/<versão>/`
- `scripts/iso/build-iso.sh` (sudo): faz a ISO a partir da última versão (`release/LATEST`)
- `tools/nexora-monitor/`: app (Rust + Slint) que acompanha o build

### Versões e atualizações (A/B)

Cada versão é uma imagem do sistema inteiro, igual para todos:

- `nexora_<versão>.root.raw`: o sistema (squashfs, só de leitura). O mesmo ficheiro serve para o live, para instalar e para atualizar.
- `nexora_<versão>.efi`: UKI (kernel + microcódigo + initramfs + linha de comando) para o systemd-boot.
- `SHA256SUMS` + `SHA256SUMS.gpg`: assinados com a chave "Nexora Linux Releases". A pública está em
  `tools/update/nexora-release.pgp`; a privada nunca entra no repositório.

O disco instalado tem quatro partições: EFI, sistema A, sistema B e `nexora-data` (montada em `/var`). O `/home`,
o `/root` e o `/usr/local` vivem em `/var`, e o `/etc` é a imagem com as tuas alterações por cima (overlay).
O `systemd-sysupdate` descarrega a versão nova para a partição livre e o systemd-boot arranca-a no arranque
seguinte. Se falhar 3 vezes, volta sozinho à versão anterior.

Versões e ISOs de teste (`--dev-key`) levam uma chave SSH de desenvolvimento e **nunca se publicam**.

## Licença

Os scripts, as ferramentas e os pacotes da Nexora estão sob a
[GNU GPL v3 ou posterior](LICENSE) (GPL-3.0-or-later). O software que os scripts descarregam e compilam
(LFS/BLFS, CachyOS, Arch e os restantes projetos) mantém as licenças dos respetivos autores.
