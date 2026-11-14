#!/bin/bash
# Fase D (dentro do chroot, como root): toques da Nexora por cima do Xfce.
#   loader SVG do gdk-pixbuf, wallpaper da Nexora (desktop + login), screenshooter.
source "$(dirname "$0")/lib.sh"
B=blfs
P=/sources/blfs
WP=/usr/share/backgrounds/nexora/nexora-wallpaper.png
export PATH=/opt/rustc/bin:$PATH

mbuild() {
    # pasta própria (há tarballs que já trazem uma pasta build/) e sem && (o set -e não apanha)
    mkdir nx-build
    cd nx-build
    meson setup .. --prefix=/usr --buildtype=release "$@"
    ninja
    ninja install
}

p_rsvgloader() {
    # o librsvg 2.62 traz o loader SVG do gdk-pixbuf desligado por defeito;
    # sem ele o wallpaper do Xfce (SVG) fica preto e há ícones que não aparecem
    sed -e "/OUTDIR/s|,| / 'librsvg-2.62.3', '--no-namespace-dir',|" \
        -e '/output/s|Rsvg-2.0|librsvg-2.62.3|' -i doc/meson.build
    mbuild -D docs=disabled -D vala=disabled -D tests=false -D pixbuf-loader=enabled
    gdk-pixbuf-query-loaders --update-cache
    grep -q svg /usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
}

s_wallpaper() {
    install -vDm644 $P/nexora-wallpaper.png $WP
}

p_xfdesktop() {
    ./configure --prefix=/usr --with-default-backdrop-filename=$WP
    make
    make install
}

p_screenshooter() { mbuild -D wayland=disabled; }

s_greeter() {
    grep -q '^background' /etc/lightdm/lightdm-gtk-greeter.conf ||
        sed -i "/^\[greeter\]/a background = $WP" /etc/lightdm/lightdm-gtk-greeter.conf
    grep -q '^user-background' /etc/lightdm/lightdm-gtk-greeter.conf ||
        sed -i "/^\[greeter\]/a user-background = false" /etc/lightdm/lightdm-gtk-greeter.conf
    gtk-update-icon-cache -qtf /usr/share/icons/elementary-xfce || true
}

s_display() {
    # o QEMU (janela GTK) anuncia 640x480 ao início; a Nexora escolhe 1920x1080 na VM.
    # Em hardware real não há saída Virtual-1 e o script não faz nada.
    cat > /usr/bin/nexora-display-setup << "EOF"
#!/bin/sh
if xrandr | grep -q "^Virtual-1 connected"; then
    xrandr --output Virtual-1 --mode 1920x1080 2>/dev/null || xrandr --output Virtual-1 --auto
fi
exit 0
EOF
    chmod 755 /usr/bin/nexora-display-setup
    mkdir -p /etc/lightdm/lightdm.conf.d
    printf "[Seat:*]\ndisplay-setup-script=/usr/bin/nexora-display-setup\n" > /etc/lightdm/lightdm.conf.d/50-nexora.conf
}

T0=$SECONDS
pkg  D.01-librsvg-loader  $B/librsvg-2.62.3.tar.xz              p_rsvgloader
step D.02-wallpaper       s_wallpaper
pkg  D.03-xfdesktop       $B/xfdesktop-4.20.2.tar.bz2           p_xfdesktop
pkg  D.04-screenshooter   $B/xfce4-screenshooter-1.11.3.tar.xz  p_screenshooter
step D.05-greeter         s_greeter
step D.06-display         s_display
echo "🎉 Fase D (toques Nexora) completa em $(( SECONDS - T0 ))s"
