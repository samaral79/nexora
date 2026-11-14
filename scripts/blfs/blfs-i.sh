#!/bin/bash
# Fase I (dentro do chroot, como root): browser.
#   alsa-lib (o Firefox precisa da libasound; é também a base do som),
#   Firefox (binário oficial da Mozilla em /opt/firefox: compilá-lo pede clang e horas),
#   Firefox na doca (Xfce e Nexora Flow) e como browser por omissão.
source "$(dirname "$0")/lib.sh"
B=blfs
F=$(dirname "$0")/flow
FFVER=160.0

p_alsalib() { ./configure --prefix=/usr; make; make install; }

p_firefox() {
    rm -rf /opt/firefox
    mkdir -p /opt/firefox
    cp -a . /opt/firefox/
    ln -sfv /opt/firefox/firefox /usr/bin/firefox
    # as atualizações vêm com a Nexora (o /opt é do root: o Firefox não se atualiza sozinho)
    install -vdm755 /opt/firefox/distribution
    cat > /opt/firefox/distribution/policies.json << "EOF"
{
  "policies": {
    "DisableAppUpdate": true,
    "DontCheckDefaultBrowser": true,
    "DisableTelemetry": true
  }
}
EOF
    for s in 16 32 48 64 128; do
        install -vDm644 browser/chrome/icons/default/default$s.png \
            /usr/share/icons/hicolor/${s}x${s}/apps/firefox.png
    done
    cat > /usr/share/applications/firefox.desktop << "EOF"
[Desktop Entry]
Type=Application
Name=Firefox
GenericName=Web Browser
Comment=Browse the web
Exec=firefox %u
Icon=firefox
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=firefox
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=firefox --new-window

[Desktop Action new-private-window]
Name=New Private Window
Exec=firefox --private-window
EOF
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    update-desktop-database -q /usr/share/applications || true
}

s_defaults() {
    # browser por omissão (xdg-open, GTK e Xfce)
    cat > /etc/xdg/mimeapps.list << "EOF"
[Default Applications]
text/html=firefox.desktop
application/xhtml+xml=firefox.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
EOF
    install -vdm755 /etc/xdg/xfce4
    if [ -f /etc/xdg/xfce4/helpers.rc ]; then
        sed -i '/^WebBrowser=/d' /etc/xdg/xfce4/helpers.rc
    fi
    echo "WebBrowser=firefox" >> /etc/xdg/xfce4/helpers.rc
    # Firefox na doca do Xfce, logo a seguir aos ficheiros
    sed -i 's|/usr/share/applications/thunar.desktop;|/usr/share/applications/thunar.desktop;/usr/share/applications/firefox.desktop;|' \
        /etc/xdg/xfce4/panel/docklike.rc
    grep -q firefox.desktop /etc/xdg/xfce4/panel/docklike.rc
    # Nexora Flow: doca (eww) com o Firefox e nomes do ecrã de login em inglês
    install -vm644 $F/eww/eww.yuck $F/eww/eww.scss /usr/share/nexora-flow/eww/
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    niri validate -c /etc/niri/config.kdl
    sed -i -e 's/^Comment=.*/Comment=The Nexora desktop: windows on a scrolling strip/' \
        /usr/share/wayland-sessions/niri.desktop
    sed -i -e 's/^Name=.*/Name=Xfce (classic)/' /usr/share/xsessions/xfce.desktop
}

s_notify() {
    # o mako (Nexora Flow) também se registava como org.freedesktop.Notifications: no Xfce o D-Bus
    # podia acordá-lo em vez do xfce4-notifyd e a sessão ficava presa no arranque. No Flow o
    # mako é lançado pelo nexora-flow-start, por isso a ativação por D-Bus não faz falta.
    rm -fv /usr/share/dbus-1/services/fr.emersion.mako.service
}

s_installer() {
    # instalador em inglês e a gravar a sessão escolhida (as cópias da fase F ficaram antigas)
    I=$(dirname "$0")/installer
    install -vm755 $I/nexora-install-engine /usr/sbin/nexora-install-engine
    install -vm755 $I/nexora-installer /usr/bin/nexora-installer
    install -vm644 $I/nexora-installer.desktop /usr/share/applications/nexora-installer.desktop
}

T0=$SECONDS
pkg  I.01-alsa-lib   $B/alsa-lib-1.2.16.1.tar.bz2   p_alsalib
pkg  I.02-firefox    $B/firefox-$FFVER.tar.xz       p_firefox
step I.03-defaults   s_defaults
step I.04-notify     s_notify
step I.05-installer  s_installer
echo "🎉 Fase I (browser) completa em $(( (SECONDS - T0) / 60 )) min"
