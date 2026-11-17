#!/bin/bash
# Prepara a sessão live da Nexora. Corre no arranque do live (o initramfs faz chroot para aqui),
# dentro da camada em RAM: a imagem é a mesma que o instalador põe no disco e não muda.
# Instalado na imagem como /usr/lib/nexora/live-setup.
set -u
LIVEUSER=nexora

mkdir -p /var/home
# utilizador live: sem senha, com sudo sem senha e login automático
getent passwd $LIVEUSER >/dev/null ||
    useradd -m -c "Nexora Live" -G wheel,video,audio,input,users,lpadmin -s /bin/bash $LIVEUSER
passwd -d $LIVEUSER >/dev/null
echo "$LIVEUSER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-nexora-live
chmod 440 /etc/sudoers.d/90-nexora-live
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/60-nexora-live.conf << EOF
[Seat:*]
autologin-user=$LIVEUSER
autologin-user-timeout=0
autologin-session=xfce
EOF

# instalador: no menu, no ambiente de trabalho e a abrir sozinho no arranque
H=/home/$LIVEUSER
install -m644 /usr/lib/nexora/nexora-installer.desktop /usr/share/applications/nexora-installer.desktop
install -dm755 $H/Desktop $H/.config/autostart
install -m755 /usr/lib/nexora/nexora-installer.desktop $H/Desktop/nexora-installer.desktop
install -m644 /usr/lib/nexora/nexora-installer.desktop $H/.config/autostart/nexora-installer.desktop
chown -R $LIVEUSER:$LIVEUSER $H

# chave de desenvolvimento (só em ISOs de teste: build-iso.sh --dev-key)
if [ -f /tmp/dev-key.pub ]; then
    install -dm700 /root/.ssh
    install -m600 /tmp/dev-key.pub /root/.ssh/authorized_keys
    rm -f /tmp/dev-key.pub
fi
exit 0
