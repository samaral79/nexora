#!/bin/bash
# Entra no chroot da Nexora (root). Monta /dev, /proc, /sys e /run do host em $LFS (cap. 7.3).
# Uso:
#   sudo ./scripts/chroot.sh           -> shell interativa dentro da Nexora
#   sudo ./scripts/chroot.sh ch7       -> corre scripts/build/ch7.sh lá dentro
set -euo pipefail
source "$(dirname "$0")/config.sh"
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
mountpoint -q $LFS || "$(dirname "$0")/mount.sh"

# 7.2: passar a posse para root (só faz algo enquanto houver ficheiros do lfs)
chown --from lfs -R root:root $LFS/{usr,var,etc,lib64}
[ -d $LFS/tools ] && chown --from lfs -R root:root $LFS/tools

# 7.3: sistemas de ficheiros virtuais (idempotente)
mkdir -p $LFS/{dev,proc,sys,run}
mountpoint -q $LFS/dev     || mount -v --bind /dev $LFS/dev
mountpoint -q $LFS/dev/pts || mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mountpoint -q $LFS/proc    || mount -vt proc proc $LFS/proc
mountpoint -q $LFS/sys     || mount -vt sysfs sysfs $LFS/sys
mountpoint -q $LFS/run     || mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
    install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
    mountpoint -q $LFS/dev/shm || mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

# Fontes do BLFS (ficam no projeto, fora da imagem)
mkdir -p $PROJ/sources-blfs $LFS/sources/blfs
mountpoint -q $LFS/sources/blfs || mount --bind $PROJ/sources-blfs $LFS/sources/blfs
# DNS dentro do chroot: só no /run (tmpfs), a imagem não é tocada
mkdir -p $LFS/run/systemd/resolve
cat /etc/resolv.conf > $LFS/run/systemd/resolve/stub-resolv.conf

# Scripts de build visíveis lá dentro em /sources/nexora-build
DEST=$LFS/sources/nexora-build
mkdir -p $DEST
cp "$(dirname "$0")"/build/*.sh "$(dirname "$0")"/blfs/*.sh $DEST/
mkdir -p $DEST/installer && cp -a "$(dirname "$0")"/../tools/installer/. $DEST/installer/
mkdir -p $DEST/flow && cp -a "$(dirname "$0")"/../tools/flow/. $DEST/flow/
mkdir -p $DEST/login && cp -a "$(dirname "$0")"/../tools/login/. $DEST/login/
mkdir -p $DEST/aur && cp -a "$(dirname "$0")"/../tools/aur/. $DEST/aur/

ENV=(HOME=/root TERM="$TERM" PS1='(nexora chroot) \u:\w\$ '
     PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j${NX_JOBS:-$(nproc)}" TESTSUITEFLAGS="-j${NX_JOBS:-$(nproc)}"
     NX_JOBS="${NX_JOBS:-$(nproc)}" LFS=)
if [ $# -gt 0 ]; then
    chroot "$LFS" /usr/bin/env -i "${ENV[@]}" /bin/bash /sources/nexora-build/$1.sh
else
    chroot "$LFS" /usr/bin/env -i "${ENV[@]}" /bin/bash --login
fi
