#!/bin/bash
# Fase T (dentro do chroot, como root): o que um utilizador normal sente logo a falta.
#   Impressoras: CUPS + filtros da OpenPrinting + cups-browsed (as impressoras de rede aparecem
#   sozinhas) + Avahi/nss-mdns; sem drivers para quase todas (IPP Everywhere / AirPrint).
#   Firewall: nftables com regras simples (nada entra sem ser pedido; mDNS e Steam na rede local).
#   Bloqueio: swayidle + swaylock pelo nexora-idle, que não bloqueia a meio de jogos nem vídeos.
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
F=$N/flow
I=$N/installer
SY=$F/system

ac() {
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static "$@"
    make
    make install
}

# ---------------------------------------------------------------- base: USB e descoberta na rede
p_libusb() { ac; }
p_libdaemon() { ac --docdir=/usr/share/doc/libdaemon-0.14; }
p_avahi() {
    groupadd -fg 84 avahi
    getent passwd avahi >/dev/null || useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 \
        -g avahi -s /bin/false avahi
    groupadd -fg 86 netdev
    patch -Np1 -i $SRC/$B/avahi-0.9-rc5-ipv6_race_condition_fix-1.patch
    autoreconf -fiv
    ac --disable-libevent --disable-mono --disable-monodoc --disable-python \
       --disable-qt3 --disable-qt4 --disable-qt5 --disable-gtk --disable-gtk3 \
       --disable-manpages --disable-doxygen-doc --with-distro=none \
       --with-systemdsystemunitdir=/usr/lib/systemd/system \
       --with-dbus-system-address='unix:path=/run/dbus/system_bus_socket'
    systemctl enable avahi-daemon.service
}
p_nssmdns() {
    ac
    # "impressora.local" resolve-se pelo Avahi; o mDNS do systemd-resolved sai do caminho
    grep -q mdns_minimal /etc/nsswitch.conf ||
        sed -i 's/^hosts:\s*mymachines /hosts:          mymachines mdns_minimal [NOTFOUND=return] /' /etc/nsswitch.conf
    grep -q mdns_minimal /etc/nsswitch.conf
    install -vdm755 /etc/systemd/resolved.conf.d
    printf "[Resolve]\nMulticastDNS=no\n" > /etc/systemd/resolved.conf.d/50-nexora-avahi.conf
}

# ---------------------------------------------------------------- impressão
p_qpdf() {
    mkdir nx-build && cd nx-build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D BUILD_STATIC_LIBS=OFF \
          -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/qpdf-12.4.2 -G Ninja ..
    ninja
    ninja install
}
p_gs() {
    # usa as bibliotecas do sistema em vez das cópias velhas que vêm no tarball
    rm -rf freetype lcms2mt jpeg libpng openjpeg zlib
    ./configure --prefix=/usr --disable-compile-inits --with-system-libtiff \
        CFLAGS="-O2 -fPIC"
    make
    make install
    gs --version
    gs -h | grep appleraster >/dev/null
}
p_cups() {
    getent passwd lp >/dev/null || useradd -c "Print Service User" -d /var/spool/cups -g lp -s /bin/false -u 9 lp
    groupadd -fg 19 lpadmin
    sed -i 's#@CUPS_HTMLVIEW@#xdg-open#' desktop/cups.desktop.in
    ./configure --libdir=/usr/lib --with-rcdir=/tmp/cupsinit --with-rundir=/run/cups \
                --with-system-groups=lpadmin --with-docdir=/usr/share/cups/doc-2.4.20
    make
    make install
    rm -rf /tmp/cupsinit
    # quem gere impressoras: lpadmin (Definições), wheel (quem usa sudo) e o root
    sed -i 's/^SystemGroup lpadmin$/SystemGroup lpadmin wheel root/' /etc/cups/cups-files.conf
    grep -q "^SystemGroup lpadmin wheel root" /etc/cups/cups-files.conf
    cat > /etc/pam.d/cups << "EOF"
# Begin /etc/pam.d/cups
auth    include system-auth
account include system-account
session include system-session
# End /etc/pam.d/cups
EOF
    # os utilizadores da Nexora (grupo lpadmin) gerem impressoras nas Definições
    for u in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do usermod -aG lpadmin "$u"; done
    systemctl enable cups.socket cups.path cups.service
}
p_pdfio() {
    ./configure --prefix=/usr --enable-shared
    make
    make install
}
p_libcupsfilters() {
    # master da OpenPrinting (commit fab9d52296, 2026-11-15): a 2.2.1 falha na contagem de páginas
    # e no pdftopdf das páginas de teste/banners; o master já traz essas correções
    autoreconf -fi   # o autogen.sh procura o libtoolize com o "which", que a Nexora não tem
    ac --without-jpegxl --disable-mutool --docdir=/usr/share/doc/libcupsfilters-2.2.1-git
}
p_libppd() { ac --disable-mutool --with-cups-rundir=/run/cups --enable-ppdc-utils --docdir=/usr/share/doc/libppd-2.1.1; }
p_cupsfilters() {
    # o foomatic-rip ainda usa protótipos "()" do C antigo, que o GCC 16 (C23) recusa
    CFLAGS="${CFLAGS:--O2} -std=gnu17" ac --disable-mutool --docdir=/usr/share/doc/cups-filters-2.0.1
}
p_cupsbrowsed() {
    ac --with-cups-rundir=/run/cups --without-rcdir --docdir=/usr/share/doc/cups-browsed-2.1.1
    install -vm644 $SY/cups-browsed.service /usr/lib/systemd/system/cups-browsed.service
    systemctl enable cups-browsed.service
}

