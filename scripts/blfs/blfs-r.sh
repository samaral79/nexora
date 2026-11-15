#!/bin/bash
# Fase R (dentro do chroot, como root): a Nexora para jogar, com peças do CachyOS e da Valve.
#   kernel do CachyOS 7.3 (fonte assinada pelo CachyOS) + escalonador BORE, perfil de jogo
#   (1000 Hz, preempção total, -O3, NTSYNC), afinações do CachyOS-Settings (sysctl, udev, limites),
#   GameMode da Feral, regras udev da Valve para comandos/VR e "game-performance".
#   O Steam, Heroic, Lutris, MangoHud e Gamescope instalam-se por Flatpak (Definições → Gaming):
#   trazem o seu próprio Mesa de 32 bits, coisa que a Nexora (64 bits puro) não tem.
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
F=$N/flow
CACHY=cachyos-7.3.4-1

cbuild() {
    mkdir nx-build && cd nx-build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -G Ninja "$@" ..
    ninja
    ninja install
}
mbuild() {
    mkdir nx-build && cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}

# ---------------------------------------------------------------- kernel
p_kernel() {
    patch -Np1 -i $SRC/$B/bore-cachy-7.3.patch
    make mrproper
    # parte da config da Nexora (fase Q) e junta o perfil de jogo do CachyOS
    cp -v /boot/config-7.1.8 .config
    source $N/kernel-extra.sh
    kcfg_extra
    kcfg_gaming
    make olddefconfig
    kcfg_check
    kcfg_gaming_check
    local kver
    kver=$(make -s kernelrelease)
    [ "$kver" = 7.3.4-nexora ]
    make
    rm -rf /usr/lib/modules/$kver
    make modules_install
    cp -v arch/x86/boot/bzImage /boot/vmlinuz-$kver
    cp -v System.map /boot/System.map-${kver%-nexora}
    cp -v .config /boot/config-${kver%-nexora}
}

s_grub() {
    # lfs.img: o kernel novo por omissão, o 7.1.8 fica como alternativa (o instalador e a ISO
    # escolhem sozinhos o mais recente)
    local root new old
    root=$(blkid -s PARTUUID -o value "$(blkid -L lfs-root)")
    [ -n "$root" ]
    new=$(cd /boot && ls vmlinuz-*-nexora | sort -V | tail -1)
    old=$(cd /boot && ls vmlinuz-*-nexora | sort -V | grep -vx "$new" | tail -1)
    cat > /boot/grub/grub.cfg << EOF
# Begin /boot/grub/grub.cfg
set default=0
set timeout=3

insmod part_gpt
insmod ext2
insmod all_video
search --no-floppy --label lfs-root --set=root
set gfxpayload=keep

menuentry "Nexora Linux 13.1 (${new#vmlinuz-})" {
        linux   /boot/$new root=PARTUUID=$root ro quiet loglevel=3 console=ttyS0,115200 console=tty0
}
menuentry "Nexora Linux 13.1 (${new#vmlinuz-}, modo de recuperação)" {
        linux   /boot/$new root=PARTUUID=$root ro console=ttyS0,115200 console=tty0 systemd.unit=rescue.target
}
EOF
    [ -n "$old" ] && cat >> /boot/grub/grub.cfg << EOF
menuentry "Nexora Linux 13.1 (${old#vmlinuz-}, kernel anterior)" {
        linux   /boot/$old root=PARTUUID=$root ro quiet loglevel=3 console=ttyS0,115200 console=tty0
}
EOF
    echo "# End /boot/grub/grub.cfg" >> /boot/grub/grub.cfg
    cat /boot/grub/grub.cfg
}

