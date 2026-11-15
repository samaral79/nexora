#!/bin/bash
# Fase Q (dentro do chroot, como root): a Nexora pronta para o dia a dia em hardware real.
#   kernel com portáteis/discos/Bluetooth/webcams/comandos/som SOF, firmware SOF + perfis UCM,
#   Bluetooth (BlueZ), pens e discos no Ficheiros (udisks2 + gvfs: NTFS, exFAT, btrfs, LUKS,
#   telemóveis por MTP), PDFs (Papers), perfis de energia, brilho e teclas multimédia,
#   zram, emojis e ferramentas de terminal (htop, btop, fastfetch, nano, 7zip, completação...).
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
F=$N/flow
KVER=7.1.8

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
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -G Ninja "$@" ..
    ninja
    ninja install
}

# ---------------------------------------------------------------- kernel + firmware de som
p_kernel() {
    make mrproper
    cp -v /boot/config-$KVER .config
    source $N/kernel-extra.sh
    kcfg_extra
    make olddefconfig
    kcfg_check
    make
    rm -rf /usr/lib/modules/$KVER-nexora
    make modules_install
    cp -v arch/x86/boot/bzImage /boot/vmlinuz-$KVER-nexora
    cp -v System.map /boot/System.map-$KVER
    cp -v .config /boot/config-$KVER
}

p_sof() {
    # firmware e topologias do Sound Open Firmware (Intel), sem as ferramentas de debug
    install -dm755 /usr/lib/firmware/intel
    cp -av sof sof-ipc4 sof-ipc4-lib sof-ipc4-tplg sof-tplg sof-ace-tplg /usr/lib/firmware/intel/
    install -vDm644 LICENCE.Intel /usr/share/licenses/sof-firmware/LICENCE.Intel
}
p_ucm() {
    # perfis UCM do ALSA (o PipeWire precisa deles para o som SOF/ACP e muitos USB)
    rm -rf /usr/share/alsa/ucm2
    cp -a ucm2 /usr/share/alsa/
}
p_alsautils() {
    ./configure --disable-alsaconf --disable-bat --disable-xmlto --with-curses=ncursesw
    make
    make install
}

# ---------------------------------------------------------------- Bluetooth
p_libical() {
    mkdir build && cd build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D LIBICAL_STATIC=NO \
          -D LIBICAL_BUILD_DOCS=false -D LIBICAL_BUILD_TESTING=false -D LIBICAL_JAVA_BINDINGS=OFF \
          -D LIBICAL_GLIB_VAPI=false -D LIBICAL_GOBJECT_INTROSPECTION=false ..
    make -j1
    make install
}
p_bluez() {
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
                --enable-library --disable-manpages --disable-cups
    make
    make install
    ln -svf ../libexec/bluetooth/bluetoothd /usr/sbin
    install -v -dm555 /etc/bluetooth
    install -v -m644 src/main.conf /etc/bluetooth/main.conf
    # o adaptador liga-se sozinho no arranque e depois de suspender
    sed -i -e 's/^#\?AutoEnable *=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    grep -q '^AutoEnable=true' /etc/bluetooth/main.conf || sed -i '/^\[Policy\]/a AutoEnable=true' /etc/bluetooth/main.conf
    systemctl enable bluetooth
}

# ---------------------------------------------------------------- sistemas de ficheiros
p_lzo() {
    ./configure --prefix=/usr --enable-shared --disable-static
    make
    make install
}
p_btrfs() {
    ./configure --prefix=/usr --disable-static --disable-documentation --disable-python
    make
    make install
}
p_ntfs3g() {
    # só as ferramentas (mkntfs, ntfsfix, ...); montar é com o driver ntfs3 do kernel
    ./autogen.sh
    ./configure --prefix=/usr --disable-static --with-fuse=internal
    make
    make install
}
p_exfat() {
    ./configure --prefix=/usr
    make
    make install
}

