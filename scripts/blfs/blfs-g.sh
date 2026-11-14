#!/bin/bash
# Fase G (dentro do chroot, como root): hardware real e visual moderno.
#   linux-firmware (sem blobs de servidor/ARM), NetworkManager + Wi-Fi + applet,
#   tema Colloid recolorido (azul-noite + ciano Nexora), ícones Papirus, cursor Bibata,
#   barra em cima + doca em baixo (docklike), wallpaper aurora.
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs
X=/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
ACCENT="#22b8cf"

mbuild() {
    # pasta própria (há tarballs que já trazem uma pasta build/) e sem && (o set -e não apanha)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
abuild() { ./configure --prefix=/usr "$@"; make; make install; }

# ---------------------------------------------------------------- firmware
p_firmware() {
    rm -rf /usr/lib/firmware.new
    ./copy-firmware.sh --zstd /usr/lib/firmware.new
    # blobs de servidores, redes de datacenter e SoCs ARM: não servem num PC
    for d in netronome mellanox liquidio qed cxgb4 dpaa2 cavium qcom mrvl/prestera \
             bnx2x qlogic ql2* mediatek/mt8* imx meson amlogic; do
        rm -rf /usr/lib/firmware.new/$d
    done
    rm -rf /usr/lib/firmware.old
    [ -d /usr/lib/firmware ] && mv /usr/lib/firmware /usr/lib/firmware.old
    mv /usr/lib/firmware.new /usr/lib/firmware
    [ -d /usr/lib/firmware.old ] && cp -an /usr/lib/firmware.old/. /usr/lib/firmware/ && rm -rf /usr/lib/firmware.old
    du -sh /usr/lib/firmware
}

# ---------------------------------------------------------------- rede
p_libndp() { abuild --sysconfdir=/etc --localstatedir=/var --disable-static; }
p_libnl()  { abuild --sysconfdir=/etc --disable-static; }
p_wpa() {
    cat > wpa_supplicant/.config << "EOF"
CONFIG_BACKEND=file
CONFIG_CTRL_IFACE=y
CONFIG_DEBUG_FILE=y
CONFIG_DEBUG_SYSLOG=y
CONFIG_DEBUG_SYSLOG_FACILITY=LOG_DAEMON
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_DRIVER_WIRED=y
CONFIG_EAP_GTC=y
CONFIG_EAP_LEAP=y
CONFIG_EAP_MD5=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_EAP_OTP=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TLS=y
CONFIG_EAP_TTLS=y
CONFIG_IEEE8021X_EAPOL=y
CONFIG_IPV6=y
CONFIG_LIBNL32=y
CONFIG_PEERKEY=y
CONFIG_PKCS12=y
CONFIG_READLINE=y
CONFIG_SMARTCARD=y
CONFIG_WPS=y
CONFIG_SAE=y
CONFIG_OWE=y
CONFIG_CTRL_IFACE_DBUS=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_CTRL_IFACE_DBUS_INTRO=y
CFLAGS += -I/usr/include/libnl3
EOF
    cd wpa_supplicant
    make BINDIR=/usr/sbin LIBDIR=/usr/lib
    install -v -m755 wpa_{cli,passphrase,supplicant} /usr/sbin/
    install -v -m644 systemd/*.service /usr/lib/systemd/system/
    install -v -m644 dbus/fi.w1.wpa_supplicant1.service /usr/share/dbus-1/system-services/
    install -v -d -m755 /etc/dbus-1/system.d
    install -v -m644 dbus/dbus-wpa_supplicant.conf /etc/dbus-1/system.d/wpa_supplicant.conf
}
p_nm() {
    grep -rl '^#!.*python$' | xargs -r sed -i '1s/python/&3/'
    mbuild -D libaudit=no -D nmtui=false -D ovs=false -D ppp=false -D nbft=false -D selinux=false \
           -D qt=false -D session_tracking=systemd -D nm_cloud_setup=false -D clat=false \
           -D modem_manager=false -D vapi=false -D docs=false -D tests=no -D introspection=true \
           -D crypto=gnutls -D man=false
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/NetworkManager.conf << "EOF"
[main]
plugins=keyfile
EOF
    printf '[main]\nauth-polkit=true\n' > /etc/NetworkManager/conf.d/polkit.conf
    # quem está nos grupos wheel/netdev gere a rede sem pedir senha
    groupadd -fg 86 netdev
    mkdir -p /usr/share/polkit-1/rules.d
    cat > /usr/share/polkit-1/rules.d/org.freedesktop.NetworkManager.rules << "EOF"
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        (subject.isInGroup("netdev") || subject.isInGroup("wheel")) && subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF
    # o NetworkManager passa a gerir a rede (o networkd sai de cena; o resolved fica para DNS)
    systemctl disable systemd-networkd systemd-networkd.socket systemd-networkd-wait-online 2>/dev/null || true
    rm -f /etc/systemd/network/10-eth-dhcp.network
    systemctl enable NetworkManager
    systemctl disable NetworkManager-wait-online 2>/dev/null || true
}
p_libsecret() { mbuild -D gtk_doc=false -D vapi=false -D manpage=false; }
p_gcr() {
    sed '/ssh.add/d; /ssh.agent/d' -i meson.build
    sed -i 's:"/desktop:"/org:' schema/*.xml
    mbuild -D gtk_doc=false -D ssh_agent=false -D gpg_path=/usr/bin/gpg2 -D introspection=false
}
p_libnma() { mbuild -D gtk_doc=false -D libnma_gtk4=false -D mobile_broadband_provider_info=false -D vapi=false -D introspection=false; }
p_nmapplet() { mbuild -D appindicator=no -D selinux=false -D team=false -D wwan=false; }

# ---------------------------------------------------------------- visual
p_colloid() {
    # acento teal -> ciano Nexora; cinzentos escuros -> azul-noite
    sed -i -e "s/^\$teal-light: .*/\$teal-light: $ACCENT;/" -e 's/^\$teal-dark: .*/$teal-dark: #1497ab;/' \
        -e 's/^\$grey-550: .*/$grey-550: #4a5a6a;/' -e 's/^\$grey-600: .*/$grey-600: #3a4856;/' \
        -e 's/^\$grey-650: .*/$grey-650: #263442;/' -e 's/^\$grey-700: .*/$grey-700: #1a2530;/' \
        -e 's/^\$grey-750: .*/$grey-750: #151f29;/' -e 's/^\$grey-800: .*/$grey-800: #111a23;/' \
        -e 's/^\$grey-850: .*/$grey-850: #0d151d;/' -e 's/^\$grey-900: .*/$grey-900: #0a1118;/' \
        -e 's/^\$grey-950: .*/$grey-950: #050a0f;/' \
        src/sass/_color-palette-default.scss
    grep -E '^\$(teal|grey-7)' src/sass/_color-palette-default.scss
    rm -rf /usr/share/themes/Nexora-Colloid*
    ./install.sh -d /usr/share/themes -n Nexora-Colloid -t teal -c dark --tweaks rimless
    cd /usr/share/themes
    rm -rf Nexora Nexora-hdpi Nexora-xhdpi
    for s in "" -hdpi -xhdpi; do
        [ -d Nexora-Colloid-Teal-Dark$s ] && mv Nexora-Colloid-Teal-Dark$s Nexora$s
    done
    sed -i -e 's/^Name=.*/Name=Nexora/' -e 's/^GtkTheme=.*/GtkTheme=Nexora/' -e 's/^MetacityTheme=.*/MetacityTheme=Nexora/' \
        Nexora/index.theme
    # doca em cápsula: o painel fica transparente (cor com alfa 0) e a caixa do docklike é que
    # tem fundo, borda e cantos redondos. Vai para gtk.css e gtk-dark.css (o painel usa o escuro).
    for f in Nexora/gtk-3.0/gtk.css Nexora/gtk-3.0/gtk-dark.css; do
        cat >> $f << "EOF"

/* --- Nexora: painel e doca --- */
#docklike-plugin { background-color: rgba(16, 26, 38, 0.80); border-radius: 18px; padding: 4px 8px;
                   margin-bottom: 6px; border: 1px solid rgba(255, 255, 255, 0.08); }
#docklike-plugin button { border-radius: 12px; }
#whiskermenu-button { padding: 0 10px; }
EOF
    done
    ls -d /usr/share/themes/Nexora*
}
p_papirus() {
    rm -rf /usr/share/icons/Papirus /usr/share/icons/Papirus-Dark /usr/share/icons/Papirus-Light /usr/share/icons/ePapirus*
    cp -a Papirus Papirus-Dark /usr/share/icons/
    # pastas ciano (o papirus-folders troca os symlinks das pastas)
    tar -xf $P/papirus-folders-1.14.0.tar.gz
    bash papirus-folders-1.14.0/papirus-folders -C cyan --theme Papirus-Dark -o || true
    bash papirus-folders-1.14.0/papirus-folders -C cyan --theme Papirus -o || true
    gtk-update-icon-cache -qtf /usr/share/icons/Papirus || true
    gtk-update-icon-cache -qtf /usr/share/icons/Papirus-Dark || true
}
s_cursor() {
    rm -rf /usr/share/icons/Bibata-Modern-Classic
    tar -xf $P/Bibata-Modern-Classic-2.0.7.tar.xz -C /usr/share/icons/
    printf '[Icon Theme]\nInherits=Bibata-Modern-Classic\n' > /usr/share/icons/default/index.theme
    ls /usr/share/icons/Bibata-Modern-Classic/cursors | wc -l
}
p_docklike() { mbuild; }
s_wallpaper() {
    install -vDm644 $P/nexora-aurora.png /usr/share/backgrounds/nexora/nexora-aurora.png
    # o fundo por omissão do xfdesktop aponta para nexora-wallpaper.png: passa a ser a aurora
    ln -sfv nexora-aurora.png /usr/share/backgrounds/nexora/nexora-wallpaper.png 2>/dev/null || true
    install -vDm644 $P/nexora-wallpaper.png /usr/share/backgrounds/nexora/nexora-logo.png
}

