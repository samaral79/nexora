#!/bin/bash
# LFS 13.1, capítulo 8: o sistema final da Nexora (dentro do chroot, como root)
# Testes: só nos pacotes críticos (glibc, binutils, gmp, mpfr), e nunca param o build.
# Personalização da Nexora: locales pt_PT/en_US, fuso Europe/Lisbon, papel A4.
source "$(dirname "$0")/lib.sh"

# ---------- 8.3 – 8.11 ----------
p_manpages() { rm -v man3/crypt*; make -R GIT=false prefix=/usr install; }
p_ianaetc()  { cp -v services protocols /etc; }

p_glibc() {
    patch -Np1 -i ../glibc-fhs-1.patch
    patch -Np1 -i ../glibc-2.44-upstream_fixes-1.patch
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr                   \
                 --disable-werror                \
                 --disable-nscd                  \
                 libc_cv_slibdir=/usr/lib        \
                 --enable-stack-protector=strong \
                 --enable-kernel=5.10
    make
    t make check
    touch /etc/ld.so.conf
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
    make DESTDIR=$PWD/dest install
    install -vm755 dest/usr/lib/*.so.* /usr/lib
    DIR=$(dirname $(gcc -print-libgcc-file-name))
    [ -e $DIR/include/limits.h ]    || mv $DIR/include{-fixed,}/limits.h
    [ -e $DIR/include/syslimits.h ] || mv $DIR/include{-fixed,}/syslimits.h
    rm -rfv $DIR/include-fixed/*
    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

    # Locales da Nexora (+ os que os testes de outros pacotes esperam)
    localedef -i C     -f UTF-8      C.UTF-8
    localedef -i pt_PT -f UTF-8      pt_PT.UTF-8
    localedef -i pt_PT -f ISO-8859-1 pt_PT
    localedef -i pt_BR -f UTF-8      pt_BR.UTF-8
    localedef -i en_US -f UTF-8      en_US.UTF-8
    localedef -i en_US -f ISO-8859-1 en_US
    localedef -i en_GB -f UTF-8      en_GB.UTF-8
    localedef -i de_DE -f UTF-8      de_DE.UTF-8
    localedef -i fr_FR -f UTF-8      fr_FR.UTF-8
    localedef -i es_ES -f UTF-8      es_ES.UTF-8
    localedef -i ja_JP -f UTF-8      ja_JP.UTF-8

    cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

    tar -xf ../../tzdata2026c.tar.gz
    ZONEINFO=/usr/share/zoneinfo
    mkdir -pv $ZONEINFO/{posix,right}
    for tz in etcetera southamerica northamerica europe africa antarctica \
              asia australasia backward; do
        zic -L /dev/null   -d $ZONEINFO       ${tz}
        zic -L /dev/null   -d $ZONEINFO/posix ${tz}
        zic -L leapseconds -d $ZONEINFO/right ${tz}
    done
    cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York
    ln -sfv /usr/share/zoneinfo/Europe/Lisbon /etc/localtime

    cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
    mkdir -pv /etc/ld.so.conf.d
}

p_zlib() { ./configure --prefix=/usr; make; make install; rm -fv /usr/lib/libz.a; }

p_bzip2() {
    patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
    make -f Makefile-libbz2_so
    make clean
    make
    make PREFIX=/usr install
    cp -av libbz2.so.* /usr/lib
    ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
    ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
    cp -v bzip2-shared /usr/bin/bzip2
    for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 $i; done
    rm -fv /usr/lib/libbz2.a
}

p_xz() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz-5.8.3
    make; make install
}
p_lz4()  { make BUILD_STATIC=no PREFIX=/usr; make BUILD_STATIC=no PREFIX=/usr install; }
p_zstd() { make prefix=/usr; make prefix=/usr install; rm -v /usr/lib/libzstd.a; }
p_file() { ./configure --prefix=/usr; make; make install; }

# ---------- 8.12 – 8.21 ----------
p_readline() {
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install
    sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
    sed -e '270a\
     else\
       chars_avail = 1;'      \
        -e '288i\   result = -1;' \
        -i.orig input.c
    ./configure --prefix=/usr --disable-static --with-curses \
                --docdir=/usr/share/doc/readline-8.3
    make SHLIB_LIBS="-lncursesw"
    make install
    install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3
}

p_pcre2() {
    ./configure --prefix=/usr                       \
                --docdir=/usr/share/doc/pcre2-10.47 \
                --enable-unicode                    \
                --enable-jit                        \
                --enable-pcre2-16                   \
                --enable-pcre2-32                   \
                --enable-pcre2grep-libz             \
                --enable-pcre2grep-libbz2           \
                --enable-pcre2test-libreadline      \
                --disable-static
    make; make install
}

p_m4() { ./configure --prefix=/usr; make; make install; }
p_bc() { CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r; make; make install; }

p_flex() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/flex-2.6.4
    make; make install
    ln -sv flex   /usr/bin/lex
    ln -sv flex.1 /usr/share/man/man1/lex.1
}

p_tcl() {
    SRCDIR=$(pwd)
    cd unix
    ./configure --prefix=/usr --mandir=/usr/share/man --disable-rpath
    make
    sed -e "s|$SRCDIR/unix|/usr/lib|" \
        -e "s|$SRCDIR|/usr/include|"  \
        -i tclConfig.sh
    sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.13|/usr/lib/tdbc1.1.13|" \
        -e "s|$SRCDIR/pkgs/tdbc1.1.13/generic|/usr/include|"     \
        -e "s|$SRCDIR/pkgs/tdbc1.1.13/library|/usr/lib/tcl8.6|"  \
        -e "s|$SRCDIR/pkgs/tdbc1.1.13|/usr/include|"             \
        -i pkgs/tdbc1.1.13/tdbcConfig.sh
    sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.7|/usr/lib/itcl4.3.7|" \
        -e "s|$SRCDIR/pkgs/itcl4.3.7/generic|/usr/include|"    \
        -e "s|$SRCDIR/pkgs/itcl4.3.7|/usr/include|"            \
        -i pkgs/itcl4.3.7/itclConfig.sh
    make install
    chmod 644 /usr/lib/libtclstub8.6.a
    chmod -v u+w /usr/lib/libtcl8.6.so
    make install-private-headers
    ln -sfv tclsh8.6 /usr/bin/tclsh
    mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
    cd ..
    tar -xf ../tcl8.6.18-html.tar.gz --strip-components=1
    mkdir -v -p /usr/share/doc/tcl-8.6.18
    cp -v -r ./html/* /usr/share/doc/tcl-8.6.18
}

p_expect() {
    python3 -c 'from pty import spawn; spawn(["echo", "ok"])'   # PTYs têm de funcionar
    patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
    ./configure --prefix=/usr           \
                --with-tcl=/usr/lib     \
                --enable-shared         \
                --disable-rpath         \
                --mandir=/usr/share/man \
                --with-tclinclude=/usr/include
    make; make install
    ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
}

p_dejagnu() {
    mkdir -v build && cd build
    ../configure --prefix=/usr
    makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
    makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
    make install
    install -v -dm755  /usr/share/doc/dejagnu-1.6.3
    install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
}

p_ninja() {
    sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
    python3 configure.py --bootstrap --verbose
    install -vm755 ninja /usr/bin/
    install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
    install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
}

p_pkgconf() {
    tar -xf ../meson-1.12.0.tar.gz
    mkdir build && cd build
    python3 ../meson-1.12.0/meson.py setup --prefix=/usr --buildtype=release ..
    ninja
    ninja install
    mv /usr/share/doc/pkgconf{,-3.0.5}
    ln -sv pkgconf   /usr/bin/pkg-config
    ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
}

# ---------- 8.22 – 8.32: toolchain final ----------
p_binutils() {
    mkdir -v build && cd build
    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-ld=default \
                 --enable-plugins    \
                 --enable-shared     \
                 --disable-werror    \
                 --enable-64-bit-bfd \
                 --enable-new-dtags  \
                 --with-system-zlib  \
                 --with-lib-path=/usr/lib \
                 --enable-default-hash-style=gnu
    make tooldir=/usr
    t make -k check
    echo "=== FAILs:"; grep '^FAIL:' $(find -name '*.log') || true
    make tooldir=/usr install
    rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a /usr/share/doc/gprofng/
}

p_gmp() {
    sed -i '/long long t1;/,+1s/()/(...)/' configure
    ./configure --prefix=/usr --enable-cxx --disable-static --docdir=/usr/share/doc/gmp-6.3.0
    make
    make html
    t make check
    local n; n=$(cat $(find -name '*.log') | grep -c ^PASS || true)
    echo "=== GMP PASS: $n (tem de ser >= 199)"
    [ "$n" -ge 199 ] || { echo "GMP falhou testes críticos"; exit 1; }
    make install
    make install-html
}

p_mpfr() {
    ./configure --prefix=/usr --disable-static --enable-thread-safe \
                --docdir=/usr/share/doc/mpfr-4.2.2
    make
    make html
    t make check
    make install
    make install-html
}

p_mpc() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpc-1.4.1
    make; make html; make install; make install-html
}

p_attr() {
    ./configure --prefix=/usr --disable-static --sysconfdir=/etc \
                --docdir=/usr/share/doc/attr-2.6.0
    make; make install
}
p_acl() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/acl-2.4.0
    make; make install
}
p_libcap() {
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib
    make prefix=/usr lib=lib install
}
p_libxcrypt() {
    sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
    ./configure --prefix=/usr                \
                --enable-hashes=strong,glibc \
                --enable-obsolete-api=no     \
                --disable-static             \
                --disable-failure-tokens
    make; make install
}

p_shadow() {
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
    sed -e 's:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:'                      \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                     \
        -i etc/login.defs
    touch /usr/bin/passwd
    ./configure --sysconfdir=/etc   \
                --disable-static    \
                --with-{b,yes}crypt \
                --without-libbsd    \
                --disable-logind    \
                --with-group-name-max-length=32
    make
    make exec_prefix=/usr install
    make -C man install-man
    pwconv
    grpconv
    mkdir -p /etc/default
    useradd -D --gid 999
    sed -i '/MAIL/s/yes/no/' /etc/default/useradd
    touch /etc/sub{u,g}id
    # A senha de root define-se à mão no fim (passwd root)
}

p_gawk() {
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr
    make
    rm -f /usr/bin/gawk-5.4.1
    make install
    ln -sv gawk.1 /usr/share/man/man1/awk.1
    install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.4.1
}

p_gcc() {
    case $(uname -m) in
      x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac
    mkdir -v build && cd build
    ../configure --prefix=/usr            \
                 LD=ld                    \
                 --enable-languages=c,c++ \
                 --enable-default-pie     \
                 --enable-default-ssp     \
                 --enable-host-pie        \
                 --enable-targets=all     \
                 --disable-multilib       \
                 --disable-bootstrap      \
                 --disable-fixincludes    \
                 --with-system-zlib
    make
    make install
    chown -v -R root:root $(gcc -print-file-name=include){,-fixed} 2>/dev/null || \
        chown -v -R root:root $(gcc -print-file-name=include)
    ln -svr /usr/bin/cpp /usr/lib
    ln -sv gcc.1 /usr/share/man/man1/cc.1
    ln -sfvr $(gcc -print-prog-name=liblto_plugin.so) /usr/lib/bfd-plugins/

    # Sanity check: tem de usar o loader e o libc do sistema final
    echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
    readelf -l a.out | grep ': /lib' | tee /dev/stderr \
        | grep -q 'Requesting program interpreter: /lib64/ld-linux-x86-64.so.2'
    grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
    grep -B4 '^ /usr/include' dummy.log
    grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g'
    grep "/lib.*/libc.so.6 " dummy.log
    grep found dummy.log
    rm -v a.out dummy.log
    mkdir -pv /usr/share/gdb/auto-load/usr/lib
    mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
}

