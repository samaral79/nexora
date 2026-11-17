#!/bin/bash
# Fase S (dentro do chroot, como root): os drivers gráficos que faltavam.
#   NVIDIA 620 (módulos abertos, RTX 20 / GTX 16 em diante) com libglvnd, para o driver da
#   NVIDIA e o Mesa viverem lado a lado; NVK (Vulkan livre do Mesa) para as NVIDIA antigas;
#   intel-media-driver (VA-API iHD, Broadwell em diante); vainfo e vulkaninfo para testar.
#   No arranque o nexora-gpu-select.service escolhe nvidia ou nouveau conforme a placa.
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
F=$N/flow
CACHY=cachyos-7.3.4-1
NV=620.70.06

cbuild() {
    mkdir nx-build && cd nx-build
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_INSTALL_LIBDIR=lib -D CMAKE_BUILD_TYPE=Release \
          -G Ninja "$@" ..
    ninja
    ninja install
}
mbuild() {
    mkdir nx-build && cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}
export PATH=/opt/rustc/bin:$PATH CARGO_HOME=/sources/cargo-home

# ---------------------------------------------------------------- GL partilhado (glvnd)
p_glvnd() {
    # o Mesa até aqui trazia o seu próprio libGL/libEGL; com o glvnd cada placa usa o do seu driver
    rm -fv /usr/lib/libGL.so* /usr/lib/libEGL.so* /usr/lib/libGLESv1_CM.so* /usr/lib/libGLESv2.so* \
           /usr/lib/libglapi.so* /usr/lib/pkgconfig/{gl,egl,glesv1_cm,glesv2}.pc
    mbuild -D gles1=true -D headers=true
}
s_bindgen() {
    # o NVK (e o compilador de shaders NAK) são em Rust e o Mesa gera as ligações com o bindgen/cbindgen
    local r=/sources/nx-bindgen
    rm -rf $r
    cargo install --locked --root $r bindgen-cli
    cargo install --locked --root $r cbindgen
    install -vm755 $r/bin/bindgen $r/bin/cbindgen /usr/bin/
    rm -rf $r
    bindgen --version
    cbindgen --version
}
p_mesa() {
    mbuild -D platforms=x11,wayland -D glvnd=enabled \
           -D gallium-drivers=radeonsi,r300,r600,nouveau,iris,crocus,i915,svga,zink,virgl,llvmpipe,softpipe \
           -D vulkan-drivers=amd,intel,intel_hasvk,nouveau,virtio,swrast \
           -D vulkan-layers=device-select,overlay \
           -D gallium-va=enabled -D video-codecs=all \
           -D valgrind=disabled -D libunwind=disabled
    ls /usr/lib/libGLX_mesa.so.0 /usr/lib/libEGL_mesa.so.0 /usr/share/glvnd/egl_vendor.d/50_mesa.json \
       /usr/lib/dri/radeonsi_dri.so /usr/lib/dri/iris_dri.so /usr/lib/dri/radeonsi_drv_video.so \
       /usr/share/vulkan/icd.d/{radeon,intel,nouveau}_icd.x86_64.json
    ldconfig
}

# ---------------------------------------------------------------- Intel: vídeo por hardware
p_gmmlib() { cbuild -D RUN_TEST_SUITE=OFF; }
p_imedia() {
    cbuild -D INSTALL_DRIVER_SYSCONF=OFF -D MEDIA_BUILD_FATAL_WARNINGS=OFF -D ENABLE_NONFREE_KERNELS=ON
    ls /usr/lib/dri/iHD_drv_video.so
}
p_vautils() { mbuild; }
p_vktools() {
    cbuild -D BUILD_CUBE=OFF -D BUILD_ICD=OFF -D BUILD_TESTS=OFF
    command -v vulkaninfo
}

