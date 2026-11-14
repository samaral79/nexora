#!/bin/bash
# Fase L (dentro do chroot, como root): mais apps sem compilar tudo.
#   Flatpak (+ OSTree, GnuPG para as assinaturas, bubblewrap já da fase K),
#   portais do ambiente de trabalho (diálogos de ficheiros, abrir links, Flatpak),
#   GNOME Software como loja ("Software") com o Flathub configurado.
source "$(dirname "$0")/lib.sh"
B=blfs

mbuild() {
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
abuild() { ./configure --prefix=/usr "$@"; make; make install; }

p_fuse3() {
    sed -i '/^udev/,$ s/^/#/' util/meson.build
    mbuild -D examples=false -D tests=false
    chmod u+s /usr/bin/fusermount3
}
p_dbusproxy() { mbuild -D man=disabled; }
p_yaml()      { abuild --disable-static; }
p_assuan()    { abuild; }
p_gpgme() {
    mkdir nx-build
    cd nx-build
    ../configure --prefix=/usr --disable-static --disable-gpg-test --disable-gpgsm-test
    make
    make install
}
p_ksba()      { abuild; }
p_npth()      { abuild; }
p_gnupg() {
    mkdir nx-build
    cd nx-build
    ../configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc --disable-ldap --enable-gpg-is-gpg2
    make
    make install
}
p_pyparsing() {
    pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
    pip3 install --no-index --find-links dist --no-user pyparsing
}
p_ostree() {
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static \
                --without-selinux --disable-gtk-doc --disable-man --with-curl --without-soup \
                --with-libarchive --disable-rofiles-fuse --without-grub2 --disable-dracut
    make
    make install
}
p_flatpak() {
    mbuild -D system_bubblewrap=bwrap -D system_dbus_proxy=xdg-dbus-proxy -D selinux_module=disabled \
           -D malcontent=disabled -D tests=false -D installed_tests=false -D man=disabled \
           -D docbook_docs=disabled -D gtkdoc=disabled -D privileged_group=wheel -D gir=enabled
}
p_dconf()     { mbuild -D bash_completion=false -D man=false -D gtk_doc=false -D vapi=false; }
p_portal() {
    mbuild -D tests=disabled -D documentation=disabled -D man-pages=disabled -D geoclue=disabled \
           -D installed-tests=false
}
p_portalgtk() { mbuild; }
s_portals() {
    # niri e Xfce usam o portal GTK (abrir ficheiros, escolher apps, definições)
    install -vdm755 /usr/share/xdg-desktop-portal
    for d in niri xfce; do
        printf '[preferred]\ndefault=gtk\n' > /usr/share/xdg-desktop-portal/$d-portals.conf
    done
}
p_software() {
    mbuild -D packagekit=false -D fwupd=false -D malcontent=false -D eos_updater=false \
           -D rpm_ostree=false -D snap=false -D apt=false -D tests=false -D installed_tests=false \
           -D man=false -D gtk_doc=false -D webapps=false -D hardcoded_foss_webapps=false \
           -D hardcoded_proprietary_webapps=false -D sysprof=disabled -D polkit=true \
           -D external_appstream=false -D dkms=false -D systemd-sysupdate=false -D mogwai=false \
           -D opensuse-distro-upgrade=false -D flatpak=true -D gudev=true
    glib-compile-schemas /usr/share/glib-2.0/schemas
}
s_flathub() {
    # o Flathub fica pronto para todos (instalações do sistema; a loja pede a senha via polkit)
    flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    # as apps Flatpak aparecem nos menus
    grep -q flatpak /etc/profile.d/flatpak.sh 2>/dev/null || true
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
    update-desktop-database -q /usr/share/applications || true
}

T0=$SECONDS
pkg  L.01-fuse3          $B/fuse-3.18.2.tar.gz              p_fuse3
pkg  L.02-xdg-dbus-proxy $B/xdg-dbus-proxy-0.1.8.tar.xz     p_dbusproxy
pkg  L.03-libyaml        $B/yaml-0.2.5.tar.gz               p_yaml
pkg  L.04-libassuan      $B/libassuan-3.0.2.tar.bz2         p_assuan
pkg  L.05-gpgme          $B/gpgme-2.1.2.tar.bz2             p_gpgme
pkg  L.06-libksba        $B/libksba-1.8.0.tar.bz2           p_ksba
pkg  L.07-npth           $B/npth-1.8.tar.bz2                p_npth
pkg  L.08-gnupg          $B/gnupg-2.5.21.tar.bz2            p_gnupg
pkg  L.09-pyparsing      $B/pyparsing-3.3.2.tar.gz          p_pyparsing
pkg  L.10-ostree         $B/libostree-2026.7.tar.xz         p_ostree
pkg  L.11-flatpak        $B/flatpak-1.18.4.tar.xz           p_flatpak
pkg  L.12-dconf          $B/dconf-0.49.0.tar.xz             p_dconf
pkg  L.13-portal         $B/xdg-desktop-portal-1.22.1.tar.xz p_portal
pkg  L.14-portal-gtk     $B/xdg-desktop-portal-gtk-1.15.3.tar.xz p_portalgtk
step L.15-portals        s_portals
pkg  L.16-software       $B/gnome-software-50.4.tar.xz      p_software
step L.17-flathub        s_flathub
echo "🎉 Fase L (Flatpak + loja) completa em $(( (SECONDS - T0) / 60 )) min"