# ---------- 8.33 – 8.60 ----------
p_ncurses() {
    ./configure --prefix=/usr           \
                --mandir=/usr/share/man \
                --with-shared           \
                --without-debug         \
                --without-normal        \
                --with-cxx-shared       \
                --enable-pc-files       \
                --with-pkg-config-libdir=/usr/lib/pkgconfig
    make
    make DESTDIR=$PWD/dest install
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
    cp --remove-destination -av dest/* /
    for lib in ncurses form panel menu ; do
        ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
        ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
    done
    ln -sfv libncursesw.so /usr/lib/libcurses.so
    cp -v -R doc -T /usr/share/doc/ncurses-6.6
}

p_sed() {
    ./configure --prefix=/usr
    make; make html; make install
    install -vDm644 doc/sed.html -t /usr/share/doc/sed-4.10
}
p_psmisc() { ./configure --prefix=/usr; make; make install; }
p_gettext() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext-1.0
    make; make install
    chmod -v 0755 /usr/lib/preloadable_libintl.so
}
p_bison() { ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2; make; make install; }
p_grep() { sed -i "s/echo/#echo/" src/egrep.sh; ./configure --prefix=/usr; make; make install; }
p_bash() {
    ./configure --prefix=/usr             \
                --without-bash-malloc     \
                --with-installed-readline \
                --docdir=/usr/share/doc/bash-5.3
    make; make install
}
p_libtool() { ./configure --prefix=/usr; make; make install; rm -fv /usr/lib/libltdl.a; }
p_gdbm() {
    ./configure --prefix=/usr --disable-static --enable-libgdbm-compat
    make; make install
}
p_gperf() { ./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3; make; make install; }
p_expat() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/expat-2.8.3
    make; make install
    install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.8.3
}
p_inetutils() {
    sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
    ./configure --prefix=/usr        \
                --bindir=/usr/bin    \
                --localstatedir=/var \
                --disable-logger     \
                --disable-whois      \
                --disable-rcp        \
                --disable-rexec      \
                --disable-rlogin     \
                --disable-rsh        \
                --disable-servers
    make; make install
    mv -v /usr/{,s}bin/ifconfig
}
p_less() { ./configure --prefix=/usr --sysconfdir=/etc; make; make install; }

p_perl() {
    export BUILD_ZLIB=False
    export BUILD_BZIP2=0
    sh Configure -des                                          \
                 -D prefix=/usr                                \
                 -D vendorprefix=/usr                          \
                 -D privlib=/usr/lib/perl5/5.44/core_perl      \
                 -D archlib=/usr/lib/perl5/5.44/core_perl      \
                 -D sitelib=/usr/lib/perl5/5.44/site_perl      \
                 -D sitearch=/usr/lib/perl5/5.44/site_perl     \
                 -D vendorlib=/usr/lib/perl5/5.44/vendor_perl  \
                 -D vendorarch=/usr/lib/perl5/5.44/vendor_perl \
                 -D man1dir=/usr/share/man/man1                \
                 -D man3dir=/usr/share/man/man3                \
                 -D pager="/usr/bin/less -isR"                 \
                 -D useshrplib                                 \
                 -D usethreads
    make; make install
}
p_autoconf() { ./configure --prefix=/usr; make; make install; }
p_automake() { ./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1; make; make install; }

p_openssl() {
    ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
    make
    make INSTALL_LIBS= MANSUFFIX=ssl install
    mv -v /usr/share/doc/openssl /usr/share/doc/openssl-4.0.1
    cp -vfr doc/* /usr/share/doc/openssl-4.0.1
}

p_libelf() {
    ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
    make -C lib
    make -C libelf
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm /usr/lib/libelf.a
}

p_libffi() {
    # genérico (não "native"): a Nexora tem de arrancar noutras máquinas/VMs
    ./configure --prefix=/usr --disable-static --without-gcc-arch
    make; make install
}

p_sqlite() {
    python3 -m zipfile -e ../sqlite-doc-3530400.zip .
    ./configure --prefix=/usr     \
                --disable-static  \
                --enable-fts{4,5} \
                CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                          -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                          -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                          -D SQLITE_SECURE_DELETE=1"
    make LDFLAGS.rpath=""
    make install
    cp -v -R sqlite-doc-3530400 -T /usr/share/doc/sqlite-3.53.4
}

p_mpdecimal() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpdecimal-4.0.1
    make; make install
}

p_python() {
    patch -Np1 -i ../Python-3.14.7-openssl_4-1.patch
    ./configure --prefix=/usr          \
                --enable-shared        \
                --with-system-expat    \
                --enable-optimizations \
                --without-static-libpython
    make; make install
    cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
    install -v -dm755 /usr/share/doc/python-3.14.7/html
    tar --strip-components=1 --no-same-owner --no-same-permissions \
        -C /usr/share/doc/python-3.14.7/html \
        -xvf ../python-3.14.7-docs-html.tar.bz2
}

# Pacotes Python: wheel + install
pywheel() {
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
    pip3 install --no-index --find-links dist "$1"
}
p_flitcore()   { pywheel flit_core; }
p_packaging()  { pywheel packaging; }
p_wheel()      { pywheel wheel; }
p_setuptools() { pywheel setuptools; }
p_meson() {
    pywheel meson
    install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
    install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
}

p_kmod() {
    mkdir -p build && cd build
    meson setup --prefix=/usr .. --buildtype=release -D manpages=false
    ninja; ninja install
}

# ---------- 8.61 – 8.82 ----------
p_coreutils() {
    patch -Np1 -i ../coreutils-9.11-i18n-1.patch
    autoreconf -fv
    automake -af
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
    make; make install
    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}
p_diffutils() { ./configure --prefix=/usr; make; make install; }
p_findutils() { ./configure --prefix=/usr --localstatedir=/var/lib/locate; make; make install; }
p_groff() { PAGE=A4 ./configure --prefix=/usr; make -j1; make install; }

p_grub() {
    unset {C,CPP,CXX,LD}FLAGS
    sed 's/--image-base/--nonexist-linker-option/' -i configure
    # BIOS
    ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror
    make; make install
    # UEFI 64-bit
    make clean
    ./configure --prefix=/usr --sysconfdir=/etc --target=x86_64 --with-platform=efi \
                --disable-efiemu --disable-werror
    make; make install
}

p_gzip() { ./configure --prefix=/usr; make; make install; }
p_iproute2() {
    sed -i /ARPD/d Makefile
    rm -fv man/man8/arpd.8
    make NETNS_RUN_DIR=/run/netns
    make SBINDIR=/usr/sbin install
    install -vDm644 COPYING README* -t /usr/share/doc/iproute2-7.1.0
}
p_kbd() {
    patch -Np1 -i ../kbd-2.10.0-backspace-1.patch
    sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
    sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
    ./configure --prefix=/usr --disable-vlock
    make; make install
    cp -R -v docs/doc -T /usr/share/doc/kbd-2.10.0
}
p_libpipeline() { ./configure --prefix=/usr; make; make install; }
p_make()  { ./configure --prefix=/usr; make; make install; }
p_patch() { ./configure --prefix=/usr; make; make install; }
p_tar() {
    patch -Np1 -i ../tar-1.35-acl_fix-1.patch
    FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
    make; make install
    make -C doc install-html docdir=/usr/share/doc/tar-1.35
}
p_texinfo() { ./configure --prefix=/usr; make; make install; make TEXMF=/usr/share/texmf install-tex; }

p_vim() {
    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
    ./configure --prefix=/usr
    make; make install
    ln -sv vim /usr/bin/vi
    for L in /usr/share/man/{,*/}man1/vim.1; do ln -sv vim.1 $(dirname $L)/vi.1; done
    ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.1025
    cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
}