# ---------------------------------------------------------------- NVIDIA
s_nvkmod() {
    # módulos abertos da NVIDIA contra o kernel mais recente da Nexora
    local kver w=/sources/nx-nvidia
    kver=$(cd /boot && ls vmlinuz-*-nexora | sort -V | tail -1); kver=${kver#vmlinuz-}
    rm -rf $w && mkdir -p $w && cd $w
    tar -xf $SRC/$B/$CACHY.tar.gz
    tar -xf $SRC/$B/open-gpu-kernel-modules-$NV.tar.gz
    cd $w/$CACHY
    patch -Np1 -i $SRC/$B/bore-cachy-7.3.patch
    cp -v /boot/config-${kver%-nexora} .config
    make olddefconfig
    [ "$(make -s kernelrelease)" = "$kver" ] || { echo "kernelrelease não bate com $kver"; exit 1; }
    # build completo (não instala nada do kernel): o modpost da NVIDIA precisa do Module.symvers
    # para confirmar símbolos, namespaces e licenças contra o kernel que vai correr
    make
    [ -s Module.symvers ]
    cd $w/open-gpu-kernel-modules-$NV
    make modules SYSSRC=$w/$CACHY SYSOUT=$w/$CACHY
    make modules_install SYSSRC=$w/$CACHY SYSOUT=$w/$CACHY INSTALL_MOD_DIR=kernel/drivers/video/nvidia
    depmod $kver
    for m in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
        modinfo -k $kver $m | grep -E "^(filename|version|vermagic)"
    done
    modinfo -k $kver -F vermagic nvidia | grep -q "^$kver "
    cd /sources && rm -rf $w
}
s_nvuser() {
    local w=/sources/nx-nvrun
    rm -rf $w
    sh $SRC/$B/NVIDIA-Linux-x86_64-$NV.run --extract-only --target $w
    cd $w
    ./nvidia-installer --silent --no-questions --ui=none \
        --no-kernel-modules --no-install-libglvnd --no-install-compat32-libs \
        --no-x-check --no-incompatible-kernel-module-check --no-disable-incompatible-kernel-modules \
        --no-distro-scripts --no-check-for-alternate-installs --no-rpms --no-backup --no-peermem \
        --skip-depmod --systemd --systemd-unit-prefix=/usr/lib/systemd/system \
        --systemd-sleep-prefix=/usr/lib/systemd/system-sleep \
        --x-prefix=/usr --x-module-path=/usr/lib/xorg/modules --x-library-path=/usr/lib \
        --opengl-prefix=/usr --utility-prefix=/usr --documentation-prefix=/usr \
        --application-profile-path=/usr/share/nvidia \
        --log-file-name=/sources/.logs/nvidia-installer.log
    # firmware GSP (o módulo aberto precisa dele); o instalador sem módulos pode não o pôr
    install -vdm755 /usr/lib/firmware/nvidia/$NV
    install -vm644 firmware/*.bin /usr/lib/firmware/nvidia/$NV/
    # placas que este driver suporta com os módulos abertos (o nexora-gpu-select usa esta lista)
    install -vdm755 /usr/share/nexora
    python3 - supported-gpus/supported-gpus.json > /usr/share/nexora/nvidia-open-ids << 'EOF'
import json, sys
chips = json.load(open(sys.argv[1]))["chips"]
ids = {c["devid"].lower().removeprefix("0x") for c in chips
       if "legacybranch" not in c and "kernelopen" in c.get("features", [])}
print("\n".join(sorted(ids)))
EOF
    [ "$(wc -l < /usr/share/nexora/nvidia-open-ids)" -gt 200 ]
    cd /sources && rm -rf $w
    ldconfig
    ls /usr/lib/libGLX_nvidia.so.0 /usr/lib/libEGL_nvidia.so.0 /usr/lib/gbm/nvidia-drm_gbm.so \
       /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/bin/nvidia-smi /usr/bin/nvidia-settings
    [ -e /usr/share/vulkan/icd.d/nvidia_icd.json ] || [ -e /etc/vulkan/icd.d/nvidia_icd.json ]
}
s_gpusel() {
    local G=$F/gpu
    install -vm644 $G/nvidia-nexora.conf /usr/lib/modprobe.d/nvidia-nexora.conf
    install -vm755 $G/nexora-gpu-select /usr/libexec/nexora-gpu-select
    install -vm644 $G/nexora-gpu-select.service /usr/lib/systemd/system/
    install -vDm644 $G/gpu.conf /etc/nexora/gpu.conf
    install -vDm644 $G/50-limit-free-buffer-pool-in-wayland-compositors.json \
        /etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json
    install -vm755 $G/prime-run /usr/bin/prime-run
    # o instalador da NVIDIA às vezes deixa isto; aqui quem decide é o nexora-gpu-select
    rm -fv /etc/modprobe.d/nvidia-installer-disable-nouveau.conf /usr/lib/modprobe.d/nvidia-installer-disable-nouveau.conf
    systemctl enable nexora-gpu-select.service
    # sem placa NVIDIA o nvidia-sleep.sh sai logo, por isso podem ficar ligados em todo o lado
    systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service \
                     nvidia-suspend-then-hibernate.service
}
s_flow() {
    install -vm755 $F/settings/nexora-settings /usr/bin/nexora-settings
    python3 -c "import ast; ast.parse(open('/usr/bin/nexora-settings').read())"
}

T0=$SECONDS
pkg  S.01-libglvnd      $B/libglvnd-v1.7.0.tar.gz              p_glvnd
step S.02-bindgen       s_bindgen
pkg  S.03-mesa          $B/mesa-26.1.7.tar.xz                  p_mesa
pkg  S.04-gmmlib        $B/intel-gmmlib-22.10.2.tar.gz         p_gmmlib
pkg  S.05-intel-media   $B/intel-media-26.3.5.tar.gz           p_imedia
pkg  S.06-libva-utils   $B/libva-utils-2.24.0.tar.gz           p_vautils
pkg  S.07-vulkan-tools  $B/Vulkan-Tools-1.4.357.tar.gz         p_vktools
step S.08-nvidia-kmod   s_nvkmod
step S.09-nvidia        s_nvuser
step S.10-gpu-select    s_gpusel
step S.11-flow          s_flow
echo "🟩 Fase S (drivers NVIDIA e Intel) completa em $(( (SECONDS - T0) / 60 )) min"
