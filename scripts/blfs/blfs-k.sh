#!/bin/bash
# Fase K (dentro do chroot, como root): apps modernas (GTK4 + libadwaita).
#   Ficheiros (Nautilus), Imagens (Loupe), Calculadora, Arquivos (File Roller),
#   Uso do disco (Baobab), Monitor do sistema, Editor de texto, Terminal (Ptyxis).
source "$(dirname "$0")/lib.sh"
B=blfs
export PATH=/opt/rustc/bin:$PATH
export CARGO_HOME=/sources/cargo-home
export CARGO_BUILD_JOBS=$(( ${NX_JOBS:-8} < 8 ? ${NX_JOBS:-8} : 8 ))

mbuild() {
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
cbuild() {
    mkdir nx-build
    cd nx-build
    cmake -G Ninja -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D CMAKE_SKIP_INSTALL_RPATH=ON "$@" ..
    ninja
    ninja install
}
abuild() { ./configure --prefix=/usr --disable-static "$@"; make; make install; }

# ---------------------------------------------------------------- bases
p_seccomp()   { abuild; }
p_bwrap()     { mbuild -D man=disabled -D tests=false; }
p_lcms2()     { mbuild -D tests=disabled; }
p_icu()       { cd source; ./configure --prefix=/usr; make; make install; }
p_gst()       { mbuild -D gst_debug=false -D tests=disabled -D examples=disabled -D doc=disabled; }
p_gstbase()   { mbuild --wrap-mode=nodownload -D tests=disabled -D examples=disabled -D doc=disabled; }
p_glycin() {
    # carregadores de imagens em sandbox (bubblewrap) + a biblioteca GTK4 que o Loupe e o Nautilus usam
    cargo vendor >/dev/null
    mbuild -D tests=false -D libglycin-gtk4=true -D introspection=true -D vapi=false -D capi_docs=false \
          -D loaders=glycin-image-rs,glycin-svg   # sem HEIF/JXL (não temos libheif/libjxl)
}
p_blueprint() { mbuild; }
p_exiv2() {
    cbuild -D EXIV2_ENABLE_VIDEO=yes -D EXIV2_ENABLE_WEBREADY=yes -D EXIV2_ENABLE_CURL=yes \
           -D EXIV2_BUILD_SAMPLES=no -D EXIV2_BUILD_EXIV2_COMMAND=yes -D EXIV2_ENABLE_INIH=no \
           -D EXIV2_ENABLE_BROTLI=no -D EXIV2_BUILD_UNIT_TESTS=no
}
p_gexiv2()    { mbuild -D vapi=false -D gtk_doc=false -D tests=false; }
p_nghttp2()   { abuild --enable-lib-only; }
p_gnet()      { mbuild -D libproxy=disabled -D installed_tests=false; }
p_soup3() {
    patch -Np1 -i ../blfs/libsoup-3.6.6-upstream_fixes-1.patch
    mbuild --wrap-mode=nofallback -D vapi=disabled -D docs=disabled -D tests=false -D sysprof=disabled
}
p_geocode()   { mbuild -D enable-gtk-doc=false -D soup2=false -D enable-installed-tests=false; }
p_gwlocs()    { mbuild; }
p_gweather()  { mbuild -D gtk_doc=false -D tests=false -D enable_vala=false; }
p_loupe() {
    mbuild
    rm -fv /usr/share/applications/org.gnome.eog.desktop
}

# ---------------------------------------------------------------- Ficheiros
p_archive() {
    abuild
    ln -sfv bsdunzip /usr/bin/unzip
}
# o libadwaita e o gtksourceview5 da fase J foram feitos sem vapi (ainda não havia Vala); as apps em Vala precisam
p_adw_vapi()  { mbuild -D vapi=true -D documentation=false -D tests=false -D examples=false; }
p_gsv5_vapi() { mbuild -D vapi=true -D documentation=false -D install-tests=false; }
p_soup3_vapi() {
    # o libsoup-3.0.vapi que vem com o Vala é velho (falta send_and_splice); gera-se o do próprio libsoup
    patch -Np1 -i ../blfs/libsoup-3.6.6-upstream_fixes-1.patch
    mbuild --wrap-mode=nofallback -D vapi=enabled -D docs=disabled -D tests=false -D sysprof=disabled
    cp -v /usr/share/vala/vapi/libsoup-3.0.{vapi,deps} /usr/share/vala-0.56/vapi/
}
p_vala()      { ./configure --prefix=/usr --disable-valadoc; make; make install; }
p_autoar()    { mbuild -D vapi=false -D gtk_doc=false -D tests=false; }
p_gdesktop()  { mbuild -D desktop_docs=false -D build_gtk4=true -D legacy_library=true -D installed_tests=false; }
p_tinysparql() {
    rm -fv /usr/lib/systemd/user/tracker-xdg-portal-3.service
    mbuild -D man=false -D docs=false -D tests=false
}
p_nautilus() {
    mbuild -D selinux=disabled -D docs=false -D tests=none -D packagekit=false -D cloudproviders=false
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

# ---------------------------------------------------------------- utilitários
p_gee()       { ./configure --prefix=/usr --enable-vala --disable-static; make; make install; }
p_calc()      { mbuild -D ui-tests=false -D doc=false; }
p_froller() {
    mbuild -D packagekit=false -D nautilus-actions=disabled -D api_docs=disabled
    chmod -v 0755 /usr/libexec/file-roller/isoinfo.sh || true
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
p_baobab()    { mbuild; }
p_gtop()      { abuild; }
p_gsm() {
    find . -name meson.build | xargs sed -i -e '/catch2/d'
    sed -i '141,151d' src/meson.build
    mbuild
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

# ---------------------------------------------------------------- editor e terminal
p_enchant()   { mkdir -p /usr/lib/enchant-2; abuild --sysconfdir=/etc --disable-static; }   # sem corretores, a pasta dos providers não é criada
p_spelling()  { mbuild -D docs=false -D vapi=false -D introspection=disabled -D sysprof=false; }
p_editorconfig() {
    cbuild -D BUILD_DOCUMENTATION=OFF
    rm -fv /usr/lib/libeditorconfig_static.a
}
p_texteditor() {
    mbuild -D development=false
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
p_ptyxis() {
    mbuild -D development=false
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

s_caches() {
    glib-compile-schemas /usr/share/glib-2.0/schemas
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    update-desktop-database -q /usr/share/applications || true
}

T0=$SECONDS
pkg  K.00a-icu          $B/icu4c-78.3-sources.tgz          p_icu
pkg  K.00b-gstreamer    $B/gstreamer-1.28.6.tar.xz         p_gst
pkg  K.00c-gst-base     $B/gst-plugins-base-1.28.6.tar.xz  p_gstbase
pkg  K.01-libseccomp     $B/libseccomp-2.6.1.tar.gz         p_seccomp
pkg  K.02-bubblewrap     $B/bubblewrap-0.11.2.tar.xz        p_bwrap
pkg  K.03-lcms2          $B/lcms2-2.19.1.tar.gz             p_lcms2
pkg  K.04-glycin         $B/glycin-2.1.5.tar.xz             p_glycin
pkg  K.05-blueprint      $B/blueprint-compiler-0.22.2.tar.xz p_blueprint
pkg  K.06-exiv2          $B/exiv2-0.28.8.tar.gz             p_exiv2
pkg  K.07-gexiv2         $B/gexiv2-0.16.2.tar.xz            p_gexiv2
pkg  K.08-nghttp2        $B/nghttp2-1.70.0.tar.xz           p_nghttp2
pkg  K.09-glib-networking $B/glib-networking-2.80.1.tar.xz  p_gnet
pkg  K.10-libsoup3       $B/libsoup-3.6.6.tar.xz            p_soup3
pkg  K.11-geocode-glib   $B/geocode-glib-3.26.4.tar.xz      p_geocode
pkg  K.11b-gweather-locs $B/gweather-locations-2026.2.tar.xz p_gwlocs
pkg  K.12-libgweather    $B/libgweather-4.6.0.tar.xz        p_gweather
pkg  K.13-loupe          $B/loupe-49.2.tar.xz               p_loupe
pkg  K.14-libarchive     $B/libarchive-3.8.9.tar.xz         p_archive
pkg  K.15-vala           $B/vala-0.56.19.tar.xz             p_vala
pkg  K.15b-adwaita-vapi  $B/libadwaita-1.9.3.tar.xz         p_adw_vapi
pkg  K.15c-gsv5-vapi     $B/gtksourceview-5.20.0.tar.xz     p_gsv5_vapi
pkg  K.15d-libsoup3-vapi $B/libsoup-3.6.6.tar.xz            p_soup3_vapi
pkg  K.16-gnome-autoar   $B/gnome-autoar-0.4.5.tar.xz       p_autoar
pkg  K.17-gnome-desktop  $B/gnome-desktop-44.5.tar.xz       p_gdesktop
pkg  K.18-tinysparql     $B/tinysparql-3.11.1.tar.xz        p_tinysparql
pkg  K.19-nautilus       $B/nautilus-50.2.2.tar.xz          p_nautilus
pkg  K.20-libgee         $B/libgee-0.20.8.tar.xz            p_gee
pkg  K.21-calculator     $B/gnome-calculator-50.0.tar.xz    p_calc
pkg  K.22-file-roller    $B/file-roller-44.7.tar.xz         p_froller
pkg  K.23-baobab         $B/baobab-50.0.tar.xz              p_baobab
pkg  K.24-libgtop        $B/libgtop-2.41.3.tar.xz           p_gtop
pkg  K.25-system-monitor $B/gnome-system-monitor-50.0.tar.xz p_gsm
pkg  K.26-enchant        $B/enchant-2.8.19.tar.gz           p_enchant
pkg  K.27-libspelling    $B/libspelling-0.4.11.tar.xz       p_spelling
pkg  K.28-editorconfig   $B/editorconfig-core-c-0.12.11.tar.gz p_editorconfig
pkg  K.29-text-editor    $B/gnome-text-editor-50.1.tar.xz   p_texteditor
pkg  K.30-ptyxis         $B/ptyxis-50.1.tar.xz              p_ptyxis
step K.31-caches         s_caches
echo "🎉 Fase K (apps GTK4) completa em $(( (SECONDS - T0) / 60 )) min"