p_markupsafe() { pywheel Markupsafe; }
p_jinja2()     { pywheel Jinja2; }

p_systemd() {
    sed -e 's/GROUP="render"/GROUP="video"/' \
        -e 's/GROUP="sgx", //'               \
        -i rules.d/50-udev-default.rules.in
    mkdir -p build && cd build
    meson setup ..                \
          --prefix=/usr           \
          --buildtype=release     \
          -D default-dnssec=no    \
          -D firstboot=false      \
          -D install-tests=false  \
          -D ldconfig=false       \
          -D sysusers=false       \
          -D rpmmacrosdir=no      \
          -D homed=disabled       \
          -D man=disabled         \
          -D mode=release         \
          -D pamconfdir=no        \
          -D dev-kvm-mode=0660    \
          -D nobody-group=nogroup \
          -D sysupdate=disabled   \
          -D ukify=disabled       \
          -D docdir=/usr/share/doc/systemd-261.2
    ninja
    ninja install
    tar -xf ../../systemd-man-pages-261.2.tar.xz \
        --no-same-owner --strip-components=1     \
        -C /usr/share/man
    systemd-machine-id-setup
    systemctl preset-all
}

p_dbus() {
    mkdir build && cd build
    meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
    ninja; ninja install
    ln -sfv /etc/machine-id /var/lib/dbus
}

