#!/bin/bash
# Corre capítulos de build como serviço do systemd (root), fora do terminal e com teto de memória:
# se a RAM apertar, morre o compilador e não o ambiente de trabalho do Fedora.
# Uso: sudo ./scripts/build-bg.sh blfs-b ch10 blfs-c     (segue com: journalctl -fu nexora-build)
#      sudo NX_JOBS=6 ./scripts/build-bg.sh ...          (menos jobs quando o PC está ocupado)
#      sudo NX_GAMING=1 ./scripts/build-bg.sh ...        (a jogar: 3 jobs, 4 GB, só usa CPU que sobre)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
[ $# -gt 0 ] || { echo "uso: $0 <cap>..."; exit 1; }
systemctl reset-failed nexora-build 2>/dev/null || true
CHAIN=""
for c in "$@"; do CHAIN+="$HERE/chroot.sh $c && "; done
CHAIN+="echo '🏁 cadeia completa: $*'"
# a jogar: o build só apanha CPU livre (CPUWeight=idle) e fica longe da RAM do jogo
if [ -n "${NX_GAMING:-}" ]; then
    LIM=(-p MemoryHigh=3500M -p MemoryMax=4500M -p MemorySwapMax=1G -p CPUWeight=idle -p Nice=19)
    NX_JOBS=${NX_JOBS:-3}
else
    LIM=(-p MemoryHigh=10500M -p MemoryMax=11500M -p MemorySwapMax=2G -p Nice=5)
fi
systemd-run --unit=nexora-build --collect \
    "${LIM[@]}" -p OOMScoreAdjust=900 -p IOSchedulingClass=idle \
    -E TERM=xterm-256color -E NX_JOBS="${NX_JOBS:-$(nproc)}" \
    /bin/bash -c "$CHAIN"
echo "▶ a correr em fundo. Ver: journalctl -fu nexora-build   |   parar: sudo systemctl stop nexora-build"
