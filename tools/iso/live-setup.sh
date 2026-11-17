#!/bin/bash
# Prepara a sessão live da Nexora (corre DENTRO da raiz da ISO, como root, via chroot).
# Tudo o que é só do live fica listado em /etc/nexora-live para o instalador o apagar.
set -euo pipefail
LIVEUSER=nexora
DEVKEY=$(cat /tmp/nexora-dev-key.pub 2>/dev/null || true)   # só em builds de teste

# utilizador de desenvolvimento e restos de testes não vão para a ISO
getent passwd lori >/dev/null && userdel -r lori 2>/dev/null || true
rm -f /etc/lightdm/lightdm.conf.d/99-teste-autologin.conf

# fstab do live: a raiz (squashfs + overlay) é montada pelo initramfs; nada de partições do
# sistema de desenvolvimento (o instalador escreve um fstab novo no disco de destino)
echo "# Nexora live: a raiz é montada pelo initramfs (squashfs + overlay em RAM)" > /etc/fstab

# utilizador live: sem senha, com sudo sem senha e login automático
getent passwd $LIVEUSER >/dev/null || useradd -m -c "Nexora Live" -G wheel,video,audio,input,users,lpadmin -s /bin/bash $LIVEUSER
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

# instalador: no ambiente de trabalho e a abrir sozinho no arranque
H=/home/$LIVEUSER
install -dm755 $H/Desktop $H/.config/autostart
install -m755 /usr/share/applications/nexora-installer.desktop $H/Desktop/nexora-installer.desktop
install -m644 /usr/share/applications/nexora-installer.desktop $H/.config/autostart/nexora-installer.desktop
chown -R $LIVEUSER:$LIVEUSER $H

cat > /etc/nexora-live << "EOF"
/etc/sudoers.d/90-nexora-live
/etc/lightdm/lightdm.conf.d/60-nexora-live.conf
/usr/share/applications/nexora-installer.desktop
EOF

# limpeza: nada de chaves, histórico nem identidade desta máquina na ISO
rm -rf /root/.ssh /root/.bash_history /root/.cache /home/*/.bash_history
rm -f /etc/ssh/ssh_host_*
rm -rf /var/lib/lightdm/.cache/lightdm-gtk-greeter /var/cache/lightdm/dmrc/*   # sessões lembradas dos testes
: > /etc/machine-id
rm -f /var/lib/systemd/random-seed
rm -rf /var/log/journal/* /tmp/* /var/tmp/*
find /var/log -type f -name '*.log' -delete 2>/dev/null || true

# chave de desenvolvimento (só em builds de teste: build-iso.sh --dev-key)
if [ -n "$DEVKEY" ]; then
    install -dm700 /root/.ssh
    echo "$DEVKEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "/root/.ssh" >> /etc/nexora-live
fi
echo "✔ live preparado (utilizador $LIVEUSER, login automático, instalador no arranque)"
