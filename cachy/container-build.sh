#!/bin/bash
# Corre dentro do contentor CachyOS (lançado pelo cachy/build.sh). O projeto está em /proj (só
# leitura), a cache de pacotes em /var/cache/pacman/pkg e a ISO sai para /out.
set -euo pipefail
P=/proj
C=$P/cachy
W=/work
PKGS=(eww nexora-theme nexora-base nexora-flow nexora-installer)
# instaladas no sistema pelo instalador, não no live (no live não há partição EFI para gerir)
OFFLINE=(limine-mkinitcpio-hook limine-snapper-sync)

msg() { printf '\n==> %s\n' "$*"; }

msg "contentor: atualizar e instalar as ferramentas"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacman -Syu --noconfirm --needed archiso grub base-devel git sudo cargo sassc gtk3 gtk-layer-shell \
    libdbusmenu-gtk3 >/dev/null
rm -rf $W && mkdir -p $W/repo $W/pkgs $W/offline
id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

msg "pacotes da Nexora"
cp -r $C/pkgs/. $W/pkgs/
B=$P/sources-blfs
mkdir -p $W/pkgs/{eww,nexora-theme,nexora-base,nexora-flow,nexora-installer}/files
cp $B/eww-0.6.0.tar.gz $W/pkgs/eww/files/
cp $B/Colloid-gtk-theme-2026-08-08.tar.gz $B/Bibata-Modern-Classic-2.0.7.tar.xz \
   $B/papirus-folders-1.14.0.tar.gz $B/nexora-aurora.png $B/nexora-wallpaper.png $B/nexora-logo.svg \
   $W/pkgs/nexora-theme/files/
cp -r $B/wallpapers $W/pkgs/nexora-theme/files/
cp $P/tools/login/gtk.css $W/pkgs/nexora-theme/files/login-gtk.css
cp -r $P/tools/flow $W/pkgs/nexora-base/files/flow
cp -r $P/tools/flow $W/pkgs/nexora-flow/files/flow
cp $P/tools/installer/nexora-installer $P/tools/installer/nexora-installer.desktop $W/pkgs/nexora-installer/files/
chown -R builder: $W/pkgs
for p in "${PKGS[@]}"; do
    msg "makepkg $p"
    (cd $W/pkgs/$p && sudo -u builder makepkg -fd --noconfirm)
    cp $W/pkgs/$p/*.pkg.tar.zst $W/repo/
done
repo-add -q $W/repo/nexora.db.tar.gz $W/repo/*.pkg.tar.zst
ls -la $W/repo

msg "pacotes para o instalador (sem rede): ${OFFLINE[*]}"
pacman -Sw --noconfirm --cachedir $W/offline "${OFFLINE[@]}" >/dev/null
for p in "${OFFLINE[@]}"; do ls $W/offline/$p-[0-9]*.pkg.tar.zst >/dev/null; done
find $W/offline -name '*.pkg.tar.zst' ! -name 'limine-*' -delete
ls $W/offline

msg "perfil da ISO"
cp -r $C/iso $W/profile
A=$W/profile/airootfs
install -dm755 $A/opt/nexora/offline
cp $W/offline/*.pkg.tar.zst $A/opt/nexora/offline/
# serviços ligados no live (e no sistema instalado, que é uma cópia do live)
S=$A/etc/systemd/system
mkdir -p $S/multi-user.target.wants $S/sysinit.target.wants $S/timers.target.wants $S/bluetooth.target.wants
for u in NetworkManager cups avahi-daemon power-profiles-daemon nftables systemd-oomd; do
    ln -sf /usr/lib/systemd/system/$u.service $S/multi-user.target.wants/$u.service
done
ln -sf /usr/lib/systemd/system/bluetooth.service $S/bluetooth.target.wants/bluetooth.service
ln -sf /usr/lib/systemd/system/nexora-gpu-select.service $S/sysinit.target.wants/nexora-gpu-select.service
ln -sf /usr/lib/systemd/system/fstrim.timer $S/timers.target.wants/fstrim.timer
ln -sf /usr/lib/systemd/system/lightdm.service $S/display-manager.service
ln -sf /usr/lib/systemd/system/graphical.target $S/default.target
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service $S/dbus-org.freedesktop.nm-dispatcher.service
# ISO de teste: a chave SSH do projeto no root do live e o sshd ligado
if [ -n "${DEVKEY:-}" ]; then
    install -dm700 $A/root/.ssh
    install -m600 $P/vm/nexora_ed25519.pub $A/root/.ssh/authorized_keys
    ln -sf /usr/lib/systemd/system/sshd.service $S/multi-user.target.wants/sshd.service
    echo openssh >> $W/profile/packages.x86_64
    echo "   ⚠ ISO de TESTE (chave SSH de desenvolvimento no root)"
fi

msg "mkarchiso"
mkarchiso -v -r -w $W/archiso -o $W/out $W/profile
ISO=$(ls $W/out/*.iso)
NAME=$(basename "$ISO")
[ -n "${DEVKEY:-}" ] && NAME=${NAME%.iso}-TESTE.iso
cp "$ISO" /out/$NAME
(cd /out && sha256sum "$NAME" > "$NAME.sha256")
chown "${HOST_UID:-1000}:${HOST_GID:-1000}" /out/$NAME /out/$NAME.sha256
msg "✔ /out/$NAME ($(du -h /out/$NAME | cut -f1))"
