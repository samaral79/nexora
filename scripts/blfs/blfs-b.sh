#!/bin/bash
# BLFS 13.1 fase B (dentro do chroot, como root): Xorg + Mesa (llvmpipe) + pilha GTK3 + Rust/librsvg.
# Nexora: só X11 (sem Wayland), sem Vulkan nem codecs, LLVM só para o CPU (sem clang).
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs          # patches e ficheiros extra
export XORG_PREFIX=/usr
export XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc --localstatedir=/var --disable-static"
export PATH=/opt/rustc/bin:$PATH

# meson padrão: mbuild [opções...]
mbuild() {
    # pasta própria (há tarballs que já trazem uma pasta build/) e sem && (o set -e não apanha)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
# autotools padrão: abuild [opções...]
abuild() { ./configure --prefix=/usr "$@"; make; make install; }
# módulo Python: pywheel <nome>
pywheel() {
    pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
    pip3 install --no-index --find-links dist --no-user "$1"
}
# vários tarballs de uma lista md5 (libs/apps/fontes do Xorg)
xorg_loop() {   # xorg_loop <pasta> <ficheiro md5>
    local dir=$1 md5=$2 work
    work=$(mktemp -d /sources/xorg-XXXX)
    cd "$work"
    for package in $(grep -v '^#' $P/$md5 | awk '{print $2}'); do
        packagedir=${package%.tar.?z*}
        echo "=== $packagedir"
        tar -xf $P/$dir/$package
        pushd $packagedir
        docdir="--docdir=$XORG_PREFIX/share/doc/$packagedir"
        case $packagedir in
            libXfont2-[0-9]* ) ./configure $XORG_CONFIG $docdir --disable-devel-docs ;;
            libXt-[0-9]* )     ./configure $XORG_CONFIG $docdir --with-appdefaultdir=/etc/X11/app-defaults ;;
            libXpm-[0-9]* )    ./configure $XORG_CONFIG $docdir --disable-open-zfile ;;
            libpciaccess* | libxkbfile* )
                meson setup --prefix=$XORG_PREFIX --buildtype=release build
                ninja -C build; ninja -C build install
                popd; rm -rf $packagedir; continue ;;
            * )                ./configure $XORG_CONFIG $docdir ;;
        esac
        make
        make install
        popd
        rm -rf $packagedir
        /sbin/ldconfig
    done
    cd /sources; rm -rf "$work"
}

# ---------- ambiente Xorg ----------
s_xorgenv() {
    cat > /etc/profile.d/xorg.sh << "EOF"
XORG_PREFIX="/usr"
XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc --localstatedir=/var --disable-static"
export XORG_PREFIX XORG_CONFIG
EOF
    chmod 644 /etc/profile.d/xorg.sh
    cat > /etc/sudoers.d/xorg << "EOF"
Defaults env_keep += XORG_PREFIX
Defaults env_keep += XORG_CONFIG
EOF
}

p_utilmacros() { ./configure $XORG_CONFIG; make install; }
p_xorgproto()  { mbuild; mv -v /usr/share/doc/xorgproto{,-2025.1}; }
p_libxau()     { ./configure $XORG_CONFIG; make; make install; }
p_libxdmcp()   { ./configure $XORG_CONFIG --docdir='${datadir}'/doc/libXdmcp-1.1.5; make; make install; }
p_xcbproto()   { PYTHON=python3 ./configure $XORG_CONFIG; make install; rm -f /usr/lib/pkgconfig/xcb-proto.pc; }
p_libxcb() {
    ./configure $XORG_CONFIG --without-doxygen --docdir='${datadir}'/doc/libxcb-1.17.0
    LC_ALL=en_US.UTF-8 make
    make install
    chown -Rv root:root /usr/share/doc/libxcb-1.17.0
}
p_libpng() { abuild --disable-static; }
p_freetype() {
    sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
    sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" -i include/freetype/config/ftoption.h
    # harfbuzz carregado em runtime: não é preciso recompilar o freetype depois
    abuild --disable-static --enable-freetype-config --with-harfbuzz=dynamic
}
p_fontconfig() {
    abuild --sysconfdir=/etc --localstatedir=/var --disable-docs --docdir=/usr/share/doc/fontconfig-2.18.3
}
s_xorglibs() { xorg_loop xorg-lib lib-7.md5; }
p_xcbutil()  { ./configure $XORG_CONFIG; make; make install; }
p_libxcvt()  { mbuild; }
p_pixman()   { mbuild; }
p_libdrm()   { mbuild -D udev=true -D valgrind=disabled; }