p_mandb() {
    ./configure --prefix=/usr                         \
                --docdir=/usr/share/doc/man-db-2.13.1 \
                --sysconfdir=/etc                     \
                --disable-setuid                      \
                --enable-cache-owner=bin              \
                --with-browser=/usr/bin/lynx          \
                --with-vgrind=/usr/bin/vgrind         \
                --with-grap=/usr/bin/grap
    make; make install
}

p_procps() {
    ./configure --prefix=/usr                           \
                --docdir=/usr/share/doc/procps-ng-4.0.7 \
                --disable-static                        \
                --disable-kill                          \
                --enable-watch8bit                      \
                --with-systemd
    make; make install
}

p_utillinux() {
    ./configure --bindir=/usr/bin     \
                --libdir=/usr/lib     \
                --runstatedir=/run    \
                --sbindir=/usr/sbin   \
                --disable-chfn-chsh   \
                --disable-login       \
                --disable-nologin     \
                --disable-su          \
                --disable-setpriv     \
                --disable-runuser     \
                --disable-pylibmount  \
                --disable-liblastlog2 \
                --disable-static      \
                --without-python      \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir=/usr/share/doc/util-linux-2.42.2
    make; make install
}

p_e2fsprogs() {
    mkdir -v build && cd build
    ../configure --prefix=/usr       \
                 --sysconfdir=/etc   \
                 --enable-elf-shlibs \
                 --disable-libblkid  \
                 --disable-libuuid   \
                 --disable-uuidd     \
                 --disable-fsck
    make; make install
    rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
    gunzip -v /usr/share/info/libext2fs.info.gz
    install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
    makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
    install -v -m644 doc/com_err.info /usr/share/info
    install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
}

