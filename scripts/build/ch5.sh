#!/bin/bash
# LFS 13.1, capítulo 5: toolchain cruzada (a correr como lfs)
source "$(dirname "$0")/lib.sh"

binutils_pass1() {
    mkdir -v build && cd build
    ../configure --prefix=$LFS/tools \
                 --with-sysroot=$LFS \
                 --target=$LFS_TGT   \
                 --disable-nls       \
                 --enable-gprofng=no \
                 --disable-werror    \
                 --enable-new-dtags  \
                 --enable-default-hash-style=gnu
    make
    make install
}

gcc_pass1() {
    tar -xf ../mpfr-4.2.2.tar.xz && mv -v mpfr-4.2.2 mpfr
    tar -xf ../gmp-6.3.0.tar.xz  && mv -v gmp-6.3.0 gmp
    tar -xf ../mpc-1.4.1.tar.xz  && mv -v mpc-1.4.1 mpc
    case $(uname -m) in
      x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac
    mkdir -v build && cd build
    ../configure                  \
        --target=$LFS_TGT         \
        --prefix=$LFS/tools       \
        --with-glibc-version=2.44 \
        --with-sysroot=$LFS       \
        --with-newlib             \
        --without-headers         \
        --enable-default-pie      \
        --enable-default-ssp      \
        --disable-fixincludes     \
        --disable-nls             \
        --disable-shared          \
        --disable-multilib        \
        --disable-threads         \
        --disable-libatomic       \
        --disable-libgomp         \
        --disable-libquadmath     \
        --disable-libssp          \
        --disable-libvtv          \
        --disable-libstdcxx       \
        --enable-languages=c,c++
    make
    make install
    cat ../gcc/{limitx,glimits,limity}.h > \
      $($LFS_TGT-gcc -print-file-name=include)/limits.h
}

linux_headers() {
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include $LFS/usr
}

glibc() {
    case $(uname -m) in
        x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
                ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3 ;;
    esac
    patch -Np1 -i ../glibc-fhs-1.patch
    patch -Np1 -i ../glibc-2.44-upstream_fixes-1.patch
    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure                             \
          --prefix=/usr                      \
          --host=$LFS_TGT                    \
          --build=$(../scripts/config.guess) \
          --disable-nscd                     \
          libc_cv_slibdir=/usr/lib           \
          --enable-kernel=5.10
    make
    make DESTDIR=$LFS install
    sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd

    # Sanity check do livro: o toolchain cruzado tem de linkar contra o glibc novo
    echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
    $LFS_TGT-readelf -l a.out | grep ': /lib' | tee /dev/stderr \
        | grep -q 'Requesting program interpreter: /lib64/ld-linux-x86-64.so.2'
    grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
    grep -B3 "^ $LFS/usr/include" dummy.log
    grep 'SEARCH.*/usr/lib' dummy.log | sed 's|; |\n|g'
    grep "/lib.*/libc.so.6 " dummy.log
    grep found dummy.log
    rm -v a.out dummy.log
}

libstdcxx() {
    mkdir -v build && cd build
    ../libstdc++-v3/configure      \
        --host=$LFS_TGT            \
        --build=$(../config.guess) \
        CXX=$LFS_TGT-gcc           \
        --prefix=/usr              \
        --disable-multilib         \
        --disable-nls              \
        --disable-libstdcxx-pch    \
        --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/16.2.0
    make
    make DESTDIR=$LFS install
    rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

T0=$SECONDS
pkg 5.2-binutils-pass1 binutils-2.47.tar.xz   binutils_pass1
pkg 5.3-gcc-pass1      gcc-16.2.0.tar.xz      gcc_pass1
pkg 5.4-linux-headers  linux-7.1.8.tar.xz     linux_headers
pkg 5.5-glibc          glibc-2.44.tar.xz      glibc
pkg 5.6-libstdcxx      gcc-16.2.0.tar.xz      libstdcxx
echo "🎉 Capítulo 5 completo em $(( (SECONDS - T0) / 60 )) min"
