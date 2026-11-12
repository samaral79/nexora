#!/bin/bash
# Prepara o host (shrek) para o LFS. Correr como root: sudo ./00-host-setup.sh
# - instala dependências em falta
# - cria um disco virtual (lfs.img) com GPT: ESP 512M + raiz ext4
# - monta em $LFS, cria a estrutura base e o utilizador lfs
set -euo pipefail
source "$(dirname "$0")/config.sh"
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }

dnf5 install -y bison m4 patch texinfo grep wget dosfstools e2fsprogs

if [ ! -e "$IMG" ]; then
    touch "$IMG"
    chattr +C "$IMG" 2>/dev/null || true   # sem CoW no btrfs (imagem de disco)
    truncate -s "$IMG_SIZE" "$IMG"
    chown samaral79: "$IMG"
    sfdisk "$IMG" <<EOF
label: gpt
size=512M, type=uefi, name=ESP
type=linux, name=lfs-root
EOF
    LOOP=$(losetup -fP --show "$IMG")
    mkfs.vfat -F32 -n LFS-ESP "${LOOP}p1"
    mkfs.ext4 -q -L lfs-root "${LOOP}p2"
    losetup -d "$LOOP"
fi

"$(dirname "$0")/mount.sh"

# Estrutura do capítulo 4
mkdir -pv $LFS/{etc,var,tools,sources} $LFS/usr/{bin,lib,sbin}
chmod -v a+wt $LFS/sources
for i in bin lib sbin; do [ -e $LFS/$i ] || ln -sv usr/$i $LFS/$i; done
case $(uname -m) in x86_64) mkdir -pv $LFS/lib64 ;; esac

# Utilizador lfs
if ! id lfs &>/dev/null; then
    groupadd lfs
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
    passwd -l lfs   # sem senha; entra-se com `sudo -u lfs -i`
fi
chown -v lfs $LFS/{usr{,/*},var,etc,tools,lib64}
chown -v lfs $LFS/{bin,lib,sbin} -h

# Ambiente limpo do utilizador lfs (cap. 4.4)
cat > /home/lfs/.bash_profile <<'EOF'
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF
cat > /home/lfs/.bashrc <<EOF
set +h
umask 022
LFS=$LFS
LC_ALL=POSIX
LFS_TGT=$LFS_TGT
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:\$PATH; fi
PATH=\$LFS/tools/bin:\$PATH
CONFIG_SITE=\$LFS/usr/share/config.site
MAKEFLAGS=$MAKEFLAGS
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE MAKEFLAGS
EOF
chown lfs:lfs /home/lfs/.bash_profile /home/lfs/.bashrc

echo "✔ Host pronto. $LFS montado."
