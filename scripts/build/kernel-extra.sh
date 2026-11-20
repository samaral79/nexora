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

# Perfil de jogo (fase R, kernel do CachyOS): o mesmo que o linux-cachyos por omissão, mas com gcc
# (sem LTO/clang) e para qualquer CPU x86-64-v2 (não "native": a ISO corre em PCs diferentes).
#   BORE, 1000 Hz, tickless total, preempção total, -O3, THP sempre, NTSYNC para o Wine/Proton.
kcfg_gaming() {
    local c=scripts/config
    $c -e CACHY -e SCHED_BORE
    $c -e GENERIC_CPU -d MZEN4 -d X86_NATIVE_CPU --set-val X86_64_VERSION 2
    $c -d HZ_300 -d HZ_250 -e HZ_1000 --set-val HZ 1000
    $c -d HZ_PERIODIC -d NO_HZ_IDLE -d CONTEXT_TRACKING_FORCE -e NO_HZ_FULL_NODEF -e NO_HZ_FULL \
       -e NO_HZ -e NO_HZ_COMMON -e CONTEXT_TRACKING
    $c -e PREEMPT_DYNAMIC -e PREEMPT -d PREEMPT_LAZY -d PREEMPT_VOLUNTARY -d PREEMPT_NONE
    $c -d CC_OPTIMIZE_FOR_PERFORMANCE -e CC_OPTIMIZE_FOR_PERFORMANCE_O3
    $c -e TRANSPARENT_HUGEPAGE -d TRANSPARENT_HUGEPAGE_MADVISE -e TRANSPARENT_HUGEPAGE_ALWAYS
    $c -m NTSYNC -e FUTEX -e FUTEX_PI
    # rede (o CachyOS tem o BBRv3 como módulo; a Nexora deixa o CUBIC por omissão)
    $c -m TCP_CONG_BBR -m NET_SCH_FQ
    # escalonadores de disco que as regras udev do CachyOS escolhem (kyber, mq-deadline, bfq)
    $c -e MQ_IOSCHED_DEADLINE -e MQ_IOSCHED_KYBER -e IOSCHED_BFQ
}

# desempenho geral (fase V): a raiz inteira é uma imagem squashfs, por isso a descompressão
# tem de correr em todos os núcleos e direto para a cache de páginas; MGLRU para a memória;
# schedutil por omissão (o acpi-cpufreq ficava preso no governador "userspace")
kcfg_perf() {
    local c=scripts/config
    $c -d SQUASHFS_CHOICE_DECOMP_BY_MOUNT -d SQUASHFS_COMPILE_DECOMP_SINGLE \
       -d SQUASHFS_COMPILE_DECOMP_MULTI -e SQUASHFS_COMPILE_DECOMP_MULTI_PERCPU \
       -d SQUASHFS_FILE_CACHE -e SQUASHFS_FILE_DIRECT -e SQUASHFS_LZ4
    $c -e LRU_GEN -e LRU_GEN_ENABLED -d LRU_GEN_STATS
    $c -e CPU_FREQ_GOV_SCHEDUTIL -d CPU_FREQ_DEFAULT_GOV_USERSPACE -d CPU_FREQ_DEFAULT_GOV_PERFORMANCE \
       -d CPU_FREQ_DEFAULT_GOV_POWERSAVE -d CPU_FREQ_DEFAULT_GOV_ONDEMAND \
       -d CPU_FREQ_DEFAULT_GOV_CONSERVATIVE -e CPU_FREQ_DEFAULT_GOV_SCHEDUTIL
    # /proc/config.gz: saber com que opções o kernel que está a correr foi feito
    $c -e IKCONFIG -e IKCONFIG_PROC
}
kcfg_perf_check() {
    local o bad=0
    for o in SQUASHFS_DECOMP_MULTI_PERCPU SQUASHFS_FILE_DIRECT LRU_GEN LRU_GEN_ENABLED \
             CPU_FREQ_DEFAULT_GOV_SCHEDUTIL IKCONFIG_PROC; do
        grep -qE "^CONFIG_$o=y$" .config || { echo "CONFIG_$o não ficou ligado"; bad=1; }
    done
    return $bad
}
kcfg_gaming_check() {
    local o bad=0
    for o in CACHY SCHED_BORE HZ_1000 PREEMPT NO_HZ_FULL CC_OPTIMIZE_FOR_PERFORMANCE_O3 \
             TRANSPARENT_HUGEPAGE_ALWAYS NTSYNC MQ_IOSCHED_KYBER IOSCHED_BFQ; do
        grep -qE "^CONFIG_$o=(y|m)$" .config || { echo "CONFIG_$o não ficou ligado"; bad=1; }
    done
    return $bad
}
