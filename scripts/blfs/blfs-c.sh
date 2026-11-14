#!/bin/bash
# BLFS 13.1 fase C (dentro do chroot, como root): Xfce 4.20 + apps + LightDM + utilizador lori.
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs
export PATH=/opt/rustc/bin:$PATH

mbuild() {
    # pasta própria (há tarballs que já trazem uma pasta build/) e sem && (o set -e não apanha)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
abuild() { ./configure --prefix=/usr "$@"; make; make install; }
pywheel() {
    pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
    pip3 install --no-index --find-links dist --no-user "$1"
}

# ---------- ferramentas de build ----------
p_perlmod()   { perl Makefile.PL; make; make install; }
p_xmlparser() { perl Makefile.PL; make; make install; }
p_intltool() {
    sed -i 's:\\\${:\\\$\\{:' intltool-update.in
    abuild
}
p_libxslt()   { abuild --disable-static --without-python --docdir=/usr/share/doc/libxslt-1.1.45; }
p_lxml()      { pywheel lxml; }
p_docbook() {
    install -v -d -m755 /usr/share/xml/docbook/xml-dtd-4.5
    install -v -d -m755 /etc/xml
    cp -v -af --no-preserve=ownership catalog.xml docbook.cat *.dtd ent/ *.mod \
        /usr/share/xml/docbook/xml-dtd-4.5
    xmlcatalog --noout --add "rewriteSystem" "http://www.oasis-open.org/docbook/xml/4.5" \
        "file:///usr/share/xml/docbook/xml-dtd-4.5" /usr/share/xml/docbook/xml-dtd-4.5/catalog.xml
    xmlcatalog --noout --add "rewriteURI" "http://www.oasis-open.org/docbook/xml/4.5" \
        "file:///usr/share/xml/docbook/xml-dtd-4.5" /usr/share/xml/docbook/xml-dtd-4.5/catalog.xml
    [ -e /etc/xml/catalog ] || xmlcatalog --noout --create /etc/xml/catalog
    for t in delegatePublic:"-//OASIS//ENTITIES DocBook XML" delegatePublic:"-//OASIS//DTD DocBook XML" \
             delegateSystem:"http://www.oasis-open.org/docbook/" delegateURI:"http://www.oasis-open.org/docbook/"; do
        xmlcatalog --noout --add "${t%%:*}" "${t#*:}" \
            "file:///usr/share/xml/docbook/xml-dtd-4.5/catalog.xml" /etc/xml/catalog
    done
}
p_docbook_wrap() {   # o docbook-xml vem em .zip sem pasta de topo (e o LFS não tem unzip)
    local d; d=$(mktemp -d /sources/docbook-XXXX); cd "$d"
    python3 -m zipfile -e $P/docbook-xml-4.5.zip .
    p_docbook
    cd /sources; rm -rf "$d"
}
p_itstool() {
    patch -Np1 -i $P/itstool-2.0.7-lxml-1.patch
    PYTHON=/usr/bin/python3 ./autogen.sh --prefix=/usr
    make; make install
}
p_xfcedevtools() { abuild; }
p_hwdata()   { ./configure --prefix=/usr --disable-blacklist; make install; }
p_libdisplayinfo() { mbuild; }

# ---------- bibliotecas ----------
p_xfce4util() { abuild; }
p_xfconf()    { abuild; }
p_startupn()  { abuild --disable-static; }
p_xfce4ui()   { abuild --sysconfdir=/etc; }
p_exo()       { abuild --sysconfdir=/etc; }
p_garcon()    { abuild --sysconfdir=/etc; }
p_xfce4win()  { abuild --sysconfdir=/etc --enable-x11 --disable-wayland --disable-debug; }
p_libgudev()  { mbuild; }
p_libnotify() { mbuild -D gtk_doc=false -D man=false -D tests=false; }
p_libusb()    { abuild --disable-static; }
p_upower()    { mbuild -D gtk-doc=false -D man=false; }
p_libwnck()   { mbuild; }
p_libogg()    { abuild --disable-static --docdir=/usr/share/doc/libogg-1.3.6; }
p_libvorbis() { abuild --disable-static; }
p_canberra() {
    patch -Np1 -i $P/libcanberra-0.30-wayland-1.patch
    ./configure --prefix=/usr --disable-oss
    make
    make docdir=/usr/share/doc/libcanberra-0.30 install
}
p_xklavier()  { abuild --disable-static; }
p_dfu() {
    rm -fv /usr/bin/desktop-file-edit
    mbuild
    install -vdm755 /usr/share/applications
    update-desktop-database /usr/share/applications
}
p_duktape() {
    sed -i 's/-Os/-O2/' Makefile.sharedlibrary
    make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr
    make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr install
}
p_polkit() {
    getent group polkitd >/dev/null || groupadd -fg 27 polkitd
    getent passwd polkitd >/dev/null || useradd -c "PolicyKit Daemon Owner" -d /etc/polkit-1 -u 27 \
        -g polkitd -s /bin/false polkitd
    mbuild -D man=false -D session_tracking=logind -D tests=false
}
p_vte() {
    mbuild -D gtk4=false -D vapi=false -D gir=false -D _systemd=false \
           -D gnutls=false -D icu=false -D glade=false -D app=false
    rm -fv /etc/profile.d/vte.*
}
p_gtksourceview4() { mbuild -D vapi=false; }
p_libexif()   { abuild --disable-static --with-doc-dir=/usr/share/doc/libexif-0.6.26; }
p_gpgerror()  { abuild --sysconfdir=/etc; }
p_gcrypt()    { abuild; }

# ---------- Xfce ----------
p_xfpanel()   { abuild --sysconfdir=/etc; }
p_thunar()    { abuild --sysconfdir=/etc --docdir=/usr/share/doc/thunar-4.20.9; }
p_thunarvol() { abuild; }
p_tumbler()   { abuild --sysconfdir=/etc; }
p_appfinder() { abuild; }
p_xfpm()      { abuild --sysconfdir=/etc; }
p_xfsettings(){ abuild --sysconfdir=/etc; }
p_xfdesktop() { abuild --with-default-backdrop-filename=/usr/share/backgrounds/nexora/nexora-wallpaper.png; }
p_xfwm4()     { abuild; }
p_xfsession() {
    abuild --sysconfdir=/etc --disable-legacy-sm
    update-desktop-database
    update-mime-database /usr/share/mime
}
p_xfterminal() {
    sed -e '570i #ifdef HAVE_GTK_LAYER_SHELL' -e '574a #endif' -i terminal/terminal-window-dropdown.c
    mbuild -D doc=false
}
p_mousepad()  { mbuild; }
p_ristretto() { mbuild; }
p_notifyd()   { abuild --sysconfdir=/etc; }

# ---------- LightDM ----------
p_lightdm() {
    getent group lightdm  >/dev/null || groupadd -g 65 lightdm
    getent passwd lightdm >/dev/null || useradd -c "Lightdm Daemon" -d /var/lib/lightdm \
        -u 65 -g lightdm -s /bin/false lightdm
    # snapshot do git: sem gtk-doc nem yelp-tools -> tirar a documentação antes do autoreconf
    sed -i -e '/GTK_DOC_CHECK/d' -e '/YELP_HELP_INIT/d' \
           -e '/^doc\/Makefile$/d' -e '/^help\/Makefile$/d' configure.ac
    sed -i 's/^SUBDIRS += data po src doc help$/SUBDIRS += data po src/' Makefile.am
    autoreconf -fiv
    ./configure --prefix=/usr --libexecdir=/usr/lib/lightdm --localstatedir=/var \
                --sbindir=/usr/bin --sysconfdir=/etc --disable-static --disable-tests \
                --with-greeter-user=lightdm --with-greeter-session=lightdm-gtk-greeter
    make
    make install
    cp tests/src/lightdm-session /usr/bin
    sed -i '1 s/sh/bash --login/' /usr/bin/lightdm-session
    # Nexora: passar DISPLAY ao systemd do utilizador (senão o xfce4-notifyd ativado por D-Bus falha)
    sed -i '/^exec \$1/i dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP 2>/dev/null\n' /usr/bin/lightdm-session
    rm -rf /etc/init
    install -v -dm755 -o lightdm -g lightdm /var/lib/lightdm
    install -v -dm755 -o lightdm -g lightdm /var/lib/lightdm-data
    install -v -dm755 -o lightdm -g lightdm /var/cache/lightdm
    install -v -dm770 -o lightdm -g lightdm /var/log/lightdm
    tar -xf $P/lightdm-gtk-greeter-2.0.9.tar.gz
    cd lightdm-gtk-greeter-2.0.9
    ./configure --prefix=/usr --libexecdir=/usr/lib/lightdm --sbindir=/usr/bin \
                --sysconfdir=/etc --with-libxklavier --enable-kill-on-sigterm \
                --disable-libido --disable-libindicator --disable-static --disable-maintainer-mode
    make
    make install
    mv -v /usr/share/doc/lightdm-gtk-greeter{,-2.0.9}
}
p_lightdm_unit() {
    make install-lightdm
    systemctl enable lightdm
}

# ---------- toque Nexora ----------
p_icons() {
    ./configure --prefix=/usr
    make svgtopng test          # gera os PNG (sem optipng, que só os comprime)
    make install
    make icon-caches
}
s_nexora() {
    # utilizador do Lourenço (a senha mete-a ele: passwd lori)
    getent passwd lori >/dev/null || useradd -m -c "Lourenço" -G wheel,video,audio,input,users -s /bin/bash lori
    # tema por omissão para todos
    install -dm755 /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
    cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita"/>
    <property name="IconThemeName" type="string" value="elementary-xfce"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="DejaVu Sans 10"/>
    <property name="MonospaceFontName" type="string" value="DejaVu Sans Mono 10"/>
    <property name="CursorThemeName" type="string" value="whiteglass"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
</channel>
EOF
    # LightDM: ecrã de login com o nome da Nexora e teclado PT no X
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
theme-name = Adwaita
icon-theme-name = elementary-xfce
font-name = DejaVu Sans 11
indicators = ~host;~spacer;~clock;~spacer;~session;~power
clock-format = %H:%M  ·  %d %b
cursor-theme-name = whiteglass
EOF
    # cursor por omissão (o Adwaita não está instalado; whiteglass vem do xcursor-themes)
    install -dm755 /usr/share/icons/default
    printf '[Icon Theme]\nInherits=whiteglass\n' > /usr/share/icons/default/index.theme
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf << "EOF"
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "pt"
EndSection
EOF
    # arrancar no ambiente gráfico
    systemctl set-default graphical.target
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    fc-cache -f
}

T0=$SECONDS
pkg  C.00a-class-inspector $B/Class-Inspector-1.36.tar.gz     p_perlmod
pkg  C.00b-sharedir-install $B/File-ShareDir-Install-0.14.tar.gz p_perlmod
pkg  C.00c-file-sharedir $B/File-ShareDir-1.118.tar.gz        p_perlmod
pkg  C.01-xml-parser     $B/XML-Parser-2.59.tar.gz            p_xmlparser
pkg  C.02-intltool       $B/intltool-0.51.0.tar.gz            p_intltool
pkg  C.03-libxslt        $B/libxslt-1.1.45.tar.xz             p_libxslt
pkg  C.04-lxml           $B/lxml-6.1.1.tar.gz                 p_lxml
step C.05-docbook        p_docbook_wrap
pkg  C.06-itstool        $B/itstool-2.0.7.tar.gz              p_itstool
pkg  C.07-xfce4-dev-tools $B/xfce4-dev-tools-4.20.0.tar.bz2   p_xfcedevtools
pkg  C.08-hwdata         $B/hwdata-0.410.tar.gz               p_hwdata
pkg  C.09-libdisplay-info $B/libdisplay-info-0.4.0.tar.xz     p_libdisplayinfo
pkg  C.10-libxfce4util   $B/libxfce4util-4.20.1.tar.bz2       p_xfce4util
pkg  C.11-xfconf         $B/xfconf-4.20.0.tar.bz2             p_xfconf
pkg  C.12-startup-notif  $B/startup-notification-0.12.tar.gz  p_startupn
pkg  C.13-libxfce4ui     $B/libxfce4ui-4.20.2.tar.bz2         p_xfce4ui
pkg  C.14-exo            $B/exo-4.20.0.tar.bz2                p_exo
pkg  C.15-garcon         $B/garcon-4.20.0.tar.bz2             p_garcon
pkg  C.21-libwnck        $B/libwnck-43.3.tar.xz               p_libwnck
pkg  C.16-libxfce4windowing $B/libxfce4windowing-4.20.7.tar.bz2 p_xfce4win
pkg  C.27-duktape        $B/duktape-2.7.0.tar.xz              p_duktape
pkg  C.28-polkit         $B/polkit-127.tar.gz                 p_polkit
pkg  C.17-libgudev       $B/libgudev-238.tar.xz               p_libgudev
pkg  C.18-libnotify      $B/libnotify-0.8.8.tar.xz            p_libnotify
pkg  C.19-libusb         $B/libusb-1.0.30.tar.bz2             p_libusb
pkg  C.20-upower         $B/upower-v1.91.3.tar.bz2            p_upower
pkg  C.22-libogg         $B/libogg-1.3.6.tar.xz               p_libogg
pkg  C.23-libvorbis      $B/libvorbis-1.3.7.tar.xz            p_libvorbis
pkg  C.24-libcanberra    $B/libcanberra-0.30.tar.xz           p_canberra
pkg  C.25-libxklavier    $B/libxklavier-5.4.tar.bz2           p_xklavier
pkg  C.26-desktop-file-utils $B/desktop-file-utils-0.28.tar.xz p_dfu
pkg  C.29-vte            $B/vte-0.84.1.tar.gz                 p_vte
pkg  C.30-gtksourceview4 $B/gtksourceview-4.8.4.tar.xz        p_gtksourceview4
pkg  C.31-libexif        $B/libexif-0.6.26.tar.bz2            p_libexif
pkg  C.32-libgpg-error   $B/libgpg-error-1.61.tar.bz2         p_gpgerror
pkg  C.33-libgcrypt      $B/libgcrypt-1.12.2.tar.bz2          p_gcrypt
pkg  C.34-xfce4-panel    $B/xfce4-panel-4.20.8.tar.bz2        p_xfpanel
pkg  C.35-thunar         $B/thunar-4.20.9.tar.bz2             p_thunar
pkg  C.36-thunar-volman  $B/thunar-volman-4.20.0.tar.bz2      p_thunarvol
pkg  C.37-tumbler        $B/tumbler-4.20.2.tar.bz2            p_tumbler
pkg  C.38-xfce4-appfinder $B/xfce4-appfinder-4.20.0.tar.bz2   p_appfinder
pkg  C.39-xfce4-power-manager $B/xfce4-power-manager-4.20.1.tar.bz2 p_xfpm
pkg  C.40-xfce4-settings $B/xfce4-settings-4.20.5.tar.bz2     p_xfsettings
pkg  C.41-xfdesktop      $B/xfdesktop-4.20.2.tar.bz2          p_xfdesktop
pkg  C.42-xfwm4          $B/xfwm4-4.20.0.tar.bz2              p_xfwm4
pkg  C.43-xfce4-session  $B/xfce4-session-4.20.4.tar.bz2      p_xfsession
pkg  C.44-xfce4-terminal $B/xfce4-terminal-1.2.0.tar.xz       p_xfterminal
pkg  C.45-mousepad       $B/mousepad-0.7.0.tar.xz             p_mousepad
pkg  C.46-ristretto      $B/ristretto-0.14.0.tar.xz           p_ristretto
pkg  C.47-xfce4-notifyd  $B/xfce4-notifyd-0.9.7.tar.bz2       p_notifyd
pkg  C.48-lightdm        $B/lightdm-1.33.1.tar.gz             p_lightdm
pkg  C.49-lightdm-unit   $B/blfs-systemd-units-20251204.tar.xz p_lightdm_unit
pkg  C.50-elementary-icons $B/elementary-xfce-0.23.tar.gz     p_icons
step C.51-nexora         s_nexora
echo "🎉 BLFS fase C completa em $(( (SECONDS - T0) / 60 )) min"
