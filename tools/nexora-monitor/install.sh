#!/bin/bash
# Põe o Nexora Build no menu do KDE (só para este utilizador).
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
install -m644 "$HERE/nexora.svg" ~/.local/share/icons/hicolor/scalable/apps/nexora-monitor.svg
cat > ~/.local/share/applications/nexora-monitor.desktop << DESK
[Desktop Entry]
Type=Application
Name=Nexora Build
GenericName=Monitor do build da Nexora Linux
Comment=Acompanha a compilação da Nexora Linux
Exec=python3 $HERE/nexora_monitor.py
Icon=$HERE/nexora.svg
Terminal=false
Categories=Development;System;Monitor;
StartupWMClass=nexora-monitor
Keywords=nexora;lfs;build;
DESK
update-desktop-database ~/.local/share/applications 2>/dev/null || true
kbuildsycoca6 >/dev/null 2>&1 || true
echo "✔ Nexora Build está no menu"