s_defaults() {
    install -dm755 $X
    cat > $X/xsettings.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Nexora"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Inter 10"/>
    <property name="MonospaceFontName" type="string" value="JetBrains Mono 10"/>
    <property name="CursorThemeName" type="string" value="Bibata-Modern-Classic"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="DialogsUseHeader" type="bool" value="true"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
    <property name="ButtonImages" type="bool" value="false"/>
    <property name="MenuImages" type="bool" value="true"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
EOF
    cat > $X/xfwm4.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Nexora"/>
    <property name="title_font" type="string" value="Inter Semi-Bold 10"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="show_frame_shadow" type="bool" value="true"/>
    <property name="show_popup_shadow" type="bool" value="true"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="shadow_opacity" type="int" value="55"/>
    <property name="placement_ratio" type="int" value="100"/>
    <property name="placement_mode" type="string" value="center"/>
    <property name="workspace_count" type="int" value="2"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="tile_on_move" type="bool" value="true"/>
    <property name="move_opacity" type="int" value="94"/>
  </property>
</channel>
EOF
    cat > $X/xfce4-desktop.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="icon-size" type="uint" value="48"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="false"/>
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-trash" type="bool" value="false"/>
      <property name="show-removable" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
    cat > $X/xfce4-notifyd.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-notifyd" version="1.0">
  <property name="theme" type="string" value="Default"/>
  <property name="notify-location" type="string" value="top-right"/>
  <property name="initial-opacity" type="double" value="0.96"/>
</channel>
EOF
    # barra fina em cima + doca centrada em baixo
    local panel
    panel=$(cat << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="double" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="30"/>
      <property name="icon-size" type="uint" value="16"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.027"/>
        <value type="double" value="0.055"/>
        <value type="double" value="0.09"/>
        <value type="double" value="0.88"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
      </property>
    </property>
    <property name="panel-2" type="empty">
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="double" value="1"/>
      <property name="length-adjust" type="bool" value="true"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="66"/>
      <property name="icon-size" type="uint" value="42"/>
      <property name="autohide-behavior" type="uint" value="1"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0"/>
        <value type="double" value="0"/>
        <value type="double" value="0"/>
        <value type="double" value="0"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="20"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-icon" type="string" value="nexora"/>
      <property name="show-button-title" type="bool" value="true"/>
      <property name="button-title" type="string" value="Nexora"/>
      <property name="position-search-alternate" type="bool" value="true"/>
      <property name="position-commands-alternate" type="bool" value="true"/>
      <property name="menu-width" type="int" value="560"/>
      <property name="menu-height" type="int" value="560"/>
      <property name="item-icon-size" type="int" value="3"/>
      <property name="category-icon-size" type="int" value="1"/>
      <property name="favorites" type="array">
        <value type="string" value="xfce4-terminal-emulator.desktop"/>
        <value type="string" value="xfce4-file-manager.desktop"/>
        <value type="string" value="org.xfce.mousepad.desktop"/>
        <value type="string" value="org.xfce.ristretto.desktop"/>
        <value type="string" value="xfce-settings-manager.desktop"/>
      </property>
    </property>
    <property name="plugin-2" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-format" type="string" value="%a %d %b   %H:%M"/>
      <property name="digital-time-font" type="string" value="Inter Semi-Bold 10"/>
    </property>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
      <property name="icon-size" type="int" value="16"/>
    </property>
    <property name="plugin-6" type="string" value="notification-plugin"/>
    <property name="plugin-7" type="string" value="power-manager-plugin"/>
    <property name="plugin-8" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-9" type="string" value="actions">
      <property name="appearance" type="uint" value="1"/>
      <property name="button-title" type="uint" value="1"/>
    </property>
    <property name="plugin-20" type="string" value="docklike"/>
  </property>
</channel>
EOF
)
    echo "$panel" > $X/xfce4-panel.xml
    echo "$panel" > /etc/xdg/xfce4/panel/default.xml
    cat > /etc/xdg/xfce4/panel/docklike.rc << "EOF"
[user]
pinned=/usr/share/applications/xfce4-terminal.desktop;/usr/share/applications/thunar.desktop;/usr/share/applications/org.xfce.mousepad.desktop;/usr/share/applications/org.xfce.ristretto.desktop;/usr/share/applications/xfce-settings-manager.desktop;
indicatorStyle=1
indicatorOrientation=0
indicatorColorFromTheme=true
showPreviews=true
forceIconSize=true
iconSize=42
EOF
    # terminal com fundo ligeiramente translúcido
    sed -i 's|</channel>|  <property name="background-mode" type="string" value="TERMINAL_BACKGROUND_TRANSPARENT"/>\n  <property name="background-darkness" type="double" value="0.90"/>\n</channel>|' \
        $X/xfce4-terminal.xml
    grep -q background-mode $X/xfce4-terminal.xml

    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
background = /usr/share/backgrounds/nexora/nexora-logo.png
user-background = false
theme-name = Nexora
icon-theme-name = Papirus-Dark
cursor-theme-name = Bibata-Modern-Classic
cursor-theme-size = 24
font-name = Inter 11
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %a %d %b   %H:%M
position = 82%,center 50%,center
EOF
    # o applet da rede arranca com a sessão (já traz .desktop em /etc/xdg/autostart)
    ls /etc/xdg/autostart/nm-applet.desktop
}

