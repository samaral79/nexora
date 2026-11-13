#!/bin/bash
# Desliga a VM da Nexora como deve ser.
#   1) por SSH (systemctl poweroff) — o Xfce não o intercepta
#   2) senão, botão de power ACPI via QMP (no Xfce pode abrir o diálogo "o que fazer?")
# Espera até o QEMU sair (máx. 90 s).
source "$(dirname "$0")/config.sh"
SOCK=$PROJ/vm/qmp.sock
pgrep -f "qemu-system.*file=$IMG" >/dev/null || { echo "VM já está desligada"; exit 0; }

if ssh -p 2222 -i "$PROJ/vm/nexora_ed25519" -o UserKnownHostsFile="$PROJ/vm/known_hosts" \
       -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes \
       root@127.0.0.1 'systemctl poweroff' 2>/dev/null; then
    echo "pedido de poweroff enviado por SSH"
elif [ -S "$SOCK" ]; then
    python3 -I - "$SOCK" <<'PY'
import socket, sys, json
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile('rw')
f.readline()
for cmd in ("qmp_capabilities", "system_powerdown"):
    f.write(json.dumps({"execute": cmd}) + "\n"); f.flush(); f.readline()
print("botão de power ACPI enviado")
PY
else
    echo "sem SSH nem QMP: desliga-a lá dentro com poweroff"; exit 1
fi

for i in $(seq 45); do
    pgrep -f "qemu-system.*file=$IMG" >/dev/null || { echo "✔ VM desligada"; exit 0; }
    sleep 2
done
echo "a VM ainda não desligou (vê se há um diálogo aberto lá dentro)"; exit 1
