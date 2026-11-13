#!/bin/bash
# Corre capítulos de build como serviço do systemd (root), fora do terminal e com teto de memória:
# se a RAM apertar, morre o compilador e não o ambiente de trabalho do Fedora.
# Uso: sudo ./scripts/build-bg.sh blfs-b ch10 blfs-c     (segue com: journalctl -fu nexora-build)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
[ $# -gt 0 ] || { echo "uso: $0 <cap>..."; exit 1; }
systemctl reset-failed nexora-build 2>/dev/null || true
CHAIN=""
for c in "$@"; do CHAIN+="$HERE/chroot.sh $c && "; done
CHAIN+="echo '🏁 cadeia completa: $*'"
systemd-run --unit=nexora-build --collect \
    -p MemoryHigh=10500M -p MemoryMax=11500M -p MemorySwapMax=2G -p OOMScoreAdjust=900 \
    -p Nice=5 -p IOSchedulingClass=idle \
    -E TERM=xterm-256color \
    /bin/bash -c "$CHAIN"
echo "▶ a correr em fundo. Ver: journalctl -fu nexora-build   |   parar: sudo systemctl stop nexora-build"
