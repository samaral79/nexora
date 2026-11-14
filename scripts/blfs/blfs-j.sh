#!/bin/bash
# Fase J (dentro do chroot, como root): base moderna.
#   GTK4 + libadwaita (apps GNOME modernas), gtksourceview5, libportal, AppStream,
#   som com PipeWire (+ WirePlumber, servidor PulseAudio compatível) e pavucontrol,
#   VTE com GTK4 (para o terminal novo).
source "$(dirname "$0")/lib.sh"
B=blfs

mbuild() {
    # pasta própria e sem && (o set -e não apanha falhas dentro de &&)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}

# ---------------------------------------------------------------- GTK4 e libadwaita
p_graphene() { mbuild -D tests=false -D installed_tests=false; }
p_gtk4() {
    mbuild -D broadway-backend=false -D introspection=enabled -D vulkan=disabled \
           -D media-gstreamer=disabled -D build-tests=false -D build-testsuite=false \
           -D build-demos=false -D build-examples=false -D documentation=false -D man-pages=false
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
p_xmlb()       { mbuild -D gtkdoc=false -D tests=false; }
p_fyaml()      { ./configure --prefix=/usr --disable-static --without-libclang; make; make install; }
p_appstream()  { mbuild -D apidocs=false -D docs=false -D bash-completion=false -D stemming=false -D man=false; }
p_adwaita()    { mbuild -D vapi=false -D documentation=false -D tests=false -D examples=false; }
p_gsv5()       { mbuild -D vapi=false -D documentation=false -D install-tests=false; }
p_portal() {
    [ -e /usr/include/libportal ] && rm -rf /usr/include/libportal
    mbuild -D vapi=false -D docs=false -D tests=false -D backend-gtk3=enabled -D backend-gtk4=enabled \
           -D backend-qt5=disabled -D backend-qt6=disabled
}
p_vte4() {
    # VTE outra vez, agora também com GTK4 (o terminal novo usa-o)
    mbuild -D gtk3=true -D gtk4=true -D vapi=false -D gir=true -D _systemd=false \
           -D gnutls=true -D icu=false -D glade=false -D app=false
    rm -fv /etc/profile.d/vte.*
}

# ---------------------------------------------------------------- som
p_lua() {
    cat > lua.pc << "EOF"
V=5.4
R=5.4.8

prefix=/usr
INSTALL_BIN=${prefix}/bin
INSTALL_INC=${prefix}/include
INSTALL_LIB=${prefix}/lib
INSTALL_MAN=${prefix}/share/man/man1
INSTALL_LMOD=${prefix}/share/lua/${V}
INSTALL_CMOD=${prefix}/lib/lua/${V}
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Requires:
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
    patch -Np1 -i ../blfs/lua-5.4.8-shared_library-1.patch
    make linux
    make INSTALL_TOP=/usr INSTALL_DATA="cp -d" INSTALL_MAN=/usr/share/man/man1 \
         TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.8" install
    install -vDm644 lua.pc /usr/lib/pkgconfig/lua.pc
}
p_sndfile() {
    sed -i '/typedef enum/,/bool ;/d' src/ALAC/alac_{en,de}coder.c
    ./configure --prefix=/usr --disable-static
    make
    make install
}
p_pulse() {
    # só as bibliotecas de cliente (libpulse): o servidor de som é o PipeWire
    mbuild -D daemon=false -D doxygen=false -D tests=false -D man=false -D bluez5=disabled \
           -D database=simple -D gtk=disabled
}
p_pipewire() {
    mbuild -D session-managers="[]" -D tests=disabled -D man=disabled -D docs=disabled \
           -D gstreamer=disabled -D bluez5=disabled -D jack=disabled -D pipewire-jack=disabled \
           -D libcamera=disabled -D vulkan=disabled -D roc=disabled -D libffado=disabled \
           -D examples=disabled -D sdl2=disabled -D snap=disabled
}
p_wireplumber() {
    mbuild -D system-lua=true -D doc=disabled -D tests=false -D introspection=disabled
}
s_sound() {
    # PipeWire, o servidor "PulseAudio" do PipeWire e o WirePlumber arrancam em todas as sessões
    systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
}

# ---------------------------------------------------------------- pavucontrol (C++)
p_sigc3()   { sed -i "s/'system',//" meson.build; mbuild -D build-examples=false -D build-tests=false -D build-documentation=false; }
p_glibmm()  { mbuild -D build-examples=false -D build-documentation=false; }
p_cairomm() { mbuild -D build-tests=false -D build-examples=false -D build-documentation=false; }
p_pangomm() { mbuild -D build-documentation=false; }
p_gtkmm4()  { mbuild -D build-demos=false -D build-tests=false -D build-documentation=false; }
p_jsonglib(){ mbuild -D tests=false -D documentation=disabled -D man=false; }
p_pavu()    { mbuild -D lynx=disabled; }

T0=$SECONDS
pkg  J.01-graphene      $B/graphene-1.10.8.tar.xz        p_graphene
pkg  J.02-gtk4          $B/gtk-4.22.4.tar.xz             p_gtk4
pkg  J.03-libxmlb       $B/libxmlb-0.3.29.tar.xz         p_xmlb
pkg  J.03b-libfyaml     $B/libfyaml-0.9.6.tar.gz          p_fyaml
pkg  J.04-appstream     $B/AppStream-1.1.6.tar.xz        p_appstream
pkg  J.05-libadwaita    $B/libadwaita-1.9.3.tar.xz       p_adwaita
pkg  J.06-gtksourceview5 $B/gtksourceview-5.20.0.tar.xz  p_gsv5
pkg  J.07-libportal     $B/libportal-0.9.1.tar.xz        p_portal
pkg  J.08-vte-gtk4      $B/vte-0.84.1.tar.gz             p_vte4
pkg  J.09-lua           $B/lua-5.4.8.tar.gz              p_lua
pkg  J.10-libsndfile    $B/libsndfile-1.2.2.tar.xz       p_sndfile
pkg  J.11-libpulse      $B/pulseaudio-17.0.tar.xz        p_pulse
pkg  J.12-pipewire      $B/pipewire-1.6.8.tar.bz2        p_pipewire
pkg  J.13-wireplumber   $B/wireplumber-0.5.15.tar.bz2    p_wireplumber
step J.14-sound         s_sound
pkg  J.15-libsigc3      $B/libsigc++-3.6.0.tar.xz        p_sigc3
pkg  J.16-glibmm        $B/glibmm-2.88.1.tar.xz          p_glibmm
pkg  J.17-cairomm       $B/cairomm-1.18.1.tar.xz         p_cairomm
pkg  J.18-pangomm       $B/pangomm-2.56.2.tar.xz         p_pangomm
pkg  J.19-gtkmm4        $B/gtkmm-4.22.0.tar.xz           p_gtkmm4
pkg  J.20-json-glib     $B/json-glib-1.10.8.tar.xz       p_jsonglib
pkg  J.21-pavucontrol   $B/pavucontrol-6.2.tar.xz        p_pavu
echo "🎉 Fase J (GTK4 + som) completa em $(( (SECONDS - T0) / 60 )) min"
