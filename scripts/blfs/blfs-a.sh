#!/bin/bash
# BLFS 13.1 fase A (dentro do chroot, como root): PAM, certificados, rede e ferramentas.
#   Linux-PAM -> shadow e systemd recompilados com PAM -> certificados -> curl/wget/git -> sudo, SSH
# Fontes em /sources/blfs (montadas do projeto pelo chroot.sh).
source "$(dirname "$0")/lib.sh"
B=blfs   # tarballs relativos a /sources

# ---------- PAM ----------
p_pam() {
    mkdir build && cd build
    meson setup .. --prefix=/usr --buildtype=release -D docdir=/usr/share/doc/Linux-PAM-1.7.2
    ninja
    ninja install
    chmod -v 4755 /usr/sbin/unix_chkpwd
    install -vdm755 /etc/pam.d
    cat > /etc/pam.d/system-account << "EOF"
# Begin /etc/pam.d/system-account
account   required    pam_unix.so
# End /etc/pam.d/system-account
EOF
    cat > /etc/pam.d/system-auth << "EOF"
# Begin /etc/pam.d/system-auth
auth      required    pam_unix.so
# End /etc/pam.d/system-auth
EOF
    cat > /etc/pam.d/system-session << "EOF"
# Begin /etc/pam.d/system-session
session   required    pam_unix.so
# End /etc/pam.d/system-session
EOF
    cat > /etc/pam.d/system-password << "EOF"
# Begin /etc/pam.d/system-password
password  required    pam_unix.so       yescrypt shadow try_first_pass
# End /etc/pam.d/system-password
EOF
    cat > /etc/pam.d/other << "EOF"
# Begin /etc/pam.d/other
auth        required        pam_warn.so
auth        required        pam_deny.so
account     required        pam_warn.so
account     required        pam_deny.so
password    required        pam_warn.so
password    required        pam_deny.so
session     required        pam_warn.so
session     required        pam_deny.so
# End /etc/pam.d/other
EOF
}

p_shadow() {
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
    sed -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD YESCRYPT@' \
        -e 's@/var/spool/mail@/var/mail@'                   \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
        -i etc/login.defs
    ./configure --sysconfdir=/etc --disable-static --without-libbsd --with-{b,yes}crypt
    make
    make exec_prefix=/usr pamddir= install
    make -C man install-man
    install -v -m644 /etc/login.defs /etc/login.defs.orig
    for FUNCTION in FAIL_DELAY FAILLOG_ENAB LASTLOG_ENAB MAIL_CHECK_ENAB \
                    OBSCURE_CHECKS_ENAB PORTTIME_CHECKS_ENAB QUOTAS_ENAB \
                    CONSOLE MOTD_FILE FTMP_FILE NOLOGINS_FILE ENV_HZ PASS_MIN_LEN \
                    SU_WHEEL_ONLY PASS_CHANGE_TRIES PASS_ALWAYS_WARN \
                    CHFN_AUTH ENCRYPT_METHOD ENVIRON_FILE; do
        sed -i "s/^${FUNCTION}/# &/" /etc/login.defs
    done
    cat > /etc/pam.d/login << "EOF"
# Begin /etc/pam.d/login
auth      optional    pam_faildelay.so  delay=3000000
auth      requisite   pam_nologin.so
auth      include     system-auth
account   required    pam_access.so
account   include     system-account
session   required    pam_env.so
session   required    pam_limits.so
session   include     system-session
password  include     system-password
# End /etc/pam.d/login
EOF
    cat > /etc/pam.d/passwd << "EOF"
# Begin /etc/pam.d/passwd
password  include     system-password
# End /etc/pam.d/passwd
EOF
    cat > /etc/pam.d/su << "EOF"
# Begin /etc/pam.d/su
auth      sufficient  pam_rootok.so
auth      include     system-auth
account   include     system-account
session   required    pam_env.so
session   include     system-session
# End /etc/pam.d/su
EOF
    cat > /etc/pam.d/chpasswd << "EOF"
# Begin /etc/pam.d/chpasswd
auth      sufficient  pam_rootok.so
auth      include     system-auth
account   include     system-account
password  include     system-password
# End /etc/pam.d/chpasswd
EOF
    sed -e s/chpasswd/newusers/ /etc/pam.d/chpasswd > /etc/pam.d/newusers
    cat > /etc/pam.d/chage << "EOF"
# Begin /etc/pam.d/chage
auth      sufficient  pam_rootok.so
auth      include     system-auth
account   include     system-account
# End /etc/pam.d/chage
EOF
    for PROGRAM in chfn chgpasswd chsh groupadd groupdel groupmems groupmod useradd userdel usermod; do
        install -v -m644 /etc/pam.d/chage /etc/pam.d/${PROGRAM}
        sed -i "s/chage/$PROGRAM/" /etc/pam.d/${PROGRAM}
    done
    if [ -f /etc/login.access ]; then mv -v /etc/login.access{,.NOUSE}; fi
    if [ -f /etc/limits ]; then mv -v /etc/limits{,.NOUSE}; fi
}

