#!/bin/bash
# Corre um capítulo como utilizador lfs, com o ambiente limpo do cap. 4.4.
# Uso: ./scripts/run-as-lfs.sh ch5
set -euo pipefail
source "$(dirname "$0")/config.sh"
CH=${1:?uso: $0 ch5}
mountpoint -q $LFS || { echo "$LFS não está montado: sudo ./scripts/mount.sh"; exit 1; }

# O lfs não consegue ler a minha home: copiar os scripts para dentro do disco
DEST=$LFS/sources/nexora-build
mkdir -p $DEST
cp "$(dirname "$0")"/build/*.sh $DEST/
chmod a+rx $DEST $DEST/*.sh

exec sudo -u lfs env -i HOME=/home/lfs TERM="$TERM" \
    bash -c "source ~/.bashrc && exec bash $DEST/$CH.sh"
