#!/bin/bash
# LFS 13.1, capítulo 6: ferramentas temporárias, compiladas em modo cruzado (a correr como lfs)
source "$(dirname "$0")/lib.sh"

# Configure padrão para pacotes autotools com build-aux/config.guess
std() {
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess) "$@"
    make
    make DESTDIR=$LFS install
}

p_m4() {
    cat > $LFS/usr/share/config.site << EOF
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
    std
}

p_ncurses() {
    mkdir build
    pushd build
      ../configure --prefix=$LFS/tools AWK=gawk
      make -C include
      make -C progs tic
      install progs/tic $LFS/tools/bin
    popd
    ./configure --prefix=/usr                \
                --host=$LFS_TGT              \
                --build=$(./config.guess)    \
                --mandir=/usr/share/man      \
                --with-manpage-format=normal \
                --with-shared                \
                --without-normal             \
                --with-cxx-shared            \
                --without-debug              \
                --without-ada                \
                --disable-stripping          \
                AWK=gawk
    make
    make DESTDIR=$LFS install
    ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $LFS/usr/include/curses.h
}

p_bash() {
    ./configure --prefix=/usr                      \
                --build=$(sh support/config.guess) \
                --host=$LFS_TGT                    \
                --without-bash-malloc              \
                --docdir=/usr/share/doc/bash-5.3
    make
    make DESTDIR=$LFS install
    ln -sv bash $LFS/bin/sh
}

p_coreutils() {
    std --enable-install-program=hostname
    mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
    mkdir -pv $LFS/usr/share/man/man8
    mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
}

p_diffutils() { std gl_cv_func_strcasecmp_works=yes; }

p_file() {
    mkdir build
    pushd build
      ../configure --disable-bzlib      \
                   --disable-libseccomp \
                   --disable-xzlib      \
                   --disable-zlib
      make
    popd
    ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
    make FILE_COMPILE=$(pwd)/build/src/file
    make DESTDIR=$LFS install
    rm -v $LFS/usr/lib/libmagic.la
}

p_findutils() { std --localstatedir=/var/lib/locate; }

p_gawk() {
    sed -i 's/extras//' Makefile.in
    std
}

p_gzip() {
    ./configure --prefix=/usr --host=$LFS_TGT
    make
    make DESTDIR=$LFS install
}

p_xz() {
    std --disable-static --docdir=/usr/share/doc/xz-5.8.3
    rm -v $LFS/usr/lib/liblzma.la
}

p_binutils_pass2() {
    sed '6031s/$add_dir//' -i ltmain.sh
    mkdir -v build && cd build
    ../configure                   \
        --prefix=/usr              \
        --build=$(../config.guess) \
        --host=$LFS_TGT            \
        --disable-nls              \
        --enable-shared            \
        --enable-gprofng=no        \
        --disable-werror           \
        --enable-64-bit-bfd        \
        --enable-new-dtags         \
        --enable-default-hash-style=gnu
    make
    make DESTDIR=$LFS install
    rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

p_gcc_pass2() {
    tar -xf ../mpfr-4.2.2.tar.xz && mv -v mpfr-4.2.2 mpfr
    tar -xf ../gmp-6.3.0.tar.xz  && mv -v gmp-6.3.0 gmp
    tar -xf ../mpc-1.4.1.tar.xz  && mv -v mpc-1.4.1 mpc
    case $(uname -m) in
      x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac
    mkdir -v build && cd build
    ../configure                   \
        --build=$(../config.guess) \
        --host=$LFS_TGT            \
        --target=$LFS_TGT          \
        --prefix=/usr              \
        --with-build-sysroot=$LFS  \
        --enable-default-pie       \
        --enable-default-ssp       \
        --disable-fixincludes      \
        --disable-nls              \
        --disable-multilib         \
        --disable-libatomic        \
        --disable-libgomp          \
        --disable-libquadmath      \
        --disable-libsanitizer     \
        --disable-libssp           \
        --disable-libvtv           \
        --enable-languages=c,c++   \
        CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
        LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc \
        target_configargs=gcc_cv_target_thread_file=posix
    make
    make DESTDIR=$LFS install
    ln -sv gcc $LFS/usr/bin/cc
}

T0=$SECONDS
pkg 6.2-m4             m4-1.4.21.tar.xz        p_m4
pkg 6.3-ncurses        ncurses-6.6.tar.gz      p_ncurses
pkg 6.4-bash           bash-5.3.tar.gz         p_bash
pkg 6.5-coreutils      coreutils-9.11.tar.xz   p_coreutils
pkg 6.6-diffutils      diffutils-3.12.tar.xz   p_diffutils
pkg 6.7-file           file-5.48.tar.gz        p_file
pkg 6.8-findutils      findutils-4.11.0.tar.xz p_findutils
pkg 6.9-gawk           gawk-5.4.1.tar.xz       p_gawk
pkg 6.10-grep          grep-3.12.tar.xz        std
pkg 6.11-gzip          gzip-1.14.tar.xz        p_gzip
pkg 6.12-make          make-4.4.1.tar.gz       std
pkg 6.13-patch         patch-2.8.tar.xz        std
pkg 6.14-sed           sed-4.10.tar.xz         std
pkg 6.15-tar           tar-1.35.tar.xz         std
pkg 6.16-xz            xz-5.8.3.tar.xz         p_xz
pkg 6.17-binutils-pass2 binutils-2.47.tar.xz   p_binutils_pass2
pkg 6.18-gcc-pass2     gcc-16.2.0.tar.xz       p_gcc_pass2
echo "🎉 Capítulo 6 completo em $(( (SECONDS - T0) / 60 )) min"
