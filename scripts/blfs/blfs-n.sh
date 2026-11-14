#!/bin/bash
# Fase N (dentro do chroot, como root): a cara nova da Nexora.
#   agente polkit, app Definições, barra/doca/painéis novos do Flow, fundos novos,
#   ecrã de login redesenhado, apps por omissão (GTK4) e GTK4/libadwaita escuros com ciano.
source "$(dirname "$0")/lib.sh"
B=blfs
F=$(dirname "$0")/flow
L=$(dirname "$0")/login
W=/sources/blfs/wallpapers

p_polkitgnome() {
    patch -Np1 -i ../blfs/polkit-gnome-0.105-consolidated_fixes-1.patch
    ./configure --prefix=/usr
    make
    make install
    install -vdm755 /etc/xdg/autostart
    cat > /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop << "EOF"
[Desktop Entry]
Name=PolicyKit Authentication Agent
Exec=/usr/libexec/polkit-gnome-authentication-agent-1
Terminal=false
Type=Application
NoDisplay=true
OnlyShowIn=XFCE;niri;
EOF
}

s_flow() {
    install -vm755 $F/bin/nexora-flow-start $F/bin/nexora-flow-niri $F/bin/nexora-flow-status /usr/bin/
    install -vdm755 /usr/share/nexora-flow/eww
    install -vm644 $F/eww/eww.yuck $F/eww/eww.scss /usr/share/nexora-flow/eww/
    install -vDm644 $F/fuzzel.ini /etc/xdg/fuzzel/fuzzel.ini
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    niri validate -c /etc/niri/config.kdl
    # app Definições
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    install -vm644 $F/settings/org.nexora.Settings.desktop /usr/share/applications/
    python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1"); from gi.repository import Adw'
}

s_wallpapers() {
    for f in nexora-dusk nexora-tide nexora-graphite nexora-login; do
        install -vDm644 $W/$f.png /usr/share/backgrounds/nexora/$f.png
    done
}

s_login() {
    # tema próprio do greeter: o Nexora escuro + cartão de vidro, fundo sem logótipo
    install -vDm644 $L/gtk.css /usr/share/themes/Nexora-Login/gtk-3.0/gtk.css
    cat > /usr/share/themes/Nexora-Login/index.theme << "EOF"
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Nexora-Login
Comment=Nexora login screen
EOF
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
background = /usr/share/backgrounds/nexora/nexora-login.png
user-background = false
theme-name = Nexora-Login
icon-theme-name = Papirus-Dark
cursor-theme-name = Bibata-Modern-Classic
cursor-theme-size = 24
font-name = Inter 11
default-user-image = /usr/share/icons/hicolor/scalable/apps/nexora.svg
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a %d %b  ·  %H:%M
position = 50%,center 52%,center
round-user-image = true
EOF
}

s_defaults() {
    # GTK4/libadwaita: escuro, ciano, fontes e ícones da Nexora (valores por omissão do sistema)
    cat > /usr/share/glib-2.0/schemas/90_nexora.gschema.override << "EOF"
[org.gnome.desktop.interface]
color-scheme='prefer-dark'
accent-color='teal'
gtk-theme='Nexora'
icon-theme='Papirus-Dark'
cursor-theme='Bibata-Modern-Classic'
font-name='Inter 10'
document-font-name='Inter 10'
monospace-font-name='JetBrains Mono 10'
clock-format='24h'

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:close'

[org.gnome.nautilus.preferences]
default-folder-viewer='icon-view'

[org.gnome.TextEditor]
style-scheme='Adwaita-dark'
restore-session=false
EOF
    glib-compile-schemas /usr/share/glib-2.0/schemas
    install -vdm755 /etc/gtk-4.0
    cat > /etc/gtk-4.0/settings.ini << "EOF"
[Settings]
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Inter 10
EOF
    # apps por omissão: as novas
    cat > /etc/xdg/mimeapps.list << "EOF"
[Default Applications]
text/html=firefox.desktop
application/xhtml+xml=firefox.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
application/pdf=firefox.desktop
inode/directory=org.gnome.Nautilus.desktop
text/plain=org.gnome.TextEditor.desktop
text/markdown=org.gnome.TextEditor.desktop
application/x-shellscript=org.gnome.TextEditor.desktop
image/png=org.gnome.Loupe.desktop
image/jpeg=org.gnome.Loupe.desktop
image/webp=org.gnome.Loupe.desktop
image/gif=org.gnome.Loupe.desktop
image/svg+xml=org.gnome.Loupe.desktop
video/mp4=io.github.celluloid_player.Celluloid.desktop
video/x-matroska=io.github.celluloid_player.Celluloid.desktop
video/webm=io.github.celluloid_player.Celluloid.desktop
audio/mpeg=io.github.celluloid_player.Celluloid.desktop
audio/flac=io.github.celluloid_player.Celluloid.desktop
audio/ogg=io.github.celluloid_player.Celluloid.desktop
application/zip=org.gnome.FileRoller.desktop
application/x-tar=org.gnome.FileRoller.desktop
application/x-compressed-tar=org.gnome.FileRoller.desktop
application/x-7z-compressed=org.gnome.FileRoller.desktop
EOF
    # Xfce: terminal e ficheiros novos, e a doca com as apps novas
    sed -i -e '/^TerminalEmulator=/d' -e '/^FileManager=/d' /etc/xdg/xfce4/helpers.rc
    printf 'TerminalEmulator=ptyxis\nFileManager=nautilus\n' >> /etc/xdg/xfce4/helpers.rc
    A=/usr/share/applications
    sed -i "s|^pinned=.*|pinned=$A/org.gnome.Nautilus.desktop;$A/firefox.desktop;$A/org.gnome.Ptyxis.desktop;$A/org.gnome.TextEditor.desktop;$A/io.github.celluloid_player.Celluloid.desktop;$A/org.gnome.Software.desktop;$A/org.nexora.Settings.desktop;|" \
        /etc/xdg/xfce4/panel/docklike.rc
    # as apps antigas do Xfce continuam (o Xfce precisa delas) mas não aparecem no Nexora Flow
    for d in thunar thunar-bulk-rename org.xfce.mousepad org.xfce.ristretto xfce4-terminal xfce4-appfinder xfce4-about; do
        f=$A/$d.desktop
        [ -f $f ] || continue
        sed -i '/^NotShowIn=/d' $f
        sed -i '/^\[Desktop Entry\]/a NotShowIn=niri;' $f
    done
    # o fuzzel e o menu do Xfce passam a ver as apps Flatpak
    cat > /etc/profile.d/flatpak-xdg.sh << "EOF"
# apps instaladas com Flatpak (sistema e utilizador) nos menus
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share"
EOF
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    update-desktop-database -q /usr/share/applications || true
}

T0=$SECONDS
pkg  N.01-polkit-gnome  $B/polkit-gnome-0.105.tar.xz   p_polkitgnome
step N.02-flow          s_flow
step N.03-wallpapers    s_wallpapers
step N.04-login         s_login
step N.05-defaults      s_defaults
echo "🎉 Fase N (a cara nova) completa em $(( (SECONDS - T0) / 60 )) min"