p_systemd() {
    rm -fv /usr/lib/systemd/system/systemd-update-utmp-runlevel.service
    sed -i -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in
    mkdir build && cd build
    meson setup .. --prefix=/usr --buildtype=release \
          -D default-dnssec=no -D firstboot=false -D install-tests=false \
          -D ldconfig=false -D man=auto -D sysusers=false -D rpmmacrosdir=no \
          -D homed=disabled -D mode=release -D pam=enabled -D pamconfdir=/etc/pam.d \
          -D dev-kvm-mode=0660 -D nobody-group=nogroup -D sysupdate=disabled \
          -D ukify=disabled -D docdir=/usr/share/doc/systemd-261.2
    ninja
    ninja install
    grep 'pam_systemd' /etc/pam.d/system-session || cat >> /etc/pam.d/system-session << "EOF"
# Begin Systemd addition
session  required    pam_loginuid.so
session  optional    pam_systemd.so
# End Systemd addition
EOF
    cat > /etc/pam.d/systemd-user << "EOF"
# Begin /etc/pam.d/systemd-user
account  required    pam_access.so
account  include     system-account
session  required    pam_env.so
session  required    pam_limits.so
session  required    pam_loginuid.so
session  optional    pam_keyinit.so force revoke
session  optional    pam_systemd.so
auth     required    pam_deny.so
password required    pam_deny.so
# End /etc/pam.d/systemd-user
EOF
    install -vdm755 /etc/systemd/user-environment-generators
    cat > /etc/systemd/user-environment-generators/50-profile.sh << "EOF"
#!/usr/bin/env -S -i /usr/bin/bash
# SPDX-License-Identifier: MIT
. /etc/profile
unset XDG_RUNTIME_DIR
for i in $(locale); do
  unset ${i%=*}
done
unset SHLVL
for i in $(declare -pF | awk '{print $3}'); do
  unset -f $i
done
python3 << _EOF
import os
for var in os.environ:
  if var in ['LC_CTYPE', '_']:
    continue
  print(var + '=' + os.environ[var])
_EOF
EOF
    chmod -v 755 /etc/systemd/user-environment-generators/50-profile.sh
}

# ---------- certificados ----------
p_libtasn1() { ./configure --prefix=/usr --disable-static; make; make install; }

p_p11kit() {
    sed '20,$ d' -i trust/trust-extract-compat
    cat >> trust/trust-extract-compat << "EOF"
# Copy existing anchor modifications to /etc/ssl/local
/usr/libexec/make-ca/copy-trust-modifications

# Update trust stores
/usr/sbin/make-ca -r
EOF
    mkdir p11-build && cd p11-build
    meson setup .. --prefix=/usr --buildtype=release -D trust_paths=/etc/pki/anchors
    ninja
    ninja install
    ln -sfv /usr/libexec/p11-kit/trust-extract-compat /usr/bin/update-ca-certificates
    ln -sfv ./pkcs11/p11-kit-trust.so /usr/lib/libnssckbi.so
}

p_makeca() {
    sed '/mktemp/s/-t //' -i make-ca
    make install
    install -vdm755 /etc/ssl/local
    # certdata.txt descarregado no Fedora (o chroot não precisa de ir à net para isto)
    /usr/sbin/make-ca -C /sources/blfs/certdata.txt
    systemctl enable update-pki.timer
    mkdir -pv /etc/profile.d
    cat > /etc/profile.d/pythoncerts.sh << "EOF"
# Begin /etc/profile.d/pythoncerts.sh
export _PIP_STANDALONE_CERT=/etc/pki/tls/certs/ca-bundle.crt
# End /etc/profile.d/pythoncerts.sh
EOF
    test -s /etc/pki/tls/certs/ca-bundle.crt
}