# ---------------------------------------------------------------- discos: LUKS, udisks2, gvfs
p_libaio() {
    sed -i '/install.*libaio.a/s/^/#/' src/Makefile
    make
    make install
}
p_lvm2() {
    PATH+=:/usr/sbin ./configure --prefix=/usr --enable-cmdlib --enable-pkgconfig --enable-udev_sync \
        --with-thin-check= --with-thin-dump= --with-thin-repair= --with-thin-restore= \
        --with-cache-check= --with-cache-dump= --with-cache-repair= --with-cache-restore=
    make
    make install
    make install_systemd_units
}
p_jsonc() {
    mkdir build && cd build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D BUILD_STATIC_LIBS=OFF ..
    make
    make install
}
p_cryptsetup() {
    ./configure --prefix=/usr --disable-ssh-token --disable-asciidoc
    make
    make install
}
p_bytesize() {
    # sem o bscalc (é a única coisa que pede o Pygments)
    ./configure --prefix=/usr --without-tools
    make
    make install
}
p_keyutils() {
    make
    make NO_ARLIB=1 LIBDIR=/usr/lib BINDIR=/usr/bin SBINDIR=/usr/sbin install
}
p_libnvme() { mbuild -D libdbus=auto -D docs=false -D tests=false -D python=disabled; }
p_atasmart() {
    ./configure --prefix=/usr --disable-static
    make
    make install
}
p_blockdev() {
    ./configure --prefix=/usr --sysconfdir=/etc --with-python3 --without-escrow --without-gtk-doc \
                --without-lvm --without-lvm_dbus --without-nvdimm --without-tools --without-smartmontools
    make
    make install
}
p_udisks() {
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static \
                --enable-available-modules --disable-man --disable-gtk-doc
    make
    make install
    # NTFS com o driver do kernel (ntfs3); utilizadores do grupo wheel montam sem senha
    install -dm755 /etc/udisks2
    cat > /etc/udisks2/mount_options.conf << "EOF"
[defaults]
ntfs_drivers=ntfs3,ntfs
ntfs3_defaults=uid=$UID,gid=$GID,windows_names,prealloc
ntfs3_allow=uid=$UID,gid=$GID,umask,dmask,fmask,iocharset,discard,nodiscard,sparse,nosparse,hidden,nohidden,sys_immutable,nosys_immutable,showmeta,noshowmeta,prealloc,noprealloc,hide_dot_files,nohide_dot_files,windows_names,nocase,case
EOF
}
p_gcr4() { mbuild -D gtk_doc=false; }
p_libmtp() {
    ./configure --prefix=/usr --disable-static --with-udev=/usr/lib/udev --disable-doxygen
    make
    make install
}
p_gvfs() {
    mbuild -D onedrive=false -D google=false -D goa=false -D gphoto2=false -D afc=false -D afp=false \
           -D bluray=false -D nfs=false -D smb=false -D dnssd=false -D wsdd=false -D cdda=false \
           -D mtp=true -D man=false
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

# ---------------------------------------------------------------- PDFs (Papers)
p_openjpeg() {
    mkdir -v build && cd build
    cmake -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr -D BUILD_STATIC_LIBS=OFF ..
    make
    make install
}
p_poppler() {
    cbuild -D TESTDATADIR=$PWD/testfiles -D ENABLE_QT5=OFF -D ENABLE_QT6=OFF -D ENABLE_NSS3=OFF \
           -D ENABLE_GPGME=OFF -D ENABLE_BOOST=OFF -D ENABLE_UNSTABLE_API_ABI_HEADERS=ON
    cd ..
    tar -xf $SRC/$B/poppler-data-0.4.12.tar.gz
    make -C poppler-data-0.4.12 prefix=/usr install
}
p_exempi() {
    # só a biblioteca (os testes pedem o Boost)
    ./configure --prefix=/usr --disable-static --enable-unittest=no
    make
    make install
}
p_papers() {
    export CARGO_HOME=/sources/cargo-home
    PATH=/opt/rustc/bin:$PATH mbuild -D documentation=false -D user_doc=false -D tests=false \
          -D file_tests=false -D sysprof=disabled -D djvu=disabled
    glib-compile-schemas /usr/share/glib-2.0/schemas
}

# ---------------------------------------------------------------- energia e teclas
p_ppd() {
    mbuild -D gtk_doc=false -D tests=false -D manpage=disabled -D pylint=disabled -D bashcomp=disabled
    systemctl enable power-profiles-daemon
}
p_brightnessctl() {
    # pelo logind (sem setuid nem regras udev): quem tem a sessão ativa muda o brilho
    make ENABLE_SYSTEMD=1
    make ENABLE_SYSTEMD=1 PREFIX=/usr install
}
p_playerctl() { mbuild -D gtk-doc=false -D introspection=false -D bash-completions=true; }
p_wlclip() { mbuild -D fishcompletiondir=no; }

# ---------------------------------------------------------------- ferramentas
p_zip() {
    make -f unix/Makefile generic CC="gcc -std=gnu89"
    make prefix=/usr MANDIR=/usr/share/man/man1 -f unix/Makefile install
}
p_7zip() {
    sed -i 's/-Werror //g' CPP/7zip/7zip_gcc.mak
    for i in Bundles/{Alone,Alone7z,Format7zF,SFXCon} UI/Console; do
        make -C CPP/7zip/$i -f ../../cmpl_gcc.mak
    done
    install -vDm755 CPP/7zip/Bundles/Alone{/b/g/7za,7z/b/g/7zr} CPP/7zip/Bundles/Format7zF/b/g/7z.so \
                    CPP/7zip/UI/Console/b/g/7z -t /usr/lib/7zip/
    install -vm755 CPP/7zip/Bundles/SFXCon/b/g/7zCon /usr/lib/7zip/7zCon.sfx
    for i in 7z 7za 7zr; do
        printf '#!/bin/sh\nexec /usr/lib/7zip/%s "$@"\n' $i > /usr/bin/$i
        chmod 755 /usr/bin/$i
    done
}
p_nano() {
    ./configure --prefix=/usr --sysconfdir=/etc --enable-utf8
    make
    make install
    # realce de sintaxe e números de linha por omissão
    cat > /etc/nanorc << "EOF"
include "/usr/share/nano/*.nanorc"
set linenumbers
set mouse
set autoindent
set tabsize 4
EOF
}
p_pciutils() {
    sed -r '/INSTALL/{/PCI_IDS|update-pciids /d; s/update-pciids.8//}' -i Makefile
    make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes
    make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes install install-lib
    chmod -v 755 /usr/lib/libpci.so
}
p_usbutils() { mbuild; }
p_userdirs() { mbuild -D docs=false; }
p_tirpc() {
    ./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-gssapi
    make
    make install
}
p_lsof() {
    ./configure --prefix=/usr --disable-static
    make
    make install
}
p_tree() {
    make
    make PREFIX=/usr MANDIR=/usr/share/man install
}
p_htop() {
    ./configure --prefix=/usr --enable-unicode
    make
    make install
}
p_btop() {
    make GPU_SUPPORT=true
    make install PREFIX=/usr
}
p_fastfetch() { cbuild -D BUILD_TESTS=OFF -D BUILD_FLASHFETCH=OFF -D ENABLE_IMAGEMAGICK7=OFF -D ENABLE_IMAGEMAGICK6=OFF; }
p_bashcomp() {
    ./configure --prefix=/usr --sysconfdir=/etc
    make
    make install
}

# ---------------------------------------------------------------- passos sem tarball
s_emoji() {
    install -vDm644 $SRC/$B/NotoColorEmoji-2.051.ttf /usr/share/fonts/noto-emoji/NotoColorEmoji.ttf
    # emojis a cores como recurso de todas as letras (sans, serif e mono)
    cat > /etc/fonts/conf.d/60-nexora-emoji.conf << "EOF"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias><family>sans-serif</family><prefer><family>Inter</family><family>Noto Color Emoji</family></prefer></alias>
  <alias><family>serif</family><prefer><family>DejaVu Serif</family><family>Noto Color Emoji</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>JetBrains Mono</family><family>Noto Color Emoji</family></prefer></alias>
  <alias><family>emoji</family><prefer><family>Noto Color Emoji</family></prefer></alias>
</fontconfig>
EOF
    fc-cache -f
}

s_zram() {
    # swap comprimida em RAM: metade da memória (máx. 8 GB), zstd, prioridade acima de qualquer swap em disco
    cat > /usr/sbin/nexora-zram << "EOF"
#!/bin/sh
# nexora-zram start|stop — swap em zram (Nexora)
case "$1" in
start)
    modprobe zram || exit 0
    mem=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    size=$(( mem / 2 )); [ $size -gt 8388608 ] && size=8388608
    dev=$(zramctl --find --algorithm zstd --size ${size}KiB) || dev=$(zramctl --find --size ${size}KiB) || exit 1
    echo "$dev" > /run/nexora-zram.dev
    mkswap -L zram "$dev" >/dev/null
    swapon --discard --priority 100 "$dev" ;;
stop)
    dev=$(cat /run/nexora-zram.dev 2>/dev/null) || exit 0
    swapoff "$dev" 2>/dev/null
    zramctl --reset "$dev" 2>/dev/null
    echo "${dev#/dev/zram}" > /sys/class/zram-control/hot_remove 2>/dev/null
    rm -f /run/nexora-zram.dev ;;
