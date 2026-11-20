#!/bin/bash
# Gera uma versão da Nexora a partir do lfs.img (root, no Fedora):
#   release/<versão>/nexora_<versão>.root.raw   imagem do sistema (squashfs, só de leitura)
#   release/<versão>/nexora_<versão>.efi        UKI: kernel + initramfs + linha de comando
#   release/<versão>/SHA256SUMS(.gpg)           o que o systemd-sysupdate descarrega e confirma
#   release/<versão>/boot/                      kernel e initramfs soltos (para o GRUB da ISO)
# A imagem é a mesma para atualizar, instalar e para o live.
#
# Uso: sudo ./scripts/release/make-release.sh [--version V] [--url URL]
#   --version  por omissão 13.1.AAAAMMDD (e .2, .3... se já houver uma nesse dia)
#   --url      de onde a imagem vai buscar as atualizações (por omissão a do GitHub, fase U);
#              p.ex. http://10.0.2.2:8000 para testar na VM com um servidor no Fedora
#   --dev-key  versão de TESTE: a chave SSH do projeto entra no root (nunca publicar)
# A assinatura usa a chave em ~/.local/share/nexora-release/gnupg (fora do repositório).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/../config.sh"
[ "$EUID" -eq 0 ] || { echo "corre com sudo"; exit 1; }
USR=${SUDO_USER:-samaral79}
UHOME=$(getent passwd "$USR" | cut -d: -f6)
GNUPGHOME=$UHOME/.local/share/nexora-release/gnupg

VER= URL= DEVKEY=
while [ $# -gt 0 ]; do
    case $1 in
        --version) VER=$2; shift 2 ;;
        --url)     URL=$2; shift 2 ;;
        --dev-key) DEVKEY=1; shift ;;
        *) echo "opção desconhecida: $1"; exit 1 ;;
    esac
done
if [ -z "$VER" ]; then
    base=$LFS_VERSION.$(date +%Y%m%d); VER=$base; n=1
    while [ -d "$PROJ/release/$VER" ]; do n=$((n+1)); VER=$base.$n; done
fi
[[ "$VER" =~ ^[0-9][0-9.]*$ ]] || { echo "versão inválida: $VER"; exit 1; }
OUT=$PROJ/release/$VER
W=$PROJ/release-work
M=$W/merged
[ -e "$OUT" ] && { echo "já existe $OUT"; exit 1; }
[ -f "$GNUPGHOME/pubring.kbx" ] || { echo "falta a chave de assinatura em $GNUPGHOME"; exit 1; }

if pgrep -f "qemu-system.*file=$IMG" >/dev/null; then echo "Desliga a VM primeiro"; exit 1; fi
mountpoint -q $LFS || "$HERE/../mount.sh"
for d in sources/blfs dev/shm dev/pts dev proc sys run; do mountpoint -q $LFS/$d && umount $LFS/$d; done

cleanup() {
    for d in dev/pts dev proc sys run; do mountpoint -q $M/$d && umount -l $M/$d || true; done
    mountpoint -q $M && umount -l $M || true
}
trap cleanup EXIT

echo "== 1/5 cópia overlay do lfs.img (versão $VER)"
cleanup
rm -rf $W
mkdir -p $W/upper $W/work $M $OUT/boot
mount -t overlay overlay -o lowerdir=$LFS,upperdir=$W/upper,workdir=$W/work $M

echo "== 2/5 preparar a imagem"
mount --bind /dev $M/dev; mount -t devpts devpts $M/dev/pts
mount -t proc proc $M/proc; mount -t sysfs sysfs $M/sys; mount -t tmpfs tmpfs $M/run
install -m755 "$PROJ/tools/update/image-setup.sh" $M/run/image-setup.sh
chroot $M /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/ /bin/bash /run/image-setup.sh "$VER" "$URL"
# símbolos de depuração fora (só na cópia; o lfs.img fica com eles)
install -m755 "$PROJ/tools/update/strip-image.py" $M/run/strip-image.py
chroot $M /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/ /usr/bin/python3 /run/strip-image.py
if [ -n "$DEVKEY" ]; then
    install -dm700 $M/var/roothome/.ssh
    install -m600 "$PROJ/vm/nexora_ed25519.pub" $M/var/roothome/.ssh/authorized_keys
    touch $OUT/TESTE-COM-CHAVE-DE-DESENVOLVIMENTO
    echo "   ⚠ versão de TESTE (chave SSH de desenvolvimento no root)"
fi

echo "== 3/5 kernel, initramfs e UKI"
KERNEL=$(cd $LFS/boot && ls vmlinuz-*-nexora | sort -V | tail -1)
KVER=${KERNEL#vmlinuz-}
cp $LFS/boot/$KERNEL $OUT/boot/vmlinuz
"$PROJ/scripts/iso/mkinitramfs.sh" $M $OUT/boot/initramfs.img $W/ucode.img
install -dm755 $M/run/uki
cp $OUT/boot/vmlinuz $OUT/boot/initramfs.img $W/ucode.img $M/run/uki/
# o microcódigo só vai no UKI (sistema instalado); o live arranca sem ele (a ISO não cabe)
chroot $M /usr/bin/env -i PATH=/usr/bin:/usr/sbin HOME=/ /usr/bin/ukify build \
    --linux=/run/uki/vmlinuz --initrd=/run/uki/ucode.img --initrd=/run/uki/initramfs.img --uname="$KVER" \
    --cmdline="root=PARTLABEL=nexora_$VER ro quiet loglevel=3" \
    --os-release=@/usr/lib/os-release --output=/run/uki/nexora_$VER.efi
cp $M/run/uki/nexora_$VER.efi $OUT/
for d in dev/pts dev proc sys run; do umount $M/$d; done

echo "== 4/5 imagem do sistema (squashfs zstd)"
# só o kernel mais recente vai para a imagem
OLDK=()
for k in $(cd $LFS/boot && ls vmlinuz-*-nexora | sort -V | head -n -1); do
    OLDK+=("usr/lib/modules/${k#vmlinuz-}")
done
mksquashfs $M $OUT/nexora_$VER.root.raw -noappend -comp zstd -Xcompression-level 22 -b 1M -quiet -progress \
    -wildcards -e 'sources' 'tools' 'lost+found' 'tmp/*' 'var/tmp/*' 'var/log/journal/*' 'run/*' \
                  'usr/share/doc/*' 'usr/share/gtk-doc/*' 'usr/lib/libLLVM*.a' 'usr/lib/libclang*.a' \
                  'usr/lib/firmware/intel-ucode' \
                  "${OLDK[@]}"

echo "== 5/5 SHA256SUMS assinado"
(cd $OUT && sha256sum nexora_$VER.root.raw nexora_$VER.efi > SHA256SUMS)
chown -R "$USR": $PROJ/release
sudo -u "$USR" env GNUPGHOME="$GNUPGHOME" gpg --batch --yes --detach-sign \
    --local-user "Nexora Linux Releases" --output $OUT/SHA256SUMS.gpg $OUT/SHA256SUMS
sudo -u "$USR" env GNUPGHOME="$GNUPGHOME" gpg --batch --verify $OUT/SHA256SUMS.gpg $OUT/SHA256SUMS
if [ -z "$DEVKEY" ]; then   # as versões de teste nunca passam a ser a "última" (é dessa que sai a ISO)
    echo "$VER" > $PROJ/release/LATEST
    chown "$USR": $PROJ/release/LATEST
fi
ls -lh $OUT
echo "✔ versão $VER pronta em $OUT"
