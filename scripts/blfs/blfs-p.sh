#!/bin/bash
# Fase P (dentro do chroot, como root): o AUR na Nexora, isolado.
#   nexora-aur: um contentor Arch em /var/lib/nexora-aur (criado só quando o utilizador quiser,
#   com "nexora-aur setup"); as apps do AUR correm numa sandbox e aparecem no menu.
#   Nada disto toca no /usr da Nexora.
source "$(dirname "$0")/lib.sh"
A=$(dirname "$0")/aur

s_aur() {
    install -vm755 $A/nexora-aur /usr/bin/nexora-aur
    bash -n /usr/bin/nexora-aur

    # as apps e os comandos exportados do contentor (no fim: o sistema ganha sempre)
    cat > /etc/profile.d/nexora-aur.sh << "EOF"
# apps do AUR (nexora-aur): menu e terminal; o sistema tem prioridade
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/var/lib/nexora-aur/exports/share"
case ":$PATH:" in *:/var/lib/nexora-aur/exports/bin:*) ;; *) export PATH="$PATH:/var/lib/nexora-aur/exports/bin" ;; esac
EOF

    # pkexec com a senha guardada uns minutos (instalar várias coisas seguidas sem a pedir sempre)
    cat > /usr/share/polkit-1/actions/org.nexora.aur.policy << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Nexora Linux</vendor>
  <action id="org.nexora.aur">
    <description>Manage AUR apps</description>
    <description xml:lang="pt">Gerir apps do AUR</description>
    <message>Authentication is required to install or remove AUR apps</message>
    <message xml:lang="pt">É preciso autenticação para instalar ou remover apps do AUR</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/nexora-aur</annotate>
  </action>
</policyconfig>
EOF

    # vazio de origem: o contentor só é criado com "nexora-aur setup" (na sessão live fica em RAM;
    # se o preparares lá, o instalador leva-o para o disco com o resto do sistema)
    install -dm755 /var/lib/nexora-aur
}

T0=$SECONDS
step P.01-aur s_aur
echo "🎉 Fase P (AUR isolado) completa em $(( (SECONDS - T0) / 60 )) min"
