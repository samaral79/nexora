#!/bin/bash
# Fase W (dentro do chroot, como root): mais jogo.
#   Microcódigo do CPU: o kernel só o carrega no arranque, a partir do initramfs, e até aqui não
#   ia lá nenhum (o da Intel nem estava instalado). Corrige erros do processador, incluindo os
#   crashes dos Intel de 13.ª/14.ª geração. O initramfs e o UKI juntam-no (mkinitramfs.sh).
#   Limites na sessão gráfica: o lightdm e os serviços do utilizador não passavam pelo
#   pam_limits, por isso o GameMode não podia subir a prioridade do jogo e o PipeWire ficava sem
#   tempo real (o som estala quando o jogo puxa pelo CPU).
#   GameMode a dar prioridade ao jogo e menos trabalho de memória em fundo a meio do jogo.
source "$(dirname "$0")/lib.sh"
B=blfs
UCODE=20261110

p_ucode() {
    # só serve para o initramfs (sem carregamento tardio no kernel); fora da imagem squashfs
    install -dm755 /usr/lib/firmware/intel-ucode
    install -m644 intel-ucode/* intel-ucode-with-caveats/* /usr/lib/firmware/intel-ucode/
    install -vDm644 license /usr/share/licenses/intel-ucode/LICENSE
    ls /usr/lib/firmware/intel-ucode/06-b7-01 /usr/lib/firmware/amd-ucode/microcode_amd_fam19h.bin
}

s_gaming() {
    # pam_limits nas sessões gráficas e nos serviços do utilizador (PipeWire corre no user@)
    local f
    for f in lightdm lightdm-autologin systemd-user; do
        [ -f /etc/pam.d/$f ] || continue
        grep -q pam_limits.so /etc/pam.d/$f && continue
        sed -i '0,/^session/s//session   required pam_limits.so\nsession/' /etc/pam.d/$f
        grep -q '^session   required pam_limits.so' /etc/pam.d/$f
    done

    # GameMode: o jogo fica com nice -10 (o grupo wheel tem licença em limits.d/10-gamemode.conf);
    # o resto fica nos valores do GameMode (governador "performance", E/S à frente, sem protetor)
    install -dm755 /usr/share/gamemode
    cat > /usr/share/gamemode/gamemode.ini << "EOF"
; Nexora: valores do sistema. Para mudar, copia para ~/.config/gamemode.ini
[general]
renice=10
ioprio=0
inhibit_screensaver=1
desiredgov=performance
EOF

    # memória: sem compactação proativa nem o "boost" do kswapd, que deita fora a cache de
    # ficheiros depois de uma alocação grande (o jogo volta a ler as texturas do disco)
    cat > /usr/lib/sysctl.d/81-nexora-gaming-mem.conf << "EOF"
vm.compaction_proactiveness = 0
vm.watermark_boost_factor = 0
EOF
}

T0=$SECONDS
pkg  W.01-ucode          $B/Intel-Linux-Processor-Microcode-Data-Files-microcode-$UCODE.tar.gz p_ucode
step W.02-gaming         s_gaming
echo "🎮 Fase W (mais jogo) completa em $(( (SECONDS - T0) / 60 )) min"
