#!/bin/bash
# Fase U (dentro do chroot, como root): atualizações do sistema por imagem A/B.
#   O systemd é recompilado com o systemd-boot (gestor de arranque com contagem de tentativas),
#   o systemd-sysupdate/updatectl (descarrega a versão nova para a partição livre) e o ukify
#   (junta kernel + initramfs + linha de comando num UKI). A imagem e o UKI de cada versão
#   saem do scripts/release/make-release.sh; o instalador põe o disco em A/B.
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
F=$N/flow
U=$N/update
LIVE=$N/iso
# de onde vêm as atualizações (o make-release.sh pode mudar isto em builds de teste)
URL=https://github.com/samaral79/nexora/releases/latest/download

s_pywheels() {
    # pyelftools: para compilar o systemd-boot; pefile: para o ukify
    pip3 install --no-index --no-deps --no-build-isolation \
        $SRC/$B/pyelftools-0.33-py3-none-any.whl $SRC/$B/pefile-2024.8.26-py3-none-any.whl
    python3 -c "import elftools, pefile"
}

p_systemd() {
    # as mesmas opções da fase A, mais o arranque e as atualizações
    sed -i -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in
    mkdir build && cd build
    meson setup .. --prefix=/usr --buildtype=release \
          -D default-dnssec=no -D firstboot=false -D install-tests=false \
          -D ldconfig=false -D man=disabled -D sysusers=true -D rpmmacrosdir=no \
          -D homed=disabled -D mode=release -D pam=enabled -D pamconfdir=/etc/pam.d \
          -D dev-kvm-mode=0660 -D nobody-group=nogroup \
          -D bootloader=enabled -D efi=true -D sbat-distro=nexora -D sbat-distro-summary="Nexora Linux" \
          -D sbat-distro-url=https://github.com/samaral79 \
          -D sysupdate=enabled -D sysupdated=enabled -D importd=enabled -D libcurl=enabled \
          -D ukify=enabled -D docdir=/usr/share/doc/systemd-261.2
    ninja
    ninja install
    rm -fv /usr/lib/systemd/system/systemd-update-utmp-runlevel.service
    ls /usr/lib/systemd/boot/efi/systemd-bootx64.efi /usr/lib/systemd/boot/efi/linuxx64.efi.stub \
       /usr/lib/systemd/systemd-sysupdate /usr/bin/updatectl /usr/bin/ukify /usr/lib/systemd/systemd-pull
}

s_update() {
    install -vdm755 /usr/lib/sysupdate.d /usr/lib/systemd/system/systemd-sysupdate.service.d
    for t in 10-nexora-root 20-nexora-uki; do
        sed "s|@URL@|$URL|" $U/$t.transfer > /usr/lib/sysupdate.d/$t.transfer
    done
    install -vm644 $U/sysupdate-nexora.conf /usr/lib/systemd/system/systemd-sysupdate.service.d/nexora.conf
    install -vDm644 $U/sshd-hostkeys.conf /usr/lib/systemd/system/sshd.service.d/nexora-hostkeys.conf
    # Xfce: o terminal é o Ptyxis (sem isto o Ctrl+Alt+T e a doca perguntavam qual usar)
    install -vDm644 $U/ptyxis-helper.desktop /usr/share/xfce4/helpers/ptyxis.desktop
    install -vdm755 /etc/xdg/xfce4
    grep -q '^TerminalEmulator=' /etc/xdg/xfce4/helpers.rc 2>/dev/null &&
        sed -i 's/^TerminalEmulator=.*/TerminalEmulator=ptyxis/' /etc/xdg/xfce4/helpers.rc ||
        echo "TerminalEmulator=ptyxis" >> /etc/xdg/xfce4/helpers.rc
    install -vm644 $U/50-nexora-sysupdate.rules /usr/share/polkit-1/rules.d/50-nexora-sysupdate.rules
    # chave pública das versões da Nexora (o sysupdate confirma o SHA256SUMS.gpg com ela)
    install -vm644 $U/nexora-release.pgp /usr/lib/systemd/import-pubring.pgp
    # procura e descarrega sozinho; a versão nova entra no próximo arranque
    systemctl enable systemd-sysupdate.timer
    # o live prepara-se no arranque (a imagem é a mesma que se instala)
    install -vdm755 /usr/lib/nexora
    install -vm755 $LIVE/live-setup.sh /usr/lib/nexora/live-setup
    # o atalho do instalador só aparece no live (o live-setup põe-no no menu)
    if [ -f /usr/share/applications/nexora-installer.desktop ]; then
        mv -v /usr/share/applications/nexora-installer.desktop /usr/lib/nexora/nexora-installer.desktop
    fi
}

s_flow() {
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    install -vm755 $N/installer/nexora-install-engine /usr/sbin/nexora-install-engine
    install -vm755 $N/installer/nexora-installer /usr/bin/nexora-installer
    install -vm644 $N/installer/nexora-installer.desktop /usr/lib/nexora/nexora-installer.desktop
    rm -f /usr/share/applications/nexora-installer.desktop
    install -vm755 $LIVE/live-setup.sh /usr/lib/nexora/live-setup
    python3 -c "import ast; ast.parse(open('/usr/bin/nexora-settings').read())"
}

T0=$SECONDS
step U.01-pywheels       s_pywheels
pkg  U.02-systemd        $B/systemd-261.2.tar.gz                p_systemd
step U.03-update         s_update
step U.04-flow           s_flow
echo "🔄 Fase U (atualizações A/B) completa em $(( (SECONDS - T0) / 60 )) min"
