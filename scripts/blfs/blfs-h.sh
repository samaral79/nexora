#!/bin/bash
# Fase H (dentro do chroot, como root): Nexora Flow — ambiente Wayland próprio.
#   base Wayland (wayland, Mesa e GTK3 com Wayland, seatd, Xwayland),
#   niri (fita de janelas), eww (shell da Nexora), fuzzel, mako, swaybg, swaylock.
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs
F=$(dirname "$0")/flow
export XORG_PREFIX=/usr
export XORG_CONFIG="--prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static"
export PATH=/opt/rustc/bin:$PATH
export CARGO_HOME=/sources/cargo-home
export CARGO_BUILD_JOBS=8          # Rust pesado: não rebentar a RAM do shrek

mbuild() {
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
abuild() { ./configure "$@"; make; make install; }

# ---------------------------------------------------------------- base Wayland
p_wayland()   { mbuild -D documentation=false -D tests=false; }
p_wprotocols(){ mbuild -D tests=false; }
p_mesa_wl() {
    # agora com Wayland (EGL/GBM para o niri); o resto como na fase B
    mbuild -D platforms=x11,wayland -D gallium-drivers=llvmpipe,softpipe,virgl \
           -D vulkan-drivers="" -D valgrind=disabled -D libunwind=disabled
}
p_gtk3_wl() {
    mbuild -D man=false -D broadway_backend=false -D wayland_backend=true -D x11_backend=true
    gtk-query-immodules-3.0 --update-cache
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
p_layershell() { mbuild -D introspection=false -D vapi=false -D docs=false -D tests=false -D examples=false; }
p_seatd()      { mbuild -D server=disabled -D libseat-seatd=disabled -D man-pages=disabled; }
p_xwayland() {
    sed -i '/install_man/,$d' meson.build
    mbuild -D xkb_output_dir=/var/lib/xkb -D secure-rpc=false
}
p_xcbu() { abuild $XORG_CONFIG; }

# ---------------------------------------------------------------- ferramentas Wayland
p_tllist()  { mbuild; }
p_fcft()    { mbuild -D examples=false -D test-text-shaping=false; }
p_fuzzel()  { sed -i "/subdir('doc')/d" meson.build; mbuild -D enable-cairo=enabled -D png-backend=libpng -D svg-backend=nanosvg; }
p_mako()    { mbuild -D man-pages=disabled -D sd-bus-provider=libsystemd -D icons=enabled; }
p_swaybg()  { mbuild -D man-pages=disabled -D gdk-pixbuf=enabled; }
p_swaylock() {
    mbuild -D man-pages=disabled -D pam=enabled -D gdk-pixbuf=enabled \
           -D zsh-completions=false -D bash-completions=false -D fish-completions=false
    cat > /etc/pam.d/swaylock << "EOF"
# Begin /etc/pam.d/swaylock
auth      include     system-auth
# End /etc/pam.d/swaylock
EOF
}

# ---------------------------------------------------------------- niri, satélite X11, eww
p_dinfo03() {
    # o niri 26.04 (crate libdisplay-info-sys 0.3) quer libdisplay-info < 0.4; o sistema tem a 0.4.
    # Fica à parte em /opt, só para o niri, sem tocar na do sistema.
    mbuild --prefix=/opt/libdisplay-info-0.3 --libdir=lib
}
p_niri() {
    export PKG_CONFIG_PATH=/opt/libdisplay-info-0.3/lib/pkgconfig
    export RUSTFLAGS="-C link-arg=-Wl,-rpath,/opt/libdisplay-info-0.3/lib"
    cargo build --release --locked --no-default-features --features dbus,systemd
    install -vm755 target/release/niri /usr/bin/niri
    install -vm755 resources/niri-session /usr/bin/niri-session
    install -vDm644 resources/niri.desktop /usr/share/wayland-sessions/niri.desktop
    install -vDm644 resources/niri.service /usr/lib/systemd/user/niri.service
    install -vDm644 resources/niri-shutdown.target /usr/lib/systemd/user/niri-shutdown.target
    install -vDm644 resources/niri-portals.conf /usr/share/xdg-desktop-portal/niri-portals.conf
    niri --version
}
p_satellite() {
    cargo build --release --locked
    install -vm755 target/release/xwayland-satellite /usr/bin/xwayland-satellite
}
p_dbusmenu() {
    # a bandeja do eww usa a libdbusmenu (glib + gtk3); código de 2016: sem -Werror
    # o configure só define HAVE_VALGRIND com os testes ligados: damos-lhe o valor à mão
    export HAVE_VALGRIND_TRUE='#' HAVE_VALGRIND_FALSE=''
    CFLAGS="-O2 -Wno-error" ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
        --disable-static --disable-dumper --disable-tests --disable-vala --disable-gtk-doc \
        --enable-introspection=no --with-gtk=3
    make
    make -j1 install      # em paralelo, duas regras instalam os mesmos cabeçalhos ao mesmo tempo
}
p_eww() {
    # o Cargo.lock do eww 0.6.0 fixa time 0.3.34, que não compila com Rust >= 1.80
    cargo update -p time@0.3.34
    cargo build --release
    install -vm755 target/release/eww /usr/bin/eww
    eww --version
}

# ---------------------------------------------------------------- shell Nexora Flow
s_flow() {
    install -vm755 $F/bin/nexora-flow-start $F/bin/nexora-flow-niri $F/bin/nexora-flow-status /usr/bin/
    install -vdm755 /usr/share/nexora-flow/eww
    install -vm644 $F/eww/eww.yuck $F/eww/eww.scss /usr/share/nexora-flow/eww/
    install -vm644 $F/mako.conf /usr/share/nexora-flow/mako.conf
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    install -vDm644 $F/fuzzel.ini /etc/xdg/fuzzel/fuzzel.ini
    install -vDm644 $F/swaylock.conf /etc/swaylock/config
    install -vDm644 $F/gtk-3.0/settings.ini /etc/gtk-3.0/settings.ini
    # nomes bonitos no ecrã de login
    sed -i -e 's/^Name=.*/Name=Nexora Flow (Wayland)/' \
           -e 's/^Comment=.*/Comment=O ambiente da Nexora: janelas numa fita que desliza/' \
           /usr/share/wayland-sessions/niri.desktop
    sed -i -e 's/^Name=.*/Name=Xfce (clássico)/' /usr/share/xsessions/xfce.desktop
    niri validate -c /etc/niri/config.kdl
}

T0=$SECONDS
pkg  H.01-wayland          $B/wayland-1.26.0.tar.xz             p_wayland
pkg  H.02-wayland-protocols $B/wayland-protocols-1.49.tar.xz    p_wprotocols
pkg  H.03-mesa-wayland     $B/mesa-26.1.7.tar.xz                p_mesa_wl
pkg  H.04-gtk3-wayland     $B/gtk-3.24.52.tar.xz                p_gtk3_wl
pkg  H.05-gtk-layer-shell  $B/gtk-layer-shell-0.10.1.tar.gz     p_layershell
pkg  H.06-seatd            $B/seatd-0.9.3.tar.gz                p_seatd
pkg  H.07-xwayland         $B/xwayland-24.1.13.tar.xz           p_xwayland
pkg  H.08-xcb-renderutil   $B/xcb-util-renderutil-0.3.10.tar.xz p_xcbu
pkg  H.09-xcb-image        $B/xcb-util-image-0.4.1.tar.xz       p_xcbu
pkg  H.10-xcb-cursor       $B/xcb-util-cursor-0.1.6.tar.xz      p_xcbu
pkg  H.11-tllist           $B/tllist-1.1.0.tar.gz               p_tllist
pkg  H.12-fcft             $B/fcft-3.3.3.tar.gz                 p_fcft
pkg  H.13-fuzzel           $B/fuzzel-1.15.0.tar.gz              p_fuzzel
pkg  H.14-mako             $B/mako-1.11.0.tar.gz                p_mako
pkg  H.15-swaybg           $B/swaybg-1.2.2.tar.gz               p_swaybg
pkg  H.16-swaylock         $B/swaylock-1.8.6.tar.gz             p_swaylock
pkg  H.16b-libdisplay-info-0.3 $B/libdisplay-info-0.3.0.tar.xz p_dinfo03
pkg  H.17-niri             $B/niri-26.04.tar.gz                 p_niri
# (precisa de libclang: o LLVM da Nexora não tem clang) pkg  H.18-xwayland-satellite $B/xwayland-satellite-0.8.3.tar.gz p_satellite
pkg  H.18b-libdbusmenu      $B/libdbusmenu-16.04.0.tar.gz        p_dbusmenu
pkg  H.19-eww              $B/eww-0.6.0.tar.gz                  p_eww
step H.20-flow-config      s_flow
echo "🎉 Fase H (Nexora Flow: compilação) completa em $(( (SECONDS - T0) / 60 )) min"
