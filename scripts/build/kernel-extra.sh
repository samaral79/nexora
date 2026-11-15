# Opções do kernel da Nexora para hardware real (portáteis, discos, Bluetooth, jogos).
# Usado pelo ch10.sh (build de raiz) e pela fase Q (recompila o kernel já instalado).
# Tudo como módulo: o udev carrega só o que a máquina tiver.
# Uso (dentro da árvore do kernel):  source kernel-extra.sh; kcfg_extra; make olddefconfig; kcfg_check

kcfg_extra() {
    local c=scripts/config
    # sistemas de ficheiros: pens/discos do Windows e do Mac, btrfs, DVDs; nomes UTF-8 em FAT
    $c -m NTFS3_FS -e NTFS3_LZX_XPRESS -e NTFS3_FS_POSIX_ACL -m EXFAT_FS \
       -m BTRFS_FS -e BTRFS_FS_POSIX_ACL -m XFS_FS -m F2FS_FS -m UDF_FS \
       -e NLS_UTF8 -m NLS_CODEPAGE_850 -m NLS_ISO8859_15
    # zram (swap comprimida em RAM) e Landlock (sandbox do pacman/apps)
    $c -m ZRAM -e ZSMALLOC -e ZRAM_BACKEND_ZSTD -e ZRAM_BACKEND_LZ4 -e ZRAM_DEF_COMP_ZSTD \
       -e CRYPTO_ZSTD -e CRYPTO_LZ4 -e SECURITY_LANDLOCK
    # discos cifrados (LUKS) e o que o udisks/cryptsetup usam
    $c -m DM_CRYPT -m DM_SNAPSHOT -m CRYPTO_XTS -m CRYPTO_ESSIV -m CRYPTO_USER \
       -e CRYPTO_USER_API_HASH -e CRYPTO_USER_API_SKCIPHER -e CRYPTO_USER_API_AEAD \
       -m CRYPTO_AES_NI_INTEL
    # Bluetooth completo: ratos/teclados (HIDP, BLE via UHID), áudio, partilha de rede
    $c -e BT_BREDR -e BT_LE -m BT_RFCOMM -e BT_RFCOMM_TTY -m BT_BNEP -e BT_BNEP_MC_FILTER \
       -e BT_BNEP_PROTO_FILTER -m BT_HIDP -m UHID -m CRYPTO_CCM -m CRYPTO_CMAC -m CRYPTO_ECDH
    # webcams USB (UVC)
    $c -m MEDIA_SUPPORT -e MEDIA_SUPPORT_FILTER -e MEDIA_CAMERA_SUPPORT -e MEDIA_USB_SUPPORT \
       -m USB_VIDEO_CLASS -e USB_VIDEO_CLASS_INPUT_EVDEV
    # comandos de jogos e periféricos comuns
    $c -e GPIOLIB -e GPIO_ACPI -e LEDS_CLASS -e LEDS_CLASS_MULTICOLOR -e NEW_LEDS \
       -m INPUT_JOYDEV -m JOYSTICK_XPAD -e JOYSTICK_XPAD_FF -e JOYSTICK_XPAD_LEDS \
       -m HID_PLAYSTATION -e PLAYSTATION_FF -m HID_SONY -e SONY_FF -m HID_NINTENDO -e NINTENDO_FF \
       -m HID_STEAM -m HID_LOGITECH -m HID_LOGITECH_DJ -m HID_LOGITECH_HIDPP -m HID_APPLE \
       -m HID_MICROSOFT -m HID_LENOVO -m HID_ASUS -m HID_SENSOR_HUB
    # portáteis: touchpads I2C (Intel/AMD), botões, perfis de energia, suspensão AMD, USB-C
    $c -e COMMON_CLK -m I2C_DESIGNWARE_CORE -m I2C_DESIGNWARE_PLATFORM -m I2C_DESIGNWARE_PCI -m MFD_INTEL_LPSS_PCI -m MFD_INTEL_LPSS_ACPI \
       -m INTEL_IDMA64 -e PINCTRL -e PINCTRL_AMD -e PINCTRL_INTEL -e PINCTRL_SUNRISEPOINT -e PINCTRL_CANNONLAKE \
       -e PINCTRL_ICELAKE -e PINCTRL_TIGERLAKE -e PINCTRL_ALDERLAKE -e PINCTRL_METEORLAKE \
       -e PINCTRL_METEORPOINT -e PINCTRL_JASPERLAKE -e PINCTRL_ELKHARTLAKE -e PINCTRL_LAKEFIELD \
       -e PINCTRL_BROXTON -e PINCTRL_GEMINILAKE -e PINCTRL_LUNARLAKE \
       -e SPI -e SPI_MASTER -m SPI_PXA2XX -m SPI_AMD -m TEE -m CRYPTO_DEV_CCP -m CRYPTO_DEV_CCP_DD \
       -e CRYPTO_DEV_SP_PSP -m AMDTEE -m AMD_SFH_HID \
       -m AMD_PMC -m AMD_PMF -m INTEL_HID_EVENT -m INTEL_VBTN -m THINKPAD_ACPI -m IDEAPAD_LAPTOP \
       -m ASUS_WMI -m ASUS_NB_WMI -m HP_WMI -m DELL_WMI -m ACER_WMI -m MSI_WMI \
       -m SENSORS_K10TEMP -m SENSORS_CORETEMP -m TYPEC -m TYPEC_UCSI -m UCSI_ACPI -m USB4
    # som dos portáteis modernos: SOF (Intel), ACP (AMD), amplificadores Cirrus/TI das colunas
    $c -m SND_SOC -m SND_SOC_DMIC -e SND_SOC_SOF_TOPLEVEL -m SND_SOC_SOF_PCI -m SND_SOC_SOF_ACPI \
       -e SND_SOC_SOF_INTEL_TOPLEVEL -m SND_SOC_SOF_APOLLOLAKE -m SND_SOC_SOF_GEMINILAKE \
       -m SND_SOC_SOF_CANNONLAKE -m SND_SOC_SOF_COFFEELAKE -m SND_SOC_SOF_COMETLAKE \
       -m SND_SOC_SOF_ICELAKE -m SND_SOC_SOF_JASPERLAKE -m SND_SOC_SOF_TIGERLAKE \
       -m SND_SOC_SOF_ELKHARTLAKE -m SND_SOC_SOF_ALDERLAKE -m SND_SOC_SOF_METEORLAKE \
       -m SND_SOC_SOF_LUNARLAKE -m SND_SOC_SOF_PANTHERLAKE \
       -e SND_SOC_SOF_HDA_LINK -e SND_SOC_SOF_HDA_AUDIO_CODEC -m SOUNDWIRE -m SOUNDWIRE_INTEL \
       -m SND_SOC_SOF_INTEL_SOUNDWIRE -e SND_SOC_INTEL_MACH -e SND_SOC_INTEL_USER_FRIENDLY_LONG_NAMES \
       -m SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH -m SND_SOC_INTEL_SOUNDWIRE_SOF_MACH \
       -m SND_SOC_INTEL_SOF_RT5682_MACH -m SND_SOC_INTEL_SOF_CS42L42_MACH \
       -m SND_SOC_INTEL_SOF_SSP_AMP_MACH -m SND_SOC_INTEL_SOF_NAU8825_MACH \
       -m SND_SOC_INTEL_SOF_DA7219_MACH -m SND_SOC_INTEL_SOF_ES8336_MACH \
       -m SND_SOC_AMD_ACP -m SND_SOC_AMD_ACP3x -m SND_SOC_AMD_RENOIR -m SND_SOC_AMD_RENOIR_MACH \
       -m SND_SOC_AMD_ACP5x -m SND_SOC_AMD_ACP6x -m SND_SOC_AMD_YC_MACH -m SND_SOC_AMD_RPL_ACP6x \
       -m SND_SOC_AMD_PS -m SND_SOC_AMD_PS_MACH -m SND_SOC_AMD_ACP_COMMON -m SND_SOC_AMD_ACP_PCI \
       -e SND_SOC_SOF_AMD_TOPLEVEL -m SND_SOC_SOF_AMD_REMBRANDT -m SND_SOC_SOF_AMD_ACP63 \
       -m SND_SOC_SOF_AMD_ACP70 \
       -m SND_HDA_SCODEC_CS35L41_I2C -m SND_HDA_SCODEC_CS35L41_SPI -m SND_HDA_SCODEC_TAS2781_I2C \
       -m SND_HDA_CODEC_CS8409 -m SND_HDA_CODEC_SIGMATEL -m SND_HDA_CODEC_HDMI
    # rede: VPN (WireGuard/OpenVPN), firewall nftables, contentores (bridge/veth), telemóveis por USB
    $c -m TUN -m WIREGUARD -m NF_TABLES -e NF_TABLES_INET -e NF_TABLES_IPV4 -e NF_TABLES_IPV6 \
       -m NF_CONNTRACK -m NF_NAT -m NFT_CT -m NFT_NAT -m NFT_MASQ -m NFT_REJECT -m NFT_COMPAT \
       -m NFT_FIB_INET -m BRIDGE -m VETH -m MACVLAN -m USB_NET_CDC_NCM -m USB_IPHETH
    # Arduino e afins (porta série por USB)
    $c -m USB_ACM -m USB_SERIAL -m USB_SERIAL_CH341 -m USB_SERIAL_CP210X -m USB_SERIAL_FTDI_SIO
}