# ---------------------------------------------------------------- firewall
p_libmnl() { ac; }
p_libnftnl() { ac; }
p_nftables() {
    ac --disable-man-doc --without-json --with-cli=readline --disable-python
    install -vm644 $SY/nftables.conf /etc/nftables.conf
    install -vm644 $SY/nftables.service /usr/lib/systemd/system/nftables.service
    nft -c -f /etc/nftables.conf
    systemctl enable nftables.service
}

# ---------------------------------------------------------------- bloqueio do ecrã
p_swayidle() {
    mkdir nx-build && cd nx-build
    meson setup .. --prefix=/usr --buildtype=release -D man-pages=disabled -D logind=enabled \
          -D logind-provider=systemd
    ninja
    ninja install
    install -vm755 $SY/nexora-idle /usr/bin/nexora-idle
}

s_flow() {
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    install -vm755 $F/bin/nexora-flow-start /usr/bin/nexora-flow-start
    install -vm755 $F/bin/nexora-flow-niri /usr/bin/nexora-flow-niri
    install -vm755 $I/nexora-install-engine /usr/sbin/nexora-install-engine
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    install -vm644 $F/eww/eww.yuck /usr/share/nexora-flow/eww/eww.yuck
    install -vm755 $SY/nexora-idle /usr/bin/nexora-idle
    niri validate -c /etc/niri/config.kdl
    python3 -c "import ast; ast.parse(open('/usr/bin/nexora-settings').read())"
    python3 -c "import ast; ast.parse(open('/usr/bin/nexora-flow-niri').read())"
}

T0=$SECONDS
pkg  T.01-libusb        $B/libusb-1.0.30.tar.bz2               p_libusb
pkg  T.02-libdaemon     $B/libdaemon-0.14.tar.gz               p_libdaemon
pkg  T.03-avahi         $B/avahi-0.9-rc5.tar.gz                p_avahi
pkg  T.04-nss-mdns      $B/nss-mdns-0.15.1.tar.gz              p_nssmdns
pkg  T.05-qpdf          $B/qpdf-12.4.2.tar.gz                  p_qpdf
pkg  T.07-cups          $B/cups-2.4.20-source.tar.gz           p_cups
# o Ghostscript vem depois do CUPS: só assim ganha os dispositivos de impressora (appleraster, pwgraster)
pkg  T.07a-ghostscript  $B/ghostscript-10.08.0.tar.gz          p_gs
pkg  T.07b-pdfio        $B/pdfio-1.6.6.tar.gz                  p_pdfio
pkg  T.08-libcupsfilters $B/libcupsfilters-fab9d52296.tar.gz    p_libcupsfilters
pkg  T.09-libppd        $B/libppd-2.1.1.tar.xz                 p_libppd
pkg  T.10-cups-filters  $B/cups-filters-2.0.1.tar.xz           p_cupsfilters
pkg  T.11-cups-browsed  $B/cups-browsed-2.1.1.tar.xz           p_cupsbrowsed
pkg  T.12-libmnl        $B/libmnl-1.0.5.tar.bz2                p_libmnl
pkg  T.13-libnftnl      $B/libnftnl-1.3.2.tar.xz               p_libnftnl
pkg  T.14-nftables      $B/nftables-1.1.7.tar.xz               p_nftables
pkg  T.15-swayidle      $B/swayidle-1.9.1.tar.gz               p_swayidle
step T.16-flow          s_flow
echo "🖨  Fase T (impressoras, firewall, bloqueio) completa em $(( (SECONDS - T0) / 60 )) min"