T0=$SECONDS
pkg  G.01-firmware     $B/linux-firmware-20261019.tar.xz        p_firmware
pkg  G.02-libndp       $B/libndp-1.9.tar.gz                     p_libndp
pkg  G.03-libnl        $B/libnl-3.12.0.tar.gz                   p_libnl
pkg  G.04-wpa          $B/wpa_supplicant-2.12.tar.gz            p_wpa
pkg  G.05-networkmanager $B/NetworkManager-1.58.1.tar.xz        p_nm
pkg  G.06-libsecret    $B/libsecret-0.21.7.tar.xz               p_libsecret
pkg  G.07-gcr          $B/gcr-3.41.2.tar.xz                     p_gcr
pkg  G.08-libnma       $B/libnma-1.10.6.tar.xz                  p_libnma
pkg  G.09-nm-applet    $B/network-manager-applet-1.34.0.tar.xz  p_nmapplet
pkg  G.10-colloid      $B/Colloid-gtk-theme-2026-08-08.tar.gz   p_colloid
pkg  G.11-papirus      $B/papirus-icon-theme-20260801.tar.gz    p_papirus
step G.12-cursor       s_cursor
pkg  G.13-docklike     $B/xfce4-docklike-plugin-0.5.1.tar.xz    p_docklike
step G.14-wallpaper    s_wallpaper
step G.15-defaults     s_defaults
echo "🎉 Fase G (hardware e visual) completa em $(( (SECONDS - T0) / 60 )) min"
