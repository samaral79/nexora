#!/bin/bash
# Prepara a imagem de uma versão da Nexora (corre DENTRO de uma cópia overlay do lfs.img, via chroot,
# chamado pelo scripts/release/make-release.sh). A imagem é igual para todos: nada de utilizadores,
# chaves, histórico ou identidade da máquina de desenvolvimento.
#   uso: image-setup.sh <versão> [url das atualizações]
set -euo pipefail
VER=${1:?versão}
URL=${2:-}

# ---------------------------------------------------------------- limpar o que é de desenvolvimento
for u in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do
    userdel -r "$u" 2>/dev/null || userdel "$u" || true
done
rm -f /etc/lightdm/lightdm.conf.d/99-claude-test.conf /etc/lightdm/lightdm.conf.d/99-teste-autologin.conf
rm -rf /root/.ssh /root/.bash_history /root/.cache /root/.cargo /root/.config /root/.local
rm -f /etc/ssh/ssh_host_*
# a senha do root do sistema de desenvolvimento não vai: root fica sem senha e bloqueado (sudo)
usermod -p '*' root
rm -rf /var/lib/lightdm/.cache/lightdm-gtk-greeter /var/cache/lightdm/dmrc/*
: > /etc/machine-id
rm -f /var/lib/systemd/random-seed
rm -rf /var/log/journal/* /tmp/* /var/tmp/* /var/spool/cups/c0* /var/spool/cups/d0*
find /var/log -type f \( -name '*.log' -o -name '*_log' \) -delete 2>/dev/null || true
rm -f /etc/cups/printers.conf* /etc/cups/subscriptions.conf* /etc/cups/ppd/* 2>/dev/null || true
# estado desta máquina que não pode ir para outras: identidade de rede (secret_key do NM),
# concessões DHCP, adaptadores Bluetooth, histórico de baterias, sementes, contas do ecrã de login
rm -rf /var/lib/NetworkManager/* /var/lib/bluetooth/* /var/lib/upower/* /var/lib/dbus/machine-id \
       /var/lib/systemd/timesync /var/lib/systemd/coredump /var/lib/systemd/backlight /var/lib/systemd/rfkill \
       /var/lib/systemd/linger /var/lib/lightdm/* /var/lib/AccountsService/users/* /var/lib/AccountsService/icons/* \
       /var/cache/lightdm 2>/dev/null || true

# ---------------------------------------------------------------- versão
OSR=/usr/lib/os-release
[ -L /etc/os-release ] || { cp /etc/os-release $OSR; ln -sf ../usr/lib/os-release /etc/os-release; }
sed -i -e '/^IMAGE_ID=/d' -e '/^IMAGE_VERSION=/d' $OSR
printf 'IMAGE_ID=nexora\nIMAGE_VERSION=%s\n' "$VER" >> $OSR
if [ -n "$URL" ]; then
    sed -i "s|^Path=http.*|Path=$URL|" /usr/lib/sysupdate.d/*.transfer
fi

# ---------------------------------------------------------------- disposição só de leitura
# o que muda vive em /var (partição nexora-data): pastas pessoais, root, /usr/local, /srv
mkdir -p /var/home /var/roothome /var/usrlocal /var/srv
chmod 700 /var/roothome
if [ ! -L /root ]; then cp -a /root/. /var/roothome/ 2>/dev/null || true; rm -rf /root; ln -s var/roothome /root; fi
if [ ! -L /home ]; then rm -rf /home; ln -s var/home /home; fi
if [ ! -L /srv ]; then rm -rf /srv; ln -s var/srv /srv; fi
if [ ! -L /usr/local ]; then cp -a /usr/local/. /var/usrlocal/; rm -rf /usr/local; ln -s ../var/usrlocal /usr/local; fi
# a partição EFI monta-se em /boot (os kernels vão dentro dos UKI)
find /boot -mindepth 1 -delete

cat > /etc/fstab << "EOF"
# /etc/fstab da Nexora (imagem A/B). A raiz (só de leitura), o /var e o /etc são montados pelo
# initramfs; a partição EFI (/boot) é acrescentada pelo instalador.
tmpfs  /tmp  tmpfs  mode=1777,nosuid,nodev  0 0
EOF

# utilizadores de sistema: o /etc/passwd fica na camada de cima depois de instalar, por isso os
# utilizadores novos de cada versão chegam pelo systemd-sysusers
SU=/usr/lib/sysusers.d/nexora-image.conf
{
    echo "# gerado pelo image-setup.sh (versão $VER)"
    awk -F: '$3 < 1000 && $1 != "root" {printf "g %s %s\n", $1, $3}' /etc/group
    awk -F: '($3 < 1000 || $3 == 65534) && $1 != "root" {
        printf "u %s %s:%s \"%s\" %s %s\n", $1, $3, $4, ($5 == "" ? "-" : $5), ($6 == "" ? "-" : $6), ($7 == "" ? "-" : $7)
    }' /etc/passwd
} > $SU
echo "✔ imagem preparada: versão $VER"
