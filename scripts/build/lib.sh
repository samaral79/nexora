# Funções comuns para compilar pacotes (como lfs ou dentro do chroot).
#   pkg  <nome> <tarball> <função>  -> extrai em $LFS/sources, entra na pasta e corre a função
#   step <nome> <função>            -> passo sem tarball (configs, limpeza, ...)
# Log em $LFS/sources/.logs/<nome>.log, marca .done/<nome> quando corre bem.
# O que já está feito é saltado, por isso podes relançar à vontade.
set -euo pipefail

SRC=$LFS/sources
LOGS=$SRC/.logs
DONE=$SRC/.done
mkdir -p "$LOGS" "$DONE"

_run() {
    local name=$1 fn=$2 t0=$SECONDS
    # NÃO pôr o subshell como condição de um if: aí o bash ignora o set -e lá dentro
    # e um passo a meio podia falhar sem ninguém dar por isso.
    local rc=0
    set +e
    ( set -euo pipefail; $fn ) > "$LOGS/$name.log" 2>&1
    rc=$?
    set -e
    if [ $rc -eq 0 ]; then
        touch "$DONE/$name"
        echo "✔  $name ($(( (SECONDS - t0) / 60 ))m$(( (SECONDS - t0) % 60 ))s)"
    else
        echo "✘  $name FALHOU. Últimas linhas de $LOGS/$name.log:"
        tail -25 "$LOGS/$name.log"
        exit 1
    fi
}

pkg() {
    local name=$1 tarball=$2 fn=$3
    [ -e "$DONE/$name" ] && { echo "⏭  $name (já feito)"; return; }
    echo "🔨 $name ..."
    cd "$SRC"
    local dir
    dir=$(set +o pipefail; tar -tf "$tarball" | head -1 | cut -d/ -f1)
    [ -n "$dir" ] && [ "$dir" != "." ] || { echo "não percebi a pasta de $tarball"; exit 1; }
    rm -rf "$dir"
    tar -xf "$tarball"
    cd "$dir"
    _run "$name" "$fn"
    cd "$SRC"
    rm -rf "$dir"
}

step() {
    local name=$1 fn=$2
    [ -e "$DONE/$name" ] && { echo "⏭  $name (já feito)"; return; }
    echo "🔨 $name ..."
    cd "$SRC"
    _run "$name" "$fn"
}

# Testes: corre, guarda o resultado no log e nunca pára o build
# (o resumo fica em .logs/<nome>.log; vê-se no fim com tests-summary)
t() {
    echo "=== TESTES: $* ==="
    "$@" || echo "=== TESTES COM FALHAS (exit $?) ==="
}
