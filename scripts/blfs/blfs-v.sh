#!/bin/bash
# Fase V (dentro do chroot, como root): desempenho geral.
#   Kernel: a raiz é uma imagem squashfs, por isso a descompressão passa a usar todos os núcleos
#   e a escrever direto na cache de páginas (antes era um só descompressor para o sistema todo);
#   MGLRU (gestão de memória do Chrome OS/Android, menos engasgos com pouca RAM); schedutil por
#   omissão (o acpi-cpufreq ficava preso no "userspace"); /proc/config.gz. Os módulos abertos da
#   NVIDIA são recompilados na mesma árvore.
#   Sistema: zram fora do caminho crítico do arranque, TRIM semanal dos SSD, systemd-oomd a
#   proteger a sessão quando a memória acaba (como no Fedora), hwdb gerado na imagem, sem os
#   watchdogs de hardware (como no CachyOS) e sem os erros do tmpfiles na raiz só de leitura.
source "$(dirname "$0")/lib.sh"
B=blfs
N=$(dirname "$0")
CACHY=cachyos-7.3.4-1
NV=620.70.06

p_kernel() {
    local kver w=/sources/nx-nvidia
    patch -Np1 -i $SRC/$B/bore-cachy-7.3.patch
    make mrproper
    kver=$(cd /boot && ls vmlinuz-*-nexora | sort -V | tail -1); kver=${kver#vmlinuz-}
    cp -v /boot/config-${kver%-nexora} .config
    source $N/kernel-extra.sh
    kcfg_perf
    make olddefconfig
    kcfg_check
    kcfg_gaming_check
    kcfg_perf_check
    [ "$(make -s kernelrelease)" = "$kver" ] || { echo "kernelrelease não bate com $kver"; exit 1; }
    make
    [ -s Module.symvers ]
    # módulos da NVIDIA contra esta árvore (o modpost precisa do Module.symvers dela)
    rm -rf $w && mkdir -p $w
    tar -xf $SRC/$B/open-gpu-kernel-modules-$NV.tar.gz -C $w
    make -C $w/open-gpu-kernel-modules-$NV modules SYSSRC=$PWD SYSOUT=$PWD
    # só agora se troca o que está instalado
    rm -rf /usr/lib/modules/$kver
    make modules_install
    make -C $w/open-gpu-kernel-modules-$NV modules_install SYSSRC=$PWD SYSOUT=$PWD \
        INSTALL_MOD_DIR=kernel/drivers/video/nvidia
    depmod $kver
    modinfo -k $kver -F vermagic nvidia | grep -q "^$kver "
    cp -v arch/x86/boot/bzImage /boot/vmlinuz-$kver
    cp -v System.map /boot/System.map-${kver%-nexora}
    cp -v .config /boot/config-${kver%-nexora}
    rm -rf $w
}

s_perf() {
    # zram: liga-se em paralelo com o resto do arranque (estava no caminho crítico, ~1,2 s)
    cat > /usr/lib/systemd/system/nexora-zram.service << "EOF"
[Unit]
Description=Swap comprimida em RAM (zram)
DefaultDependencies=no
After=systemd-modules-load.service
Conflicts=shutdown.target
Before=shutdown.target
ConditionPathExists=!/run/nexora-no-zram

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nexora-zram start
ExecStop=/usr/sbin/nexora-zram stop

[Install]
WantedBy=sysinit.target
EOF
    rm -f /etc/systemd/system/swap.target.wants/nexora-zram.service
    systemctl enable nexora-zram

    # TRIM semanal (SSD/NVMe mantêm a velocidade de escrita)
    systemctl enable fstrim.timer

    # systemd-oomd: com a memória esgotada mata a app que a está a comer em vez de congelar o PC
    # (valores do Fedora: pressão de memória acima de 50% durante 20 s, ou swap acima de 90%)
    install -dm755 /usr/lib/systemd/system/-.slice.d /usr/lib/systemd/system/user@.service.d \
        /usr/lib/systemd/oomd.conf.d
    cat > /usr/lib/systemd/system/-.slice.d/10-oomd-root-slice-defaults.conf << "EOF"
[Slice]
ManagedOOMSwap=kill
EOF
    cat > /usr/lib/systemd/system/user@.service.d/10-oomd-user-service-defaults.conf << "EOF"
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=50%
EOF
    cat > /usr/lib/systemd/oomd.conf.d/10-oomd-defaults.conf << "EOF"
[OOM]
DefaultMemoryPressureDurationSec=20s
EOF
    systemctl enable systemd-oomd.service

    # sem watchdogs de hardware: ninguém os usa num PC e acordam o CPU (CachyOS)
    cat > /usr/lib/modprobe.d/nexora-watchdog.conf << "EOF"
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist sp5100_tco
EOF

    # base de dados do hardware dentro da imagem (/usr): não se reconstrói no arranque
    systemd-hwdb update --usr
    rm -f /etc/udev/hwdb.bin
    [ -s /usr/lib/udev/hwdb.bin ]

    # tmpfiles: a raiz é só de leitura e /home, /srv e /root são ligações para /var
    install -dm755 /etc/tmpfiles.d
    : > /etc/tmpfiles.d/root.conf
    : > /etc/tmpfiles.d/home.conf
    grep -vE '^d-\s+/root\s' /usr/lib/tmpfiles.d/provision.conf > /etc/tmpfiles.d/provision.conf
}

T0=$SECONDS
pkg  V.01-kernel         $B/$CACHY.tar.gz                       p_kernel
step V.02-perf           s_perf
echo "⚡ Fase V (desempenho) completa em $(( (SECONDS - T0) / 60 )) min"