# ---------- 8.84 – 8.85 ----------
s_strip() {
    save_usrlib="$(cd /usr/lib; ls ld-linux*[^g])
                 libc.so.6
                 libthread_db.so.1
                 libquadmath.so.0.0.0
                 libstdc++.so.6.0.36
                 libitm.so.1.0.0
                 libatomic.so.1.2.0"
    cd /usr/lib
    for LIB in $save_usrlib; do
        objcopy --only-keep-debug --compress-debug-sections=zstd $LIB $LIB.dbg
        cp $LIB /tmp/$LIB
        strip --strip-unneeded /tmp/$LIB
        objcopy --add-gnu-debuglink=$LIB.dbg /tmp/$LIB
        install -vm755 /tmp/$LIB /usr/lib
        rm /tmp/$LIB
    done
    online_usrbin="bash find strip"
    online_usrlib="$(cd /usr/lib; ls libbfd-2.47*.so libsframe.so.*.*.*)
                   libhistory.so.8.3
                   libncursesw.so.6.6
                   libm.so.6
                   libreadline.so.8.3
                   libz.so.1.3.2
                   libzstd.so.1.5.7
                   $(cd /usr/lib; find libnss*.so* -type f)"
    # garantir que todas existem antes de mexer em nada
    for LIB in $online_usrlib; do [ -f /usr/lib/$LIB ] || { echo "falta /usr/lib/$LIB"; exit 1; }; done
    for BIN in $online_usrbin; do
        cp /usr/bin/$BIN /tmp/$BIN
        strip --strip-unneeded /tmp/$BIN
        install -vm755 /tmp/$BIN /usr/bin
        rm /tmp/$BIN
    done
    for LIB in $online_usrlib; do
        cp /usr/lib/$LIB /tmp/$LIB
        strip --strip-unneeded /tmp/$LIB
        install -vm755 /tmp/$LIB /usr/lib
        rm /tmp/$LIB
    done
    for i in $(find /usr/lib -type f -name \*.so* ! -name \*dbg) \
             $(find /usr/lib -type f -name \*.a)                 \
             $(find /usr/{bin,sbin,libexec} -type f); do
        case "$online_usrbin $online_usrlib $save_usrlib" in
            *$(basename $i)* ) ;;
            * ) strip --strip-unneeded $i 2>/dev/null || true ;;
        esac
    done
}