esac
EOF
    chmod 755 /usr/sbin/nexora-zram
    cat > /usr/lib/systemd/system/nexora-zram.service << "EOF"
[Unit]
Description=Swap comprimida em RAM (zram)
DefaultDependencies=no
Before=swap.target
ConditionPathExists=!/run/nexora-no-zram

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nexora-zram start
ExecStop=/usr/sbin/nexora-zram stop

[Install]
WantedBy=swap.target
EOF
    # a RAM rende mais com zram: troca cedo, sem ler páginas à frente
    cat > /etc/sysctl.d/90-nexora-zram.conf << "EOF"
vm.swappiness = 150
vm.page-cluster = 0
EOF
    systemctl enable nexora-zram
}

s_shell() {
    # completação no bash (só para shells interativas; o /etc/bashrc é lido por todas)
    if ! grep -q bash_completion /etc/bashrc; then
        sed -i '/^# End \/etc\/bashrc/d' /etc/bashrc
        cat >> /etc/bashrc << "EOF2"
[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
# End /etc/bashrc
EOF2
    fi
    # fastfetch com o logótipo da Nexora
    install -vDm644 $F/fastfetch/logo.txt /usr/share/nexora/fastfetch-logo.txt
    install -vDm644 $F/fastfetch/config.jsonc /etc/xdg/fastfetch/config.jsonc
    fastfetch --config /etc/xdg/fastfetch/config.jsonc --pipe > /dev/null
}

s_flow() {
    # app Definições (Bluetooth e Energia), barra/painel rápido e teclas de brilho/multimédia
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    install -vm755 $F/bin/nexora-flow-start $F/bin/nexora-flow-status $F/bin/nexora-flow-power /usr/bin/
    # ícones dos modos de energia em branco para o painel rápido (os simbólicos vêm cinzentos)
    install -dm755 /usr/share/nexora-flow/icons
    for p in balanced power-saver performance; do
        sed 's/color:#444444/color:#ffffff/' \
            /usr/share/icons/Papirus/24x24/symbolic/status/power-profile-$p-symbolic.svg \
            > /usr/share/nexora-flow/icons/power-$p.svg
    done
    install -vm644 $F/eww/eww.yuck $F/eww/eww.scss /usr/share/nexora-flow/eww/
    install -vDm644 $F/niri/config.kdl /etc/niri/config.kdl
    niri validate -c /etc/niri/config.kdl
    # PDFs no Papers
    sed -i 's|^application/pdf=.*|application/pdf=org.gnome.Papers.desktop|' /etc/xdg/mimeapps.list
    grep -q '^application/x-cbz=' /etc/xdg/mimeapps.list || cat >> /etc/xdg/mimeapps.list << "EOF"
application/x-cbz=org.gnome.Papers.desktop
application/x-cbr=org.gnome.Papers.desktop
image/tiff=org.gnome.Papers.desktop
application/vnd.rar=org.gnome.FileRoller.desktop
application/x-rar=org.gnome.FileRoller.desktop
EOF
    update-desktop-database /usr/share/applications
    gtk-update-icon-cache -qtf /usr/share/icons/hicolor
}

T0=$SECONDS
pkg  Q.01-kernel        linux-$KVER.tar.xz                     p_kernel
pkg  Q.02-sof           $B/sof-bin-2026.09.2.tar.gz            p_sof
pkg  Q.03-ucm           $B/alsa-ucm-conf-1.2.16.1.tar.bz2      p_ucm
pkg  Q.04-alsa-utils    $B/alsa-utils-1.2.16.tar.bz2           p_alsautils
pkg  Q.05-libical       $B/libical-4.0.5.tar.gz                p_libical
pkg  Q.06-bluez         $B/bluez-5.87.tar.xz                   p_bluez
pkg  Q.07-lzo           $B/lzo-2.10.tar.gz                     p_lzo
pkg  Q.08-btrfs-progs   $B/btrfs-progs-v7.1.tar.xz             p_btrfs
pkg  Q.09-ntfs-3g       $B/ntfs-3g-2026.7.7.tar.gz             p_ntfs3g
pkg  Q.10-exfatprogs    $B/exfatprogs-1.4.4.tar.gz             p_exfat
pkg  Q.11-libaio        $B/libaio-0.3.113.tar.gz               p_libaio
pkg  Q.12-lvm2          $B/LVM2.2.03.42.tgz                    p_lvm2
pkg  Q.13-json-c        $B/json-c-0.19.tar.gz                  p_jsonc
pkg  Q.14-cryptsetup    $B/cryptsetup-2.8.7.tar.xz             p_cryptsetup
pkg  Q.16-libbytesize   $B/libbytesize-2.12.tar.gz             p_bytesize
pkg  Q.17-keyutils      $B/keyutils-1.6.3.tar.gz               p_keyutils
pkg  Q.18-libnvme       $B/libnvme-1.16.2.tar.gz               p_libnvme
pkg  Q.19-libatasmart   $B/libatasmart-0.19.tar.xz             p_atasmart
pkg  Q.20-libblockdev   $B/libblockdev-3.5.0.tar.gz            p_blockdev
pkg  Q.21-udisks2       $B/udisks-2.11.2.tar.bz2               p_udisks
pkg  Q.22-gcr4          $B/gcr-4.4.0.1.tar.xz                  p_gcr4
pkg  Q.23-libmtp        $B/libmtp-1.1.23.tar.gz                p_libmtp
pkg  Q.24-gvfs          $B/gvfs-1.60.2.tar.xz                  p_gvfs
pkg  Q.25-openjpeg      $B/openjpeg-2.5.4.tar.gz               p_openjpeg
pkg  Q.26-poppler       $B/poppler-26.08.0.tar.xz              p_poppler
pkg  Q.26b-exempi       $B/exempi-2.6.6.tar.xz                 p_exempi
pkg  Q.27-papers        $B/papers-51.1.tar.xz                  p_papers
pkg  Q.28-ppd           $B/power-profiles-daemon-0.30.tar.gz   p_ppd
pkg  Q.29-brightnessctl $B/brightnessctl-0.5.1.tar.gz          p_brightnessctl
pkg  Q.30-playerctl     $B/playerctl-2.4.1.tar.gz              p_playerctl
pkg  Q.31-wl-clipboard  $B/wl-clipboard-2.3.0.tar.gz           p_wlclip
pkg  Q.32-zip           $B/zip30.tar.gz                        p_zip
pkg  Q.33-7zip          $B/7zip-26.02.tar.gz                   p_7zip
pkg  Q.34-nano          $B/nano-9.2.tar.xz                     p_nano
pkg  Q.35-pciutils      $B/pciutils-3.15.0.tar.gz              p_pciutils
pkg  Q.36-usbutils      $B/usbutils-019.tar.xz                 p_usbutils
pkg  Q.37-user-dirs     $B/xdg-user-dirs-v0.20.tar.gz          p_userdirs
pkg  Q.38-libtirpc      $B/libtirpc-1.3.7.tar.bz2              p_tirpc
pkg  Q.39-lsof          $B/lsof-4.99.7.tar.gz                  p_lsof
pkg  Q.40-tree          $B/unix-tree-2.3.2.tar.bz2             p_tree
pkg  Q.41-htop          $B/htop-3.5.3.tar.xz                   p_htop
pkg  Q.42-btop          $B/btop-1.4.8.tar.gz                   p_btop
pkg  Q.43-fastfetch     $B/fastfetch-2.71.0.tar.gz             p_fastfetch
pkg  Q.44-bash-comp     $B/bash-completion-2.18.0.tar.xz       p_bashcomp
step Q.45-emoji         s_emoji
step Q.46-zram          s_zram
step Q.47-shell         s_shell
step Q.48-flow          s_flow
echo "🎉 Fase Q (dia a dia em hardware real) completa em $(( (SECONDS - T0) / 60 )) min"
