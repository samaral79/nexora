#!/bin/bash
# Mostra o progresso do build da Nexora em tempo real. Ctrl-C para sair.
# Uso: ./scripts/progress.sh [ch8]   (sem argumento mostra todos os capítulos)
D=/mnt/lfs/sources/.done
L=/mnt/lfs/sources/.logs
B=$(dirname "$0")/build
FILES=$B/ch*.sh; [ -n "${1:-}" ] && FILES=$B/$1.sh
mapfile -t ALL < <(awk '/^(pkg|step) /{print $2}' $FILES)
ROWS=$(( $(tput lines 2>/dev/null || echo 40) - 12 ))
while true; do
    n=0; cur=""; lines=()
    for p in "${ALL[@]}"; do
        if [ -e "$D/$p" ]; then lines+=("  ✔ $p"); n=$((n+1))
        elif [ -e "$L/$p.log" ] && [ -z "$cur" ]; then lines+=("  🔨 $p  ← a compilar"); cur=$p
        else lines+=("  · $p"); fi
    done
    # mostra uma janela à volta do pacote atual
    start=$(( n - ROWS / 2 )); [ $start -lt 0 ] && start=0
    clear
    echo "  ── Nexora Linux · build ──  $(date +%H:%M:%S)"
    echo
    printf '%s\n' "${lines[@]:$start:$ROWS}"
    pct=$(( n * 100 / ${#ALL[@]} ))
    full=$(printf '%*s' $((pct / 4)) ''); empty=$(printf '%*s' $((25 - pct / 4)) '')
    printf '\n  [%s%s] %d%%  (%d/%d)\n' "${full// /█}" "${empty// /░}" $pct $n ${#ALL[@]}
    if [ -n "$cur" ]; then
        echo; echo "  último output de $cur:"
        tail -3 "$L/$cur.log" 2>/dev/null | cut -c1-100 | sed 's/^/    /'
    fi
    sleep 2
done