# ---------------------------------------------------------------- afinações do CachyOS-Settings
s_cachyset() {
    local d=/tmp/cachyos-settings
    rm -rf $d && mkdir -p $d
    tar -xf $SRC/$B/cachyos-settings-master.tar.gz -C $d --strip-components=1
    cd $d
    # sysctl (swappiness: o zram da Nexora já põe 150 quando está ativo)
    install -vDm644 usr/lib/sysctl.d/70-cachyos-settings.conf /usr/lib/sysctl.d/70-cachyos-settings.conf
    # limites (muitos ficheiros abertos: esync/fsync do Proton), tempos de paragem, journal pequeno
    install -vDm644 usr/lib/systemd/system.conf.d/10-limits.conf /usr/lib/systemd/system.conf.d/10-limits.conf
    install -vDm644 usr/lib/systemd/user.conf.d/10-limits.conf /usr/lib/systemd/user.conf.d/10-limits.conf
    install -vDm644 usr/lib/systemd/system.conf.d/00-timeout.conf /usr/lib/systemd/system.conf.d/00-timeout.conf
    install -vDm644 usr/lib/systemd/user.conf.d/00-timeout.conf /usr/lib/systemd/user.conf.d/00-timeout.conf
    install -vDm644 usr/lib/systemd/journald.conf.d/00-journal-size.conf /usr/lib/systemd/journald.conf.d/00-journal-size.conf
    install -vDm644 etc/security/limits.d/20-audio.conf /etc/security/limits.d/20-audio.conf
    # módulos: NTSYNC no arranque; amdgpu também para as Radeon antigas (GCN 1/2)
    install -vDm644 usr/lib/modules-load.d/ntsync.conf /usr/lib/modules-load.d/ntsync.conf
    install -vDm644 usr/lib/modprobe.d/amdgpu.conf /usr/lib/modprobe.d/amdgpu.conf
    # páginas grandes transparentes com desfragmentação diferida
    install -vDm644 usr/lib/tmpfiles.d/thp.conf /usr/lib/tmpfiles.d/thp.conf
    install -vDm644 usr/lib/tmpfiles.d/thp-shrinker.conf /usr/lib/tmpfiles.d/thp-shrinker.conf
    # udev: escalonadores de disco, temporizadores para áudio, latência, SATA, zram, energia do áudio
    for r in 20-audio-pm 30-zram 40-hpet-permissions 50-sata 60-ioschedulers 99-cpu-dma-latency; do
        install -vDm644 usr/lib/udev/rules.d/$r.rules /usr/lib/udev/rules.d/$r.rules
    done
    install -vDm755 usr/lib/udev/audio-pm-ctl /usr/lib/udev/audio-pm-ctl
    # game-performance: "game-performance %command%" no Steam põe o PC em modo desempenho a jogar
    install -vDm755 usr/bin/game-performance /usr/bin/game-performance
    install -vDm755 usr/bin/zink-run /usr/bin/zink-run
    install -vDm644 LICENSE.md /usr/share/licenses/cachyos-settings/LICENSE.md
    # muitos jogos (e o Proton) precisam de mais mapas de memória do que o kernel deixa (SteamOS/Fedora)
    cat > /usr/lib/sysctl.d/80-nexora-gaming.conf << "EOF"
vm.max_map_count = 2147483642
EOF
    cd / && rm -rf $d
}

# ---------------------------------------------------------------- GameMode, comandos
p_gamemode() {
    mkdir nx-build && cd nx-build
    meson setup .. --prefix=/usr --buildtype=release -D with-examples=false \
          -D with-privileged-group=wheel -D with-systemd-group=false -D with-pam-renicing=true
    ninja
    ninja install
}

p_steamdev() {
    # regras da Valve: comandos do Steam, Steam Deck, DualSense, Switch, VR... (para o Steam Input)
    install -vDm644 60-steam-input.rules /usr/lib/udev/rules.d/60-steam-input.rules
    install -vDm644 60-steam-vr.rules /usr/lib/udev/rules.d/60-steam-vr.rules
    install -vDm644 LICENSE /usr/share/licenses/steam-devices/LICENSE
}