# ---------- LLVM + Mesa ----------
p_cmake() {
    sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake
    ./bootstrap --prefix=/usr --mandir=/share/man --parallel=$(nproc) --docdir=/share/doc/cmake-4.4.2
    make
    make install
}
p_llvm() {
    patch -Np1 -i $P/llvm-22.1.8-upstream_fix-1.patch
    grep -rl '#!.*python$' | xargs sed -i '1s/python$/python3/'
    sed 's/utility/tool/' -i llvm/utils/FileCheck/CMakeLists.txt
    mkdir -v llvm/build && cd llvm/build
    # Nexora: só o alvo do CPU (llvmpipe + rustc), sem clang/compiler-rt
    CC=gcc CXX=g++ cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_SKIP_INSTALL_RPATH=ON -D LLVM_ENABLE_FFI=ON \
        -D CMAKE_BUILD_TYPE=Release -D LLVM_BUILD_LLVM_DYLIB=ON \
        -D LLVM_LINK_LLVM_DYLIB=ON -D LLVM_ENABLE_RTTI=ON \
        -D LLVM_TARGETS_TO_BUILD="host" -D LLVM_BINUTILS_INCDIR=/usr/include \
        -D LLVM_INCLUDE_BENCHMARKS=OFF -D LLVM_INCLUDE_TESTS=OFF \
        -D LLVM_INCLUDE_EXAMPLES=OFF -D LLVM_PARALLEL_LINK_JOBS=2 \
        -W no-author -G Ninja ..
    # C++ pesado: cada processo come 1-2 GB, com -j16 rebentou a RAM do shrek
    ninja -j8
    ninja install
}
p_mako()   { pywheel Mako; }
p_pyyaml() { pywheel PyYAML; }
p_mesa() {
    mbuild -D platforms=x11 -D gallium-drivers=llvmpipe,softpipe,virgl \
           -D vulkan-drivers="" -D valgrind=disabled -D libunwind=disabled
}

