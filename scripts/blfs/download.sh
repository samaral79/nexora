#!/bin/bash
# Descarrega as fontes BLFS de uns pacotes para $PROJ/sources-blfs (fora da imagem).
# Uso: ./scripts/blfs/download.sh <id-do-pacote>...   (ids do livro BLFS)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config.sh"
DEST=$PROJ/sources-blfs; mkdir -p "$DEST"; cd "$DEST"
python3 "$HERE/blfs.py" urls "$@" | while read -r url md5; do
    f=${url##*/}
    if [ ! -s "$f" ]; then
        wget -q --show-progress -c -O "$f.part" "$url" && mv "$f.part" "$f"
    fi
    if [ "$md5" != - ]; then
        echo "$md5  $f" | md5sum -c --quiet || { echo "md5 errado: $f"; exit 1; }
    fi
done
echo "✔ fontes em $DEST"