s_cleanup() {
    find /tmp -mindepth 1 -delete
    find /usr/lib /usr/libexec -name \*.la -delete
    find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
    userdel -r tester 2>/dev/null || true
}

# ---------- ordem do livro ----------
T0=$SECONDS
pkg 8.03-man-pages   man-pages-6.18.tar.xz        p_manpages
pkg 8.04-iana-etc    iana-etc-20260805.tar.gz     p_ianaetc
pkg 8.05-glibc       glibc-2.44.tar.xz            p_glibc
pkg 8.06-zlib        zlib-1.3.2.tar.gz            p_zlib
pkg 8.07-bzip2       bzip2-1.0.8.tar.gz           p_bzip2
pkg 8.08-xz          xz-5.8.3.tar.xz              p_xz
pkg 8.09-lz4         lz4-1.10.0.tar.gz            p_lz4
pkg 8.10-zstd        zstd-1.5.7.tar.gz            p_zstd
pkg 8.11-file        file-5.48.tar.gz             p_file
pkg 8.12-readline    readline-8.3.tar.gz          p_readline
pkg 8.13-pcre2       pcre2-10.47.tar.bz2          p_pcre2
pkg 8.14-m4          m4-1.4.21.tar.xz             p_m4
pkg 8.15-bc          bc-7.0.3.tar.xz              p_bc
pkg 8.16-flex        flex-2.6.4.tar.gz            p_flex
pkg 8.17-tcl         tcl8.6.18-src.tar.gz         p_tcl
pkg 8.18-expect      expect5.45.4.tar.gz          p_expect
pkg 8.19-dejagnu     dejagnu-1.6.3.tar.gz         p_dejagnu
pkg 8.20-ninja       ninja-1.13.2.tar.gz          p_ninja
pkg 8.21-pkgconf     pkgconf-3.0.5.tar.xz         p_pkgconf
pkg 8.22-binutils    binutils-2.47.tar.xz         p_binutils
pkg 8.23-gmp         gmp-6.3.0.tar.xz             p_gmp
pkg 8.24-mpfr        mpfr-4.2.2.tar.xz            p_mpfr
pkg 8.25-mpc         mpc-1.4.1.tar.xz             p_mpc
pkg 8.26-attr        attr-2.6.0.tar.gz            p_attr
pkg 8.27-acl         acl-2.4.0.tar.xz             p_acl
pkg 8.28-libcap      libcap-2.78.tar.xz           p_libcap
pkg 8.29-libxcrypt   libxcrypt-4.5.2.tar.xz       p_libxcrypt
pkg 8.30-shadow      shadow-4.20.2.tar.xz         p_shadow
pkg 8.31-gawk        gawk-5.4.1.tar.xz            p_gawk
pkg 8.32-gcc         gcc-16.2.0.tar.xz            p_gcc
pkg 8.33-ncurses     ncurses-6.6.tar.gz           p_ncurses
pkg 8.34-sed         sed-4.10.tar.xz              p_sed
pkg 8.35-psmisc      psmisc-23.7.tar.xz           p_psmisc
pkg 8.36-gettext     gettext-1.0.tar.xz           p_gettext
pkg 8.37-bison       bison-3.8.2.tar.xz           p_bison
pkg 8.38-grep        grep-3.12.tar.xz             p_grep
pkg 8.39-bash        bash-5.3.tar.gz              p_bash
pkg 8.40-libtool     libtool-2.6.2.tar.xz         p_libtool
pkg 8.41-gdbm        gdbm-1.26.tar.gz             p_gdbm
pkg 8.42-gperf       gperf-3.3.tar.gz             p_gperf
pkg 8.43-expat       expat-2.8.3.tar.xz           p_expat
pkg 8.44-inetutils   inetutils-2.8.tar.gz         p_inetutils
pkg 8.45-less        less-704.tar.gz              p_less
pkg 8.46-perl        perl-5.44.0.tar.xz           p_perl
pkg 8.47-autoconf    autoconf-2.73.tar.xz         p_autoconf
pkg 8.48-automake    automake-1.18.1.tar.xz       p_automake
pkg 8.49-openssl     openssl-4.0.1.tar.gz         p_openssl
pkg 8.50-libelf      elfutils-0.195.tar.bz2       p_libelf
pkg 8.51-libffi      libffi-3.8.0.tar.gz          p_libffi
pkg 8.52-sqlite      sqlite-autoconf-3530400.tar.gz p_sqlite
pkg 8.53-mpdecimal   mpdecimal-4.0.1.tar.gz       p_mpdecimal
pkg 8.54-python      Python-3.14.7.tar.xz         p_python
pkg 8.55-flit-core   flit_core-4.0.2.tar.gz       p_flitcore
pkg 8.56-packaging   packaging-26.3.tar.gz        p_packaging
pkg 8.57-wheel       wheel-0.48.0.tar.gz          p_wheel
pkg 8.58-setuptools  setuptools-84.0.0.tar.gz     p_setuptools
pkg 8.59-meson       meson-1.12.0.tar.gz          p_meson
pkg 8.60-kmod        kmod-34.2.tar.xz             p_kmod
pkg 8.61-coreutils   coreutils-9.11.tar.xz        p_coreutils
pkg 8.62-diffutils   diffutils-3.12.tar.xz        p_diffutils
pkg 8.63-findutils   findutils-4.11.0.tar.xz      p_findutils
pkg 8.64-groff       groff-1.24.1.tar.gz          p_groff
pkg 8.65-grub        grub-2.14.tar.xz             p_grub
pkg 8.66-gzip        gzip-1.14.tar.xz             p_gzip
pkg 8.67-iproute2    iproute2-7.1.0.tar.xz        p_iproute2
pkg 8.68-kbd         kbd-2.10.0.tar.xz            p_kbd
pkg 8.69-libpipeline libpipeline-1.5.8.tar.gz     p_libpipeline
pkg 8.70-make        make-4.4.1.tar.gz            p_make
pkg 8.71-patch       patch-2.8.tar.xz             p_patch
pkg 8.72-tar         tar-1.35.tar.xz              p_tar
pkg 8.73-texinfo     texinfo-7.3.tar.xz           p_texinfo
pkg 8.74-vim         vim-9.2.1025.tar.gz          p_vim
pkg 8.75-markupsafe  markupsafe-3.0.3.tar.gz      p_markupsafe
pkg 8.76-jinja2      jinja2-3.1.6.tar.gz          p_jinja2
pkg 8.77-systemd     systemd-261.2.tar.gz         p_systemd
pkg 8.78-dbus        dbus-1.16.2.tar.xz           p_dbus
pkg 8.79-man-db      man-db-2.13.1.tar.xz         p_mandb
pkg 8.80-procps-ng   procps-ng-4.0.7.tar.xz       p_procps
pkg 8.81-util-linux  util-linux-2.42.2.tar.xz     p_utillinux
pkg 8.82-e2fsprogs   e2fsprogs-1.47.4.tar.gz      p_e2fsprogs
step 8.84-strip      s_strip
step 8.85-cleanup    s_cleanup
echo "🎉 Capítulo 8 completo em $(( (SECONDS - T0) / 60 )) min"