# ---------- servidor X ----------
p_xbitmaps() { ./configure $XORG_CONFIG; make install; }
s_xorgapps() { xorg_loop xorg-app app-7.md5; rm -f /usr/bin/xkeystone; }
p_xcursor()  { ./configure --prefix=/usr; make; make install; }
s_xorgfonts(){ xorg_loop xorg-font font-7.md5; }
p_xkbconfig(){ mbuild; }
p_libepoxy() { mbuild; }
p_mtdev()    { abuild --disable-static; }
p_libevdev() { mbuild -D documentation=disabled -D tests=disabled; }
p_libinput() { mbuild -D debug-gui=false -D tests=false -D libwacom=false -D udev-dir=/usr/lib/udev; }
p_xserver() {
    mbuild --localstatedir=/var -D glamor=true -D secure-rpc=false -D xkb_output_dir=/var/lib/xkb
    mkdir -pv /etc/X11/xorg.conf.d
}
p_xflibinput() { ./configure $XORG_CONFIG; make; make install; }
p_xinit() { ./configure $XORG_CONFIG --with-xinitdir=/etc/X11/app-defaults; make; make install; ldconfig; }
p_dejavu() {
    install -vdm755 /usr/share/fonts/dejavu
    install -vm644 ttf/*.ttf /usr/share/fonts/dejavu
    install -vm644 fontconfig/*.conf /usr/share/fontconfig/conf.avail/ 2>/dev/null || true
    fc-cache -f
}

# ---------- GLib, Pango, GTK3 ----------
p_glib() {
    patch -Np1 -i $P/glib-skip_warnings-1.patch
    mkdir build && cd build
    meson setup .. --prefix=/usr --buildtype=release -D introspection=disabled \
          -D glib_debug=disabled -D man-pages=disabled -D sysprof=disabled
    ninja
    ninja install
    tar xf $P/gobject-introspection-1.86.0.tar.xz
    meson setup gobject-introspection-1.86.0 gi-build --prefix=/usr --buildtype=release
    ninja -C gi-build
    ninja -C gi-build install
    meson configure -D introspection=enabled
    ninja
    ninja install
}
p_gsettings() {
    sed -i -r 's:"(/system):"/org/gnome\1:g' schemas/*.in
    mbuild
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
p_libxml2() {
    sed -i "/'git'/,+3d" meson.build
    mbuild -D history=enabled -D icu=disabled
}
p_atspi()    { mbuild -D gtk2_atk_adaptor=false; }
p_fribidi()  { mbuild; }
p_harfbuzz() { mbuild -D graphite2=disabled -D tests=disabled; }
p_cairo()    { mbuild; }
p_pango()    { mbuild --wrap-mode=nofallback -D introspection=enabled; }
p_smi()      { mbuild -D update-mimedb=true -D build-tests=false -D build-spec=false; }
p_nasm()     { ./configure --prefix=/usr; make; make install; }
p_libjpeg() {
    mkdir build && cd build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=RELEASE -D ENABLE_STATIC=FALSE \
          -D CMAKE_INSTALL_DEFAULT_LIBDIR=lib -D CMAKE_SKIP_INSTALL_RPATH=ON \
          -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/libjpeg-turbo-3.2.0 ..
    make
    make install
}
p_gdkpixbuf() {
    # Nexora: sem glycin (precisava de bubblewrap e mais Rust) -> loaders clássicos
    mbuild -D png=enabled -D jpeg=enabled -D gif=enabled -D tiff=disabled \
           -D glycin=disabled -D thumbnailer=disabled -D man=false --wrap-mode=nofallback
    gdk-pixbuf-query-loaders --update-cache
}
p_xkbcommon() {
    patch -Np1 -i $P/libxkbcommon-1.13.2-upstream_fix-1.patch
    mbuild -D enable-docs=false -D enable-wayland=false
}
p_hicolor()  { mbuild; }
p_isocodes() { mbuild; }
p_gtk3() {
    mbuild -D man=false -D broadway_backend=false -D wayland_backend=false
    gtk-query-immodules-3.0 --update-cache
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

# ---------- Rust + librsvg (ícones SVG) ----------
p_rust() {
    mkdir -pv /opt/rustc-1.97.1
    ln -svfn rustc-1.97.1 /opt/rustc
    cat << EOF > bootstrap.toml
change-id = 154587
[llvm]
link-shared = true
targets = "X86"
[build]
description = "for Nexora Linux 13.1"
docs = false
tools = ["cargo", "clippy", "rustdoc", "rustfmt", "src"]
[install]
prefix = "/opt/rustc-1.97.1"
docdir = "share/doc/rustc-1.97.1"
[rust]
channel = "stable"
lto = "thin"
codegen-units = 1
llvm-bitcode-linker = false
[target.x86_64-unknown-linux-gnu]
llvm-config = "/usr/bin/llvm-config"
EOF
    export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
    ./x.py build --jobs 8
    ./x.py install
    rm -fv /opt/rustc-1.97.1/share/doc/rustc-1.97.1/*.old
    [ -f /etc/bash_completion.d/cargo ] && mv -v /etc/bash_completion.d/cargo /usr/share/bash-completion/completions/ || true
    cat > /etc/profile.d/rustc.sh << "EOF"
# Begin /etc/profile.d/rustc.sh
export PATH=/opt/rustc/bin:$PATH
# End /etc/profile.d/rustc.sh
EOF
    /opt/rustc/bin/rustc --version
}
p_cargoc() {
    curl -fLO https://github.com/lu-zero/cargo-c/releases/download/v0.10.24/Cargo.lock
    export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
    cargo build --release
    install -vm755 target/release/cargo-{capi,cbuild,cinstall,ctest} /usr/bin/
}
p_librsvg() {
    sed -e "/OUTDIR/s|,| / 'librsvg-2.62.3', '--no-namespace-dir',|" \
        -e '/output/s|Rsvg-2.0|librsvg-2.62.3|' -i doc/meson.build
    mbuild -D docs=disabled -D vala=disabled -D tests=false
    gdk-pixbuf-query-loaders --update-cache
}

T0=$SECONDS
step B.00-xorg-env       s_xorgenv
pkg  B.01-util-macros    $B/util-macros-1.20.2.tar.xz        p_utilmacros
pkg  B.02-xorgproto      $B/xorgproto-2025.1.tar.xz          p_xorgproto
pkg  B.03-libXau         $B/libXau-1.0.12.tar.xz             p_libxau
pkg  B.04-libXdmcp       $B/libXdmcp-1.1.5.tar.xz            p_libxdmcp
pkg  B.05-xcb-proto      $B/xcb-proto-1.17.0.tar.xz          p_xcbproto
pkg  B.06-libxcb         $B/libxcb-1.17.0.tar.xz             p_libxcb
pkg  B.07-libpng         $B/libpng-1.6.58.tar.xz             p_libpng
pkg  B.08-freetype       $B/freetype-2.14.3.tar.xz           p_freetype
pkg  B.09-fontconfig     $B/fontconfig-2.18.3.tar.xz         p_fontconfig
step B.10-xorg-libs      s_xorglibs
pkg  B.11-xcb-util       $B/xcb-util-0.4.1.tar.xz            p_xcbutil
pkg  B.12-libxcvt        $B/libxcvt-0.1.3.tar.xz             p_libxcvt
pkg  B.13-pixman         $B/pixman-0.46.4.tar.gz             p_pixman
pkg  B.14-libdrm         $B/libdrm-2.4.134.tar.xz            p_libdrm
pkg  B.15-cmake          $B/cmake-4.4.2.tar.gz               p_cmake
pkg  B.16-llvm           $B/llvm-project-22.1.8.src.tar.xz   p_llvm
pkg  B.17-mako           $B/mako-1.4.1.tar.gz                p_mako
pkg  B.18-pyyaml         $B/pyyaml-6.0.3.tar.gz              p_pyyaml
pkg  B.19-mesa           $B/mesa-26.1.7.tar.xz               p_mesa
pkg  B.20-xbitmaps       $B/xbitmaps-1.1.4.tar.xz            p_xbitmaps
step B.21-xorg-apps      s_xorgapps
pkg  B.22-xcursor-themes $B/xcursor-themes-1.0.7.tar.xz      p_xcursor
step B.23-xorg-fonts     s_xorgfonts
pkg  B.24-xkeyboard-config $B/xkeyboard-config-2.48.tar.xz   p_xkbconfig
pkg  B.25-libepoxy       $B/libepoxy-1.5.10.tar.xz           p_libepoxy
pkg  B.26-mtdev          $B/mtdev-1.1.7.tar.bz2              p_mtdev
pkg  B.27-libevdev       $B/libevdev-1.13.6.tar.xz           p_libevdev
pkg  B.28-libinput       $B/libinput-1.31.3.tar.gz           p_libinput
pkg  B.29-xorg-server    $B/xorg-server-21.1.24.tar.xz       p_xserver
pkg  B.30-xf86-libinput  $B/xf86-input-libinput-1.5.0.tar.xz p_xflibinput
pkg  B.31-xinit          $B/xinit-1.4.4.tar.xz               p_xinit
pkg  B.32-dejavu         $B/dejavu-fonts-ttf-2.37.tar.bz2    p_dejavu
pkg  B.33-glib           $B/glib-2.88.3.tar.xz               p_glib
pkg  B.34-gsettings      $B/gsettings-desktop-schemas-50.1.tar.xz p_gsettings
pkg  B.35-libxml2        $B/libxml2-2.15.3.tar.xz            p_libxml2
pkg  B.36-at-spi2-core   $B/at-spi2-core-2.60.6.tar.xz       p_atspi
pkg  B.37-fribidi        $B/fribidi-1.0.16.tar.xz            p_fribidi
pkg  B.38-harfbuzz       $B/harfbuzz-14.3.1.tar.xz           p_harfbuzz
pkg  B.39-cairo          $B/cairo-1.18.4.tar.xz              p_cairo
pkg  B.40-pango          $B/pango-1.58.2.tar.xz              p_pango
pkg  B.41-shared-mime    $B/shared-mime-info-2.5.1.tar.gz    p_smi
pkg  B.42-nasm           $B/nasm-3.02.tar.xz                 p_nasm
pkg  B.43-libjpeg        $B/libjpeg-turbo-3.2.0.tar.gz       p_libjpeg
pkg  B.44-gdk-pixbuf     $B/gdk-pixbuf-2.44.7.tar.xz         p_gdkpixbuf
pkg  B.45-libxkbcommon   $B/libxkbcommon-1.13.2.tar.gz       p_xkbcommon
pkg  B.46-hicolor        $B/hicolor-icon-theme-0.18.tar.xz   p_hicolor
pkg  B.47-iso-codes      $B/iso-codes-v4.20.1.tar.gz         p_isocodes
pkg  B.48-gtk3           $B/gtk-3.24.52.tar.xz               p_gtk3
pkg  B.49-rust           $B/rustc-1.97.1-src.tar.xz          p_rust
pkg  B.50-cargo-c        $B/cargo-c-0.10.24.tar.gz           p_cargoc
pkg  B.51-librsvg        $B/librsvg-2.62.3.tar.xz            p_librsvg
echo "🎉 BLFS fase B completa em $(( (SECONDS - T0) / 60 )) min"
