#!/bin/bash
# Fase E (dentro do chroot, como root): o Xfce da Nexora "de origem".
#   tema Nexora / Nexora-Dark (Greybird recolorido com o ciano #22b8cf),
#   Whisker Menu, fontes Inter + JetBrains Mono, cursores Adwaita,
#   painel, janelas, terminal e ecrã de login já configurados para utilizadores novos.
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
unzip_py() { python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$1" "$2"; }

# ---------- ferramentas ----------
p_sassc() {
    tar -xf $P/libsass-3.6.6.tar.gz
    pushd libsass-3.6.6
    autoreconf -fi
    ./configure --prefix=/usr --disable-static
    make
    make install
    popd
    autoreconf -fi
    ./configure --prefix=/usr
    make
    make install
}

# ---------- tema ----------
p_theme() {
    # Greybird com o azul trocado pelo ciano da Nexora (e menos escurecido no modo escuro)
    grep -rlI '#398ee7' . | xargs sed -i "s/#398ee7/$ACCENT/g"
    grep -rlI "darken($ACCENT,20%)" . | xargs -r sed -i "s/darken($ACCENT,20%)/darken($ACCENT,6%)/g"
    grep -rlI '#19B1A2' . | xargs -r sed -i 's/#19B1A2/#22B8CF/g'
    mbuild
    cd /usr/share/themes
    rm -rf Nexora Nexora-Dark
    mv -v Greybird Nexora
    mv -v Greybird-dark Nexora-Dark
    for t in Nexora Nexora-Dark; do
        sed -i -e "s/^Name=.*/Name=$t/" -e "s/^GtkTheme=.*/GtkTheme=$t/" \
               -e "s/^MetacityTheme=.*/MetacityTheme=$t/" -e "s/^Comment=.*/Comment=Tema da Nexora Linux/" \
               $t/index.theme
    done
    ls /usr/share/themes
}

p_whisker() {
    mkdir build && cd build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release \
          -D ENABLE_ACCOUNTS_SERVICE=OFF -D ENABLE_GTK_LAYER_SHELL=OFF -G Ninja ..
    ninja
    ninja install
}

# ---------- fontes e cursores ----------
s_fonts() {
    local d; d=$(mktemp -d /sources/fonts-XXXX)
    unzip_py $P/Inter-4.1.zip $d/inter
    unzip_py $P/JetBrainsMono-2.304.zip $d/jbm
    install -vdm755 /usr/share/fonts/inter /usr/share/fonts/jetbrains-mono
    for w in Regular Italic Light Medium SemiBold Bold BoldItalic; do
        install -vm644 $d/inter/extras/ttf/Inter-$w.ttf /usr/share/fonts/inter/
    done
    for w in Regular Italic Medium Bold BoldItalic; do
        install -vm644 $d/jbm/fonts/ttf/JetBrainsMono-$w.ttf /usr/share/fonts/jetbrains-mono/
    done
    rm -rf $d
    # Inter para a interface, DejaVu como reserva
    cat > /etc/fonts/local.conf << "EOF"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias><family>sans-serif</family><prefer><family>Inter</family><family>DejaVu Sans</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>JetBrains Mono</family><family>DejaVu Sans Mono</family></prefer></alias>
</fontconfig>
EOF
    fc-cache -f
    fc-list | grep -c -E 'Inter|JetBrains'
}

p_cursors() {
    install -vdm755 /usr/share/icons/Adwaita
    cp -a Adwaita/cursors /usr/share/icons/Adwaita/
    [ -f /usr/share/icons/Adwaita/index.theme ] || printf '[Icon Theme]\nName=Adwaita\nComment=Cursores Adwaita\n' \
        > /usr/share/icons/Adwaita/index.theme
    printf '[Icon Theme]\nInherits=Adwaita\n' > /usr/share/icons/default/index.theme
}

# ---------- configuração por omissão ----------
s_defaults() {
    install -vDm644 $P/nexora-logo.svg /usr/share/icons/hicolor/scalable/apps/nexora.svg
    install -vDm644 $P/nexora-logo.svg /usr/share/pixmaps/nexora.svg
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    grep -q '^LOGO=' /etc/os-release || echo 'LOGO=nexora' >> /etc/os-release

    install -dm755 $X
    cat > $X/xsettings.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Nexora-Dark"/>
    <property name="IconThemeName" type="string" value="elementary-xfce-dark"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Inter 10"/>
    <property name="MonospaceFontName" type="string" value="JetBrains Mono 10"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="ButtonImages" type="bool" value="true"/>
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
    <property name="theme" type="string" value="Nexora-Dark"/>
    <property name="title_font" type="string" value="Inter Semi-Bold 10"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="placement_ratio" type="int" value="100"/>
    <property name="placement_mode" type="string" value="center"/>
    <property name="workspace_count" type="int" value="2"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="tile_on_move" type="bool" value="true"/>
  </property>
</channel>
EOF
    cat > $X/xfce4-desktop.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="icon-size" type="uint" value="48"/>
    <property name="file-icons" type="empty">
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-removable" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
    # painel único em baixo: menu Nexora | janelas | ... | bandeja, notificações, relógio, sair
    local panel
    panel=$(cat << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="double" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="42"/>
      <property name="icon-size" type="uint" value="24"/>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.043"/>
        <value type="double" value="0.086"/>
        <value type="double" value="0.133"/>
        <value type="double" value="0.94"/>
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
        <value type="int" value="10"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu">
      <property name="button-icon" type="string" value="nexora"/>
      <property name="show-button-title" type="bool" value="false"/>
      <property name="favorites" type="array">
        <value type="string" value="xfce4-terminal-emulator.desktop"/>
        <value type="string" value="xfce4-file-manager.desktop"/>
        <value type="string" value="org.xfce.mousepad.desktop"/>
        <value type="string" value="org.xfce.ristretto.desktop"/>
        <value type="string" value="xfce-settings-manager.desktop"/>
      </property>
    </property>
    <property name="plugin-2" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist">
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="notification-plugin"/>
    <property name="plugin-7" type="string" value="power-manager-plugin"/>
    <property name="plugin-8" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-layout" type="uint" value="1"/>
      <property name="digital-time-format" type="string" value="%H:%M"/>
      <property name="digital-date-format" type="string" value="%d %b"/>
    </property>
    <property name="plugin-9" type="string" value="actions"/>
    <property name="plugin-10" type="string" value="showdesktop"/>
  </property>
</channel>
EOF
)
    echo "$panel" > $X/xfce4-panel.xml
    echo "$panel" > /etc/xdg/xfce4/panel/default.xml

    cat > $X/xfce4-terminal.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-terminal" version="1.0">
  <property name="font-use-system" type="bool" value="false"/>
  <property name="font-name" type="string" value="JetBrains Mono 11"/>
  <property name="color-use-theme" type="bool" value="false"/>
  <property name="color-foreground" type="string" value="#d6e4ea"/>
  <property name="color-background" type="string" value="#0b1622"/>
  <property name="color-cursor" type="string" value="$ACCENT"/>
  <property name="color-cursor-use-default" type="bool" value="false"/>
  <property name="color-palette" type="string" value="#1a2733;#e5534b;#3fb950;#d29922;#3b8eea;#bc8cff;$ACCENT;#c9d1d9;#4b5f70;#ff7b72;#56d364;#e3b341;#79c0ff;#d2a8ff;#56d4e6;#f0f6fc"/>
  <property name="misc-default-geometry" type="string" value="100x28"/>
  <property name="misc-menubar-default" type="bool" value="false"/>
  <property name="scrolling-bar" type="string" value="TERMINAL_SCROLLBAR_NONE"/>
</channel>
EOF
    # ecrã de login
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
background = /usr/share/backgrounds/nexora/nexora-wallpaper.png
user-background = false
theme-name = Nexora-Dark
icon-theme-name = elementary-xfce-dark
cursor-theme-name = Adwaita
cursor-theme-size = 24
font-name = Inter 11
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %H:%M  ·  %d %b
position = 82%,center 50%,center
EOF
}

T0=$SECONDS
pkg  E.01-sassc        $B/sassc-3.6.2.tar.gz                   p_sassc
pkg  E.02-theme        $B/Greybird-3.23.4.tar.gz               p_theme
pkg  E.03-whiskermenu  $B/xfce4-whiskermenu-plugin-2.10.1.tar.xz p_whisker
step E.04-fonts        s_fonts
pkg  E.05-cursors      $B/adwaita-icon-theme-50.0.tar.xz       p_cursors
step E.06-defaults     s_defaults
echo "🎉 Fase E (Xfce da Nexora) completa em $(( SECONDS - T0 ))s"