# ---------------------------------------------------------------- gráficas a sério
# Até aqui o Mesa da Nexora só tinha drivers por software (llvmpipe/virgl): bom na VM, sem
# aceleração num PC real. Agora: LLVM com o alvo AMDGPU + clang, SPIR-V, Vulkan, VA-API e o Mesa
# com radeonsi/iris/nouveau/zink + Vulkan para AMD (RADV) e Intel (ANV).
p_llvm() {
    patch -Np1 -i $SRC/$B/llvm-22.1.8-upstream_fix-1.patch
    grep -rl '#!.*python$' | xargs sed -i '1s/python$/python3/'
    sed 's/utility/tool/' -i llvm/utils/FileCheck/CMakeLists.txt
    mkdir -v llvm/build && cd llvm/build
    CC=gcc CXX=g++ cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_SKIP_INSTALL_RPATH=ON -D LLVM_ENABLE_FFI=ON \
        -D CMAKE_BUILD_TYPE=Release -D LLVM_BUILD_LLVM_DYLIB=ON \
        -D LLVM_LINK_LLVM_DYLIB=ON -D LLVM_ENABLE_RTTI=ON \
        -D LLVM_TARGETS_TO_BUILD="host;AMDGPU" -D LLVM_ENABLE_PROJECTS=clang \
        -D CLANG_CONFIG_FILE_SYSTEM_DIR=/etc/clang -D LLVM_BINUTILS_INCDIR=/usr/include \
        -D LLVM_INCLUDE_BENCHMARKS=OFF -D LLVM_INCLUDE_TESTS=OFF -D CLANG_INCLUDE_TESTS=OFF \
        -D LLVM_INCLUDE_EXAMPLES=OFF -D LLVM_PARALLEL_LINK_JOBS=2 \
        -W no-author -G Ninja ..
    # C++ pesado: cada processo come 1-2 GB (com -j8 o OOM do Fedora matou o build)
    ninja -j${NX_LLVM_JOBS:-5}
    ninja install
    mkdir -pv /etc/clang
    for i in clang clang++; do echo -fstack-protector-strong > /etc/clang/$i.cfg; done
    llc --version | grep -q amdgcn
}
p_spvheaders() { cbuild; }
p_spvtools() {
    cbuild -D SPIRV_WERROR=OFF -D BUILD_SHARED_LIBS=ON -D SPIRV_TOOLS_BUILD_STATIC=OFF \
           -D SPIRV-Headers_SOURCE_DIR=/usr
}
p_spvllvm() {
    cbuild -D BUILD_SHARED_LIBS=ON -D CMAKE_SKIP_INSTALL_RPATH=ON \
           -D LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=/usr
}
p_libclc() {
    mkdir libclc/build && cd libclc/build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -G Ninja ..
    ninja
    ninja install
}
p_glslang() {
    cbuild -D ALLOW_EXTERNAL_SPIRV_TOOLS=ON -D BUILD_SHARED_LIBS=ON -D GLSLANG_TESTS=OFF
}
p_vkloader() { cbuild -D CMAKE_SKIP_INSTALL_RPATH=ON; }
p_libva() { mbuild; }
p_mesa() {
    mbuild -D platforms=x11,wayland \
           -D gallium-drivers=radeonsi,r300,r600,nouveau,iris,crocus,i915,svga,zink,virgl,llvmpipe,softpipe \
           -D vulkan-drivers=amd,intel,intel_hasvk,virtio,swrast \
           -D vulkan-layers=device-select,overlay \
           -D gallium-va=enabled -D video-codecs=all \
           -D valgrind=disabled -D libunwind=disabled
    ls /usr/lib/dri/radeonsi_dri.so /usr/lib/dri/iris_dri.so /usr/share/vulkan/icd.d/radeon_icd.x86_64.json \
       /usr/share/vulkan/icd.d/intel_icd.x86_64.json /usr/lib/dri/radeonsi_drv_video.so
}

# ---------------------------------------------------------------- apps X11 no Nexora Flow
p_satellite() {
    # o niri arranca-o sozinho quando uma app X11 abre (Steam, jogos, Wine...) e põe o DISPLAY
    export PATH=/opt/rustc/bin:$PATH CARGO_HOME=/sources/cargo-home
    cargo build --release --locked
    install -vm755 target/release/xwayland-satellite /usr/bin/xwayland-satellite
}

s_flow() {
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    install -vm755 $F/bin/nexora-flow-start /usr/bin/nexora-flow-start
    # o system-helper do Flatpak usa este utilizador para o revokefs (instalações sem cópias extra)
    getent passwd flatpak >/dev/null || useradd -r -U -d / -s /usr/sbin/nologin -c "Flatpak system helper" flatpak
    python3 -c "import ast; ast.parse(open('/usr/bin/nexora-settings').read())"
}

T0=$SECONDS
pkg  R.01-kernel        $B/$CACHY.tar.gz                       p_kernel
step R.02-grub          s_grub
step R.03-cachyos-set   s_cachyset
pkg  R.04-gamemode      $B/gamemode-1.8.2.tar.xz               p_gamemode
pkg  R.05-steam-devices $B/steam-devices-master.tar.gz         p_steamdev
step R.06-flow          s_flow
pkg  R.07-llvm-clang    $B/llvm-project-22.1.8.src.tar.xz      p_llvm
pkg  R.08-spirv-headers $B/SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz p_spvheaders
pkg  R.09-spirv-tools   $B/SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz   p_spvtools
pkg  R.10-spirv-llvm    $B/SPIRV-LLVM-Translator-22.1.5.tar.gz p_spvllvm
pkg  R.11-libclc        $B/llvm-project-22.1.8.src.tar.xz      p_libclc
pkg  R.12-glslang       $B/glslang-16.5.0.tar.gz               p_glslang
pkg  R.13-vulkan-loader $B/Vulkan-Loader-vulkan-sdk-1.4.357.0.tar.gz p_vkloader
pkg  R.14-libva         $B/libva-2.24.1.tar.gz                 p_libva
pkg  R.15-mesa          $B/mesa-26.1.7.tar.xz                  p_mesa
pkg  R.16-xwl-satellite $B/xwayland-satellite-0.8.3.tar.gz     p_satellite
step R.17-flow          s_flow
echo "🎮 Fase R (jogos) completa em $(( (SECONDS - T0) / 60 )) min"
