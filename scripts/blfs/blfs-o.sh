#!/bin/bash
# Fase O (dentro do chroot, como root): acertos depois de testar o Flow na VM.
#   localsearch (o Nautilus aborta sem o schema do indexador), portal GNOME (cor de destaque e
#   tema escuro para as apps libadwaita, partilha de ecrã no niri), e reinstala os ficheiros
#   do Flow, do login e do instalador que foram corrigidos.
source "$(dirname "$0")/lib.sh"
B=blfs
F=$(dirname "$0")/flow
L=$(dirname "$0")/login
I=$(dirname "$0")/installer

mbuild() {
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}

p_localsearch() {
    mbuild -D man=false -D functional_tests=false -D sandbox_tests=false \
           -D battery_detection=none
}
p_portalgnome() { mbuild; }

s_portals() {
    # niri: o portal GNOME primeiro (Settings com accent-color, ScreenCast, FileChooser), o GTK para o resto
    cat > /usr/share/xdg-desktop-portal/niri-portals.conf << "EOF"
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
EOF
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

s_fixes() {
    # o libadwaita queixa-se do prefer-dark no settings.ini; o escuro vem do color-scheme (portal)
    cat > /etc/gtk-4.0/settings.ini << "EOF"
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Inter 10
EOF
    install -vDm644 $F/fuzzel.ini /etc/xdg/fuzzel/fuzzel.ini
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    niri validate -c /etc/niri/config.kdl
    install -vm644 $F/eww/eww.yuck $F/eww/eww.scss /usr/share/nexora-flow/eww/
    install -vDm644 $L/gtk.css /usr/share/themes/Nexora-Login/gtk-3.0/gtk.css
    install -vm755 $I/nexora-install-engine /usr/sbin/nexora-install-engine
    install -vm755 $I/nexora-installer /usr/bin/nexora-installer
    install -vm644 $I/nexora-installer.desktop /usr/share/applications/
}

T0=$SECONDS
pkg  O.01-localsearch   $B/localsearch-3.11.1.tar.xz              p_localsearch
pkg  O.02-portal-gnome  $B/xdg-desktop-portal-gnome-50.0.tar.xz   p_portalgnome
step O.03-portals       s_portals
step O.04-fixes         s_fixes
echo "🎉 Fase O (acertos do Flow) completa em $(( (SECONDS - T0) / 60 )) min"
