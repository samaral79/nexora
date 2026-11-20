#!/usr/bin/env bash
# shellcheck disable=SC2034
# Nexora Linux (base CachyOS): ISO live e instaladora
iso_name="nexora"
iso_label="NEXORA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Nexora Linux <https://github.com/samaral79>"
iso_application="Nexora Linux Live/Install"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="nexora"
buildmodes=('iso')
# UEFI pelo GRUB: lê o kernel da própria ISO (sem segunda cópia na imagem EFI)
bootmodes=('bios.syslinux'
           'uefi.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# xz com filtro x86 (BCJ): mais pequeno que o zstd, o live e a instalação descomprimem mais devagar
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '100%' '-xattrs-exclude' '^security.selinux')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/nexora-live-setup"]="0:0:755"
)