# ---------- rede ----------
p_libunistring() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/libunistring-1.4.2
    make; make install
}
p_libidn2() { ./configure --prefix=/usr --disable-static; make; make install; }
p_libpsl() {
    mkdir build && cd build
    meson setup --prefix=/usr --buildtype=release
    ninja; ninja install
}
p_curl() {
    ./configure --prefix=/usr --disable-static --with-openssl --with-ca-path=/etc/ssl/certs
    make; make install
}
p_wget() {
    NEW_LINE='#if !defined OPENSSL_NO_SSL3_METHOD '
    NEW_LINE+='&& OPENSSL_VERSION_NUMBER < 0x40000000L'
    sed -i "/SSL3/c $NEW_LINE" src/openssl.c
    unset NEW_LINE
    ./configure --prefix=/usr --sysconfdir=/etc --with-ssl=openssl
    make; make install
}
p_git() {
    ./configure --prefix=/usr --with-gitconfig=/etc/gitconfig --with-python=python3 --with-libpcre2
    # o Rust só chega na fase B; o git ainda o trata como opcional
    make NO_RUST=1
    make NO_RUST=1 perllibdir=/usr/lib/perl5/5.44/site_perl install
}

# ---------- sudo e SSH ----------
p_sudo() {
    sed -e 's/\([->.a-zA-Z_]*\)->length/ASN1_STRING_length(\1)/' -i lib/iolog/hostcheck.c
    ./configure --prefix=/usr --libexecdir=/usr/lib --with-secure-path --with-env-editor \
                --docdir=/usr/share/doc/sudo-1.9.17p2 \
                --with-passprompt="[sudo] password for %p: "
    make; make install
    cat > /etc/sudoers.d/00-sudo << "EOF"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL) ALL
EOF
    cat > /etc/pam.d/sudo << "EOF"
# Begin /etc/pam.d/sudo
auth      include     system-auth
account   include     system-account
session   required    pam_env.so
session   include     system-session
# End /etc/pam.d/sudo
EOF
    chmod 644 /etc/pam.d/sudo
}

p_openssh() {
    install -v -g sys -m700 -d /var/lib/sshd
    getent group sshd  >/dev/null || groupadd -g 50 sshd
    getent passwd sshd >/dev/null || useradd -c 'sshd PrivSep' -d /var/lib/sshd -g sshd -s /bin/false -u 50 sshd
    ./configure --prefix=/usr --sysconfdir=/etc/ssh --with-privsep-path=/var/lib/sshd \
                --with-default-path=/usr/bin --with-superuser-path=/usr/sbin:/usr/bin \
                --with-pid-dir=/run
    make
    make install
    install -v -m755 contrib/ssh-copy-id /usr/bin
    install -v -m644 contrib/ssh-copy-id.1 /usr/share/man/man1
    sed 's@d/login@d/sshd@g' /etc/pam.d/login > /etc/pam.d/sshd
    chmod 644 /etc/pam.d/sshd
    grep -q '^UsePAM yes' /etc/ssh/sshd_config || echo "UsePAM yes" >> /etc/ssh/sshd_config
}

p_units() {
    make install-sshd
    systemctl enable sshd
}

s_sshkey() {
    # chave do projeto (vm/nexora_ed25519 no Fedora) para entrar por SSH como root, só com chave
    install -dm700 /root/.ssh
    install -m600 /sources/blfs/authorized_keys /root/.ssh/authorized_keys
}

T0=$SECONDS
pkg A.01-linux-pam   $B/Linux-PAM-1.7.2.tar.xz              p_pam
pkg A.02-shadow      $B/shadow-4.20.2.tar.xz                p_shadow
pkg A.03-systemd     $B/systemd-261.2.tar.gz                p_systemd
pkg A.04-libtasn1    $B/libtasn1-4.21.0.tar.gz              p_libtasn1
pkg A.05-p11-kit     $B/p11-kit-0.26.5.tar.xz               p_p11kit
pkg A.06-make-ca     $B/make-ca-1.16.1.tar.gz               p_makeca
pkg A.07-libunistring $B/libunistring-1.4.2.tar.xz          p_libunistring
pkg A.08-libidn2     $B/libidn2-2.3.8.tar.gz                p_libidn2
pkg A.09-libpsl      $B/libpsl-0.23.3.tar.gz                p_libpsl
pkg A.10-curl        $B/curl-8.21.0.tar.xz                  p_curl
pkg A.11-wget        $B/wget-1.25.0.tar.gz                  p_wget
pkg A.12-git         $B/git-2.55.0.tar.xz                   p_git
pkg A.13-sudo        $B/sudo-1.9.17p2.tar.gz                p_sudo
pkg A.14-openssh     $B/openssh-10.5p1.tar.gz               p_openssh
pkg A.15-sshd-unit   $B/blfs-systemd-units-20251204.tar.xz  p_units
step A.16-sshkey     s_sshkey
echo "🎉 BLFS fase A completa em $(( (SECONDS - T0) / 60 )) min"
