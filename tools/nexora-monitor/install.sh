#!/bin/bash
# Compila o Nexora Build (Rust) e põe-no no menu do KDE (só para este utilizador).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cargo build --release --manifest-path "$HERE/Cargo.toml"
install -Dm755 "$HERE/target/release/nexora-monitor" ~/.local/bin/nexora-monitor
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
install -m644 "$HERE/nexora.svg" ~/.local/share/icons/hicolor/scalable/apps/nexora-monitor.svg
cat > ~/.local/share/applications/nexora-monitor.desktop << DESK
[Desktop Entry]
Type=Application
Name=Nexora Build
GenericName=Monitor do build da Nexora Linux
Comment=Acompanha a compilação da Nexora Linux
Exec=$HOME/.local/bin/nexora-monitor
Icon=$HOME/.local/share/icons/hicolor/scalable/apps/nexora-monitor.svg
Terminal=false
Categories=Development;System;Monitor;
StartupWMClass=nexora-monitor
Keywords=nexora;lfs;build;
DESK
update-desktop-database ~/.local/share/applications 2>/dev/null || true
gtk-update-icon-cache -q ~/.local/share/icons/hicolor 2>/dev/null || true
kbuildsycoca6 >/dev/null 2>&1 || true
echo "✔ Nexora Build está no menu"
