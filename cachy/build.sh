#!/bin/bash
# Nexora (base CachyOS): gera a ISO live/instaladora num contentor CachyOS.
#   1. compila os pacotes da Nexora (cachy/pkgs) para um repositório local "nexora"
#   2. junta os pacotes que o instalador usa sem rede (Limine, snapper)
#   3. mkarchiso com o perfil cachy/iso
# Uso: ./cachy/build.sh [--dev-key]      (no Fedora, como utilizador do grupo docker)
#   --dev-key  ISO de TESTE: a chave SSH do projeto entra no root do live (nunca publicar)
# Resultado: cachy-out/nexora-<data>-x86_64.iso
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PROJ=$(cd "$HERE/.." && pwd)
DEVKEY=
[ "${1:-}" = --dev-key ] && DEVKEY=1
IMAGE=docker.io/cachyos/cachyos:latest
mkdir -p "$PROJ/cachy-cache/pkg" "$PROJ/cachy-out"

docker pull -q $IMAGE >/dev/null
# privilegiado: o mkarchiso monta sistemas de ficheiros e faz chroot
docker run --rm --privileged \
    -v "$PROJ":/proj:ro \
    -v "$PROJ/cachy-cache/pkg":/var/cache/pacman/pkg \
    -v "$PROJ/cachy-out":/out \
    -e DEVKEY="$DEVKEY" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    $IMAGE /bin/bash /proj/cachy/container-build.sh
ls -la "$PROJ"/cachy-out/*.iso
