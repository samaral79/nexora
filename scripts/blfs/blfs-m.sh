#!/bin/bash
# Fase M (dentro do chroot, como root): vídeo e música.
#   dav1d (AV1), FFmpeg (descodificadores), libass (legendas), libplacebo, mpv (com libmpv)
#   e Celluloid (leitor GTK4 por cima do mpv).
source "$(dirname "$0")/lib.sh"
B=blfs

mbuild() {
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}

p_dav1d() { mbuild --wrap-mode=nofallback -D enable_tests=false -D enable_docs=false -D enable_examples=false; }
p_libass() { ./configure --prefix=/usr --disable-static; make; make install; }
p_ffmpeg() {
    patch -Np1 -i ../blfs/ffmpeg-9.0.1-chromium_method-1.patch
    ./configure --prefix=/usr --enable-gpl --enable-version3 --disable-static --enable-shared \
                --disable-debug --disable-doc --enable-libass --enable-libfreetype \
                --enable-libdav1d --enable-libvorbis --enable-openssl
    make
    make install
}
p_glad() {
    pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
    pip3 install --no-index --find-links dist --no-user glad2
}
p_vkheaders() {   # só headers; o libplacebo inclui o vulkan.h mesmo com o Vulkan desligado
    mkdir nx-build; cd nx-build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -G Ninja ..
    ninja; ninja install
}
p_placebo() { mbuild -D vulkan=disabled -D tests=false -D demos=false -D bench=false -D fuzz=false; }
p_mpv() {
    mbuild -D libmpv=true -D x11=enabled -D wayland=enabled -D pipewire=enabled -D pulse=enabled \
           -D alsa=enabled -D tests=false -D lua=disabled -D javascript=disabled
}
p_celluloid() {
    mbuild
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
s_caches() {
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    update-desktop-database -q /usr/share/applications || true
}

T0=$SECONDS
pkg  M.01-dav1d      $B/dav1d-1.5.4.tar.gz          p_dav1d
pkg  M.02-libass     $B/libass-0.17.5.tar.xz        p_libass
pkg  M.03-ffmpeg     $B/ffmpeg-9.0.1.tar.xz         p_ffmpeg
pkg  M.04-glad       $B/glad-2.0.8.tar.gz           p_glad
pkg  M.04b-vk-headers  $B/Vulkan-Headers-1.4.357.0.tar.gz p_vkheaders
pkg  M.05-libplacebo $B/libplacebo-7.360.1.tar.gz   p_placebo
pkg  M.06-mpv        $B/mpv-0.41.0.tar.gz           p_mpv
pkg  M.07-celluloid  $B/celluloid-0.30.tar.xz       p_celluloid
step M.08-caches     s_caches
echo "🎉 Fase M (vídeo e música) completa em $(( (SECONDS - T0) / 60 )) min"
