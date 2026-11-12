#!/bin/bash
# LFS 13.1, capítulo 9 (+ 11.1): configuração do sistema da Nexora (dentro do chroot, como root)
# Rede por DHCP (systemd-networkd + resolved), hostname nexora, consola pt-latin1, LANG pt_PT.
source "$(dirname "$0")/lib.sh"

s_network() {
    # DHCP em qualquer placa com fio (en*, que é o nome que o QEMU/virtio dá)
    cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
UseDomains=true
EOF
    # o resolved cria o stub; garantimos o symlink já
    ln -sfv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    # não ficar 2 min à espera de rede no arranque
    systemctl disable systemd-networkd-wait-online || true

    echo nexora > /etc/hostname
    cat > /etc/hosts << "EOF"
# Begin /etc/hosts

127.0.0.1 localhost
127.0.1.1 nexora.localdomain nexora
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF
}

s_console() {
    # relógio da VM em UTC (o default do QEMU); fuso já é Europe/Lisbon desde a glibc
    cat > /etc/adjtime << "EOF"
0.0 0 0.0
0
UTC
EOF
    cat > /etc/vconsole.conf << "EOF"
KEYMAP=pt-latin1
FONT=Lat2-Terminus16
EOF
    LC_ALL=pt_PT.UTF-8 locale charmap | grep -qx UTF-8
    cat > /etc/locale.conf << "EOF"
LANG=pt_PT.UTF-8
EOF
    cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
      export $key
    fi
  done
fi

# End /etc/profile
EOF
}

s_inputrc() {
    cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
"\eOH": beginning-of-line
"\eOF": end-of-line
"\e[H": beginning-of-line
"\e[F": end-of-line
# End /etc/inputrc
EOF
    cat > /etc/shells << "EOF"
# Begin /etc/shells
/bin/sh
/bin/bash
# End /etc/shells
EOF
}

s_systemd() {
    # não limpar o ecrã no tty1 (vê-se o que o arranque disse)
    mkdir -pv /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << EOF
[Service]
TTYVTDisallocate=no
EOF
}

s_release() {
    echo 13.1-systemd > /etc/lfs-release
    cat > /etc/os-release << "EOF"
NAME="Nexora Linux"
VERSION="13.1"
ID=nexora
ID_LIKE=lfs
VERSION_ID=13.1
PRETTY_NAME="Nexora Linux 13.1"
ANSI_COLOR="0;36"
HOME_URL="https://github.com/samaral79"
RELEASE_TYPE="stable"
EOF
    cat > /etc/lsb-release << "EOF"
DISTRIB_ID="Nexora"
DISTRIB_RELEASE="13.1"
DISTRIB_CODENAME="nexora"
DISTRIB_DESCRIPTION="Nexora Linux 13.1"
EOF
    cat > /etc/issue << "EOF"
\e[36mNexora Linux 13.1\e[0m  (\l)  kernel \r

EOF
}

T0=$SECONDS
step 9.2-network  s_network
step 9.6-console  s_console
step 9.8-inputrc  s_inputrc
step 9.10-systemd s_systemd
step 11.1-release s_release
echo "🎉 Capítulo 9 completo em $(( SECONDS - T0 ))s"
