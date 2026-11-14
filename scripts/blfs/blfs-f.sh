#!/bin/bash
# Fase F (dentro do chroot, como root): o que o live e o instalador precisam.
#   GnuTLS (e vte com ele), dosfstools, efibootmgr, rsync, PyGObject, cpio, nexora-installer.
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs
I=$(dirname "$0")/installer

mbuild() {
    # pasta própria (há tarballs que já trazem uma pasta build/) e sem && (o set -e não apanha)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
abuild() { ./configure --prefix=/usr "$@"; make; make install; }

p_nettle() {
    abuild --disable-static
    chmod -v 755 /usr/lib/lib{hogweed,nettle}.so
}
p_gnutls() {
    abuild --docdir=/usr/share/doc/gnutls-3.8.13 --with-default-trust-store-pkcs11="pkcs11:"
}
p_vte() {
    # agora com GnuTLS: o terminal deixa de avisar que o histórico vai para o disco sem cifra
    mbuild -D gtk4=false -D vapi=false -D gir=false -D _systemd=false \
           -D gnutls=true -D icu=false -D glade=false -D app=false
    rm -fv /etc/profile.d/vte.*
}
p_popt()       { abuild --disable-static; }
p_efivar() {
    patch -Np1 -i $P/efivar-39-upstream_fixes-1.patch
    make ENABLE_DOCS=0
    make install ENABLE_DOCS=0 LIBDIR=/usr/lib
}
p_efibootmgr() {
    make EFIDIR=Nexora EFI_LOADER=grubx64.efi
    make install EFIDIR=Nexora
}
p_dosfstools() {
    abuild --enable-compat-symlinks --mandir=/usr/share/man --docdir=/usr/share/doc/dosfstools-4.2
}
p_rsync()   { abuild --disable-xxhash --without-included-zlib; }
p_pycairo() { mbuild; }
p_pygobject() {
    mv -v tests/test_gdbus.py{,.nouse}
    mv -v tests/test_overrides_gtk.py{,.nouse}
    mbuild
}
p_cpio() {
    sed -e "/^extern int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" -i src/extern.h
    sed -e "/^int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" -i src/global.c
    abuild --enable-mt --with-rmt=/usr/libexec/rmt
}

s_installer() {
    install -vm755 $I/nexora-install-engine /usr/sbin/nexora-install-engine
    install -vm755 $I/nexora-installer /usr/bin/nexora-installer
    install -vm644 $I/nexora-installer.desktop /usr/share/applications/nexora-installer.desktop
    # o instalador tem de conseguir importar o GTK por PyGObject
    python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk'
    # o sshd gera as chaves da máquina no primeiro arranque (a ISO não leva nenhumas)
    install -dm755 /etc/systemd/system/sshd.service.d
    printf '[Service]\nExecStartPre=/usr/bin/ssh-keygen -A\n' > /etc/systemd/system/sshd.service.d/keygen.conf
}

T0=$SECONDS
pkg  F.01-nettle       $B/nettle-4.0.tar.gz             p_nettle
pkg  F.02-gnutls       $B/gnutls-3.8.13.tar.xz          p_gnutls
pkg  F.03-vte          $B/vte-0.84.1.tar.gz             p_vte
pkg  F.04-popt         $B/popt-1.19.tar.gz              p_popt
pkg  F.05-efivar       $B/efivar-39.tar.gz              p_efivar
pkg  F.06-efibootmgr   $B/efibootmgr-18.tar.gz          p_efibootmgr
pkg  F.07-dosfstools   $B/dosfstools-4.2.tar.gz         p_dosfstools
pkg  F.08-rsync        $B/rsync-3.5.0.tar.gz            p_rsync
pkg  F.09-pycairo      $B/pycairo-1.29.1.tar.gz         p_pycairo
pkg  F.10-pygobject    $B/pygobject-3.56.3.tar.gz       p_pygobject
pkg  F.11-cpio         $B/cpio-2.15.tar.bz2             p_cpio
step F.12-installer    s_installer
echo "🎉 Fase F (live e instalador) completa em $(( SECONDS - T0 ))s"
