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
    # sistema em inglês; teclado continua pt-latin1 e fuso Europe/Lisbon
    LC_ALL=en_US.UTF-8 locale charmap | grep -qx UTF-8
    cat > /etc/locale.conf << "EOF"
LANG=en_US.UTF-8
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
    # o getty limpa o ecrã antes do login (ecrã de login limpo)
    rm -rf /etc/systemd/system/getty@tty1.service.d
    # mensagens do kernel não aparecem por cima do login (só erros a sério)
    mkdir -pv /etc/sysctl.d
    echo "kernel.printk = 3 3 3 3" > /etc/sysctl.d/10-console-messages.conf
}

s_bash() {
    # ficheiros de arranque da bash (BLFS 'The Bash Shell Startup Files', simplificado)
    cat >> /etc/profile << "EOF"

# Nexora: profile.d, umask e bashrc
umask 022
for script in /etc/profile.d/*.sh ; do
    [ -r "$script" ] && . "$script"
done
unset script
[ -n "$BASH_VERSION" ] && [ -r /etc/bashrc ] && . /etc/bashrc
EOF
    mkdir -p /etc/profile.d
    # utilizadores normais também com /usr/sbin no PATH (shutdown, reboot, ip...)
    cat > /etc/profile.d/nexora-path.sh << "EOF"
case ":$PATH:" in *:/usr/sbin:*) ;; *) PATH=$PATH:/usr/sbin ;; esac
export PATH
EOF
    cat > /etc/bashrc << "EOF"
# Begin /etc/bashrc (Nexora)
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -lAh'
alias grep='grep --color=auto'
if [[ $EUID -eq 0 ]]; then
    PS1='\[\e[1;31m\]\u\[\e[0m\]@\[\e[1;36m\]\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]# '
else
    PS1='\[\e[1;32m\]\u\[\e[0m\]@\[\e[1;36m\]\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi
# End /etc/bashrc
EOF
    mkdir -p /etc/skel
    printf '# ~/.bash_profile\n[ -r ~/.bashrc ] && . ~/.bashrc\n' > /etc/skel/.bash_profile
    printf '# ~/.bashrc\n[ -r /etc/bashrc ] && . /etc/bashrc\n' > /etc/skel/.bashrc
    cp /etc/skel/.bash_profile /etc/skel/.bashrc /root/
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

  \e{cyan}Welcome to Nexora Linux 13.1\e{reset}   (kernel \r on \l)

  Type your username and press Enter (e.g. root).

EOF
}

T0=$SECONDS
step 9.2-network  s_network
step 9.6-console  s_console
step 9.8-inputrc  s_inputrc
step 9.10-systemd s_systemd
step 9.11-bash    s_bash
step 11.1-release s_release
echo "🎉 Capítulo 9 completo em $(( SECONDS - T0 ))s"
