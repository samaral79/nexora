# Nexora Linux

A personal Linux distribution, first built from scratch with **Linux From Scratch 13.1 (systemd)** and now
also available as a `pacman`-based edition. Both share the same look, graphical installer and gaming tweaks.

## Download

ISOs are on the [releases](https://github.com/samaral79/nexora/releases) page:

| Edition | What it is | Updates with |
|---|---|---|
| **Nexora** — the main edition | binary packages, kernel with the BORE scheduler, btrfs with snapshots | `pacman` (a snapshot is taken before every update; pick an older one in the Limine boot menu if something breaks) |
| **Nexora LFS 13.1** | everything compiled from source by these scripts, read-only system | A/B system images (`systemd-sysupdate`) |

Both boot into a live session (Xfce) with the installer. They need UEFI and a disk of 30 GB or more.
The installer erases the chosen disk.

## The process, step by step

Each phase is one script, and the git history follows the same order.

| Phase | Script | What it adds |
|---|---|---|
| LFS chapters 4–10 | `scripts/build/` | toolchain, terminal-only base system, kernel, boot |
| A–F | `scripts/blfs/blfs-a.sh` … `blfs-f.sh` | BLFS: networking, PAM, sudo, Xorg, Xfce, Firefox, installer |
| G–I | `blfs-g.sh` … `blfs-i.sh` | Nexora theme, Wayland, niri and the Nexora Flow desktop |
| J–O | `blfs-j.sh` … `blfs-o.sh` | GTK4 apps, Flatpak and the software store, video, new look, fixes |
| P | `blfs-p.sh` + `tools/aur/` | AUR in an isolated Arch container (`nexora-aur`) |
| Q | `blfs-q.sh` | real hardware: laptops, Bluetooth, SOF audio, disks, zram |
| R | `blfs-r.sh` | gaming: BORE kernel, full Mesa, GameMode |
| S–T | `blfs-s.sh`, `blfs-t.sh` | NVIDIA/Intel drivers, printers, firewall, screen lock |
| U | `blfs-u.sh` + `tools/update/` | A/B image updates |
| V | `blfs-v.sh` | performance: multi-core squashfs, MGLRU, schedutil, systemd-oomd, TRIM |
| W | `blfs-w.sh` | CPU microcode, session limits (GameMode, PipeWire), memory tuning |
| pacman edition | `cachy/` | Nexora built from binary packages, with `pacman` |

## pacman edition (`cachy/`)

```bash
./cachy/build.sh            # ISO in cachy-out/ (runs in a Docker container)
```

- `cachy/pkgs/`: the Nexora packages — `nexora-base` (branding, firewall, NVIDIA driver selection,
  GameMode), `nexora-flow` (desktop and Settings app), `nexora-theme`, `nexora-installer` and `eww`.
- `cachy/iso/`: the `mkarchiso` profile. The system image uses squashfs xz with the x86 filter so the ISO
  fits within the 2 GiB limit of a GitHub release asset.
- Installed layout: 2 GiB EFI partition and btrfs (`@`, `@home`, `@root`, `@srv`, `@cache`, `@log`, `@tmp`),
  with Limine, snapper and snap-pac.

## LFS edition

Everything is compiled inside `lfs.img`, a virtual disk mounted at `/mnt/lfs` only while building; the host
system is never touched.

- `scripts/00-host-setup.sh` (sudo): installs the dependencies, creates and mounts `lfs.img` and creates the `lfs` user
- `scripts/01-download.sh`: downloads the sources and checks their md5
- `scripts/mount.sh` / `scripts/umount.sh` (sudo): mount and unmount the virtual disk
- `scripts/build-bg.sh <phase>...` (sudo): builds phases in the background (`NX_GAMING=1` to build while gaming)
- `scripts/release/make-release.sh` (sudo): creates a release in `release/<version>/`
- `scripts/iso/build-iso.sh` (sudo): builds the ISO from the latest release (`release/LATEST`)
- `tools/nexora-monitor/`: a Rust + Slint app that follows the build

### Releases and A/B updates

Each release is an image of the whole system, identical for everyone:

- `nexora_<version>.root.raw`: the system (read-only squashfs). The same file is used for the live session, for installing and for updating.
- `nexora_<version>.efi`: a UKI (kernel + microcode + initramfs + command line) for systemd-boot.
- `SHA256SUMS` + `SHA256SUMS.gpg`: signed with the "Nexora Linux Releases" key. The public key is
  `tools/update/nexora-release.pgp`; the private key never goes into the repository.

An installed disk has four partitions: EFI, system A, system B and `nexora-data` (mounted at `/var`). `/home`,
`/root` and `/usr/local` live in `/var`, and `/etc` is the image with your changes on top (overlay).
`systemd-sysupdate` downloads the new release to the free partition and systemd-boot starts it on the next boot.
If it fails to boot 3 times, the previous release comes back automatically.

Test releases and ISOs (`--dev-key`) carry a development SSH key and are **never published**.

## Credits

Nexora stands on the work of [Linux From Scratch / Beyond LFS](https://www.linuxfromscratch.org/),
[CachyOS](https://cachyos.org/) (kernel, settings and package repositories of the `pacman` edition),
[Arch Linux](https://archlinux.org/) (`pacman`, `archiso`), [niri](https://github.com/YaLTeR/niri),
[eww](https://github.com/elkowar/eww), the [Colloid](https://github.com/vinceliuice/Colloid-gtk-theme) GTK theme,
[Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) icons and
[Bibata](https://github.com/ful1e5/Bibata_Cursor) cursors.

## License

The Nexora scripts, tools and packages are licensed under the
[GNU GPL v3 or later](LICENSE) (GPL-3.0-or-later). The software these scripts download and build
(LFS/BLFS, CachyOS, Arch and all other projects) keeps the licenses of its authors.