# depois do olddefconfig: o essencial tem de ter ficado (=y ou =m); o resto só avisa
kcfg_check() {
    local o bad=0
    for o in NTFS3_FS EXFAT_FS BTRFS_FS ZRAM SECURITY_LANDLOCK DM_CRYPT BT_HIDP BT_RFCOMM UHID \
             USB_VIDEO_CLASS I2C_DESIGNWARE_CORE I2C_DESIGNWARE_PLATFORM I2C_DESIGNWARE_PCI PINCTRL_AMD JOYSTICK_XPAD HID_PLAYSTATION \
             SND_SOC_SOF_TIGERLAKE SND_SOC_AMD_PS TUN WIREGUARD NF_TABLES UCSI_ACPI NLS_UTF8; do
        grep -qE "^CONFIG_$o=(y|m)$" .config || { echo "CONFIG_$o não ficou ligado"; bad=1; }
    done
    for o in SND_SOC_SOF_METEORLAKE SND_SOC_SOF_LUNARLAKE SND_SOC_INTEL_SOUNDWIRE_SOF_MACH \
             SND_SOC_SOF_AMD_ACP63 PINCTRL_METEORLAKE PINCTRL_LUNARLAKE ZRAM_DEF_COMP_ZSTD AMD_PMF; do
        grep -qE "^CONFIG_$o=(y|m)$" .config || echo "aviso: CONFIG_$o não existe/ficou desligado"
    done
    return $bad
}
