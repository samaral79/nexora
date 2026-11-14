#!/usr/bin/env python3
"""Nexora Build — monitor gráfico do build da Nexora Linux (PyQt6).

Lê, sem root:
  /mnt/lfs/sources/.done e .logs     -> estado de cada pacote
  scripts/build/*.sh, scripts/blfs/*.sh -> ordem dos pacotes por fase
  journal do serviço nexora-build    -> horas de início e durações
  cgroup do serviço                  -> memória e CPU do build
Quando a imagem está desmontada mostra o último estado guardado em ~/.cache.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

from PyQt6.QtCore import Qt, QTimer, QSize, QUrl, QRectF
from PyQt6.QtGui import (QAction, QColor, QDesktopServices, QFont, QFontDatabase, QIcon, QPainter, QPalette,
                         QPixmap, QTextCursor)
from PyQt6.QtWidgets import (
    QApplication, QCheckBox, QFrame, QGridLayout, QHBoxLayout, QHeaderView, QLabel, QMainWindow,
    QMessageBox, QPlainTextEdit, QProgressBar, QPushButton, QSizePolicy, QSplitter, QTabWidget,
    QMenu, QSystemTrayIcon, QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget,
)

HERE = Path(__file__).resolve().parent
PROJ = HERE.parents[1]
SCRIPTS = PROJ / "scripts"
LFS = Path("/mnt/lfs")
DONE = LFS / "sources/.done"
LOGS = LFS / "sources/.logs"
UNIT = "nexora-build"
CGROUP = Path(f"/sys/fs/cgroup/system.slice/{UNIT}.service")
CACHE = Path.home() / ".cache/nexora-monitor/state.json"
ICON = HERE / "nexora.svg"
ACCENT = "#22b8cf"

PHASES = [
    ("ch5", "Cap. 5 · Toolchain cruzada", "build/ch5.sh"),
    ("ch6", "Cap. 6 · Ferramentas temporárias", "build/ch6.sh"),
    ("ch7", "Cap. 7 · Chroot", "build/ch7.sh"),
    ("ch8", "Cap. 8 · Sistema base", "build/ch8.sh"),
    ("ch9", "Cap. 9 · Configuração", "build/ch9.sh"),
    ("ch10", "Cap. 10 · Kernel e GRUB", "build/ch10.sh"),
    ("blfs-a", "BLFS A · Rede e ferramentas", "blfs/blfs-a.sh"),
    ("blfs-b", "BLFS B · Xorg, Mesa e GTK", "blfs/blfs-b.sh"),
    ("blfs-c", "BLFS C · Xfce e LightDM", "blfs/blfs-c.sh"),
    ("blfs-d", "Nexora · Toques finais", "blfs/blfs-d.sh"),
    ("blfs-e", "Nexora · Xfce de origem", "blfs/blfs-e.sh"),
    ("blfs-f", "Nexora · Live e instalador", "blfs/blfs-f.sh"),
    ("blfs-g", "Nexora · Hardware e visual", "blfs/blfs-g.sh"),
    ("blfs-h", "Nexora Flow · Wayland", "blfs/blfs-h.sh"),
]
# fases que correm dentro do chroot (as que o botão Retomar sabe relançar)
CHROOT_PHASES = ["ch7", "ch8", "ch9", "ch10", "blfs-a", "blfs-b", "blfs-c", "blfs-d", "blfs-e", "blfs-f", "blfs-g", "blfs-h"]

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07|\r")
JLINE = re.compile(r"^(\d+\.\d+) \S+ \S+: (🔨|✔|✘|⏭)\s+(\S+)(?: \.\.\.)?(?: \((\d+)m(\d+)s\))?")
JEND = re.compile(r"^(\d+\.\d+) \S+ \S+: (🎉|🏁)\s*(.*)$")


def nice(pid):
    """B.49-rust -> rust"""
    return re.sub(r"^[A-Z]?\d*\.?\d+[a-z]?-", "", pid) or pid


def hms(sec):
    sec = int(max(0, sec))
    h, m, s = sec // 3600, sec % 3600 // 60, sec % 60
    return f"{h}h{m:02d}m" if h else (f"{m}m{s:02d}s" if m else f"{s}s")


def gib(b):
    return f"{b / 2**30:.1f} GiB"


def read_int(p, default=None):
    try:
        v = Path(p).read_text().strip()
        return None if v == "max" else int(v)
    except Exception:
        return default


# ------------------------------------------------------------------ dados
class Model:
    def __init__(self):
        self.phases = []          # [(key, label, [ids])]
        self.order = []           # todos os ids por ordem
        self.phase_of = {}
        self.starts = {}          # id -> epoch de início (journal)
        self.durations = {}       # id -> segundos (journal)
        self.events = []          # (epoch, texto) de 🎉/🏁
        self.first_seen = {}
        self.cpu_prev = None
        self.last_start = self.last_closed = None
        self.load_scripts()

    def load_scripts(self):
        self.phases, self.order, self.phase_of = [], [], {}
        for key, label, rel in PHASES:
            f = SCRIPTS / rel
            ids = []
            if f.exists():
                for line in f.read_text().splitlines():
                    m = re.match(r"^(?:pkg|step)\s+(\S+)", line)
                    if m:
                        ids.append(m.group(1))
            self.phases.append((key, label, ids))
            for i in ids:
                self.order.append(i)
                self.phase_of[i] = key

    def read_journal(self):
        try:
            out = subprocess.run(["journalctl", "-u", UNIT, "-o", "short-unix", "-q", "--no-pager", "-n", "4000"],
                                 capture_output=True, text=True, timeout=5).stdout
        except Exception:
            return
        events = []
        self.last_start, self.last_closed = None, None
        for line in out.splitlines():
            m = JLINE.match(line)
            if m:
                t, sym, pid = float(m.group(1)), m.group(2), m.group(3)
                if sym == "🔨":
                    self.starts[pid] = t
                    self.last_start = pid
                elif sym in ("✔", "✘") and pid == self.last_start:
                    self.last_closed = pid
                elif sym == "✔" and m.group(4):
                    self.durations[pid] = int(m.group(4)) * 60 + int(m.group(5))
                continue
            m = JEND.match(line)
            if m:
                events.append((float(m.group(1)), m.group(3)))
        self.events = events

    def service(self):
        try:
            out = subprocess.run(["systemctl", "show", UNIT, "-p", "ActiveState", "-p", "Result",
                                  "-p", "ExecMainStartTimestamp", "-p", "ExecMainExitTimestamp"],
                                 capture_output=True, text=True, timeout=3).stdout
        except Exception:
            out = ""
        d = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
        try:
            ex = subprocess.run(["systemctl", "show", UNIT, "-p", "ExecStart", "--value"],
                                capture_output=True, text=True, timeout=3).stdout
            d["chain"] = re.findall(r"chroot\.sh (\S+)", ex)
        except Exception:
            d["chain"] = []
        return d

    def resources(self):
        r = {}
        mem = {}
        try:
            for l in Path("/proc/meminfo").read_text().splitlines():
                k, v = l.split(":", 1)
                mem[k] = int(v.split()[0]) * 1024
        except Exception:
            pass
        r["ram_total"] = mem.get("MemTotal", 1)
        r["ram_used"] = mem.get("MemTotal", 0) - mem.get("MemAvailable", 0)
        r["swap_total"] = mem.get("SwapTotal", 0)
        r["swap_used"] = mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)
        if CGROUP.exists():
            r["b_cur"] = read_int(CGROUP / "memory.current", 0)
            r["b_high"] = read_int(CGROUP / "memory.high")
            r["b_max"] = read_int(CGROUP / "memory.max")
            r["b_swap"] = read_int(CGROUP / "memory.swap.current", 0)
            try:
                usage = int(re.search(r"usage_usec (\d+)", (CGROUP / "cpu.stat").read_text()).group(1))
                now = time.monotonic()
                if self.cpu_prev:
                    du, dt = usage - self.cpu_prev[0], now - self.cpu_prev[1]
                    r["cores"] = du / 1e6 / dt if dt > 0 else 0
                self.cpu_prev = (usage, now)
            except Exception:
                pass
        else:
            self.cpu_prev = None
        try:
            r["load"] = Path("/proc/loadavg").read_text().split()[0]
        except Exception:
            r["load"] = "?"
        if os.path.ismount(LFS):
            du = shutil.disk_usage(LFS)
            r["disk"] = (du.used, du.total)
        return r

    def snapshot(self):
        """Estado de todos os pacotes. Usa a cache se a imagem não estiver montada."""
        mounted = os.path.ismount(LFS) and DONE.exists()
        if mounted:
            done = set(os.listdir(DONE))
            logs = set(f[:-4] for f in os.listdir(LOGS) if f.endswith(".log")) if LOGS.exists() else set()
            try:
                CACHE.parent.mkdir(parents=True, exist_ok=True)
                CACHE.write_text(json.dumps({"done": sorted(done), "logs": sorted(logs), "t": time.time()}))
            except Exception:
                pass
            cached_at = None
        else:
            try:
                c = json.loads(CACHE.read_text())
                done, logs, cached_at = set(c["done"]), set(c["logs"]), c["t"]
            except Exception:
                done, logs, cached_at = set(), set(), 0
        return mounted, done, logs, cached_at


# ------------------------------------------------------------------ widgets
class Card(QFrame):
    def __init__(self, title=None):
        super().__init__()
        self.setObjectName("card")
        self.lay = QVBoxLayout(self)
        self.lay.setContentsMargins(14, 12, 14, 12)
        self.lay.setSpacing(8)
        if title:
            t = QLabel(title.upper())
            t.setObjectName("cardTitle")
            self.lay.addWidget(t)


class Meter(QWidget):
    """rótulo + barra + valor"""
    def __init__(self, label):
        super().__init__()
        g = QGridLayout(self)
        g.setContentsMargins(0, 0, 0, 0)
        g.setVerticalSpacing(3)
        self.name = QLabel(label)
        self.value = QLabel("—")
        self.value.setAlignment(Qt.AlignmentFlag.AlignRight)
        self.value.setObjectName("dim")
        self.bar = QProgressBar()
        self.bar.setTextVisible(False)
        self.bar.setFixedHeight(6)
        self.bar.setRange(0, 1000)
        g.addWidget(self.name, 0, 0)
        g.addWidget(self.value, 0, 1)
        g.addWidget(self.bar, 1, 0, 1, 2)

    def set(self, frac, text, warn=False):
        self.bar.setValue(int(max(0, min(1, frac)) * 1000))
        self.value.setText(text)
        self.bar.setProperty("warn", "1" if warn else "0")
        self.bar.style().unpolish(self.bar)
        self.bar.style().polish(self.bar)


class PhaseRow(QWidget):
    def __init__(self, label):
        super().__init__()
        g = QGridLayout(self)
        g.setContentsMargins(0, 2, 0, 2)
        g.setVerticalSpacing(3)
        self.name = QLabel(label)
        self.count = QLabel()
        self.count.setObjectName("dim")
        self.count.setAlignment(Qt.AlignmentFlag.AlignRight)
        self.bar = QProgressBar()
        self.bar.setTextVisible(False)
        self.bar.setFixedHeight(5)
        g.addWidget(self.name, 0, 0)
        g.addWidget(self.count, 0, 1)
        g.addWidget(self.bar, 1, 0, 1, 2)

    def set(self, n, total, active):
        self.bar.setRange(0, max(total, 1))
        self.bar.setValue(n)
        self.count.setText(f"{n}/{total}")
        f = self.name.font()
        f.setBold(active)
        self.name.setFont(f)
        self.bar.setProperty("complete", "1" if n == total and total else "0")
        self.bar.style().unpolish(self.bar)
        self.bar.style().polish(self.bar)


# ------------------------------------------------------------------ símbolo
STATUS_COLORS = {"A compilar": ACCENT, "Falhou": "#e5534b", "Completo": "#3fb950", "Parado": "#8b949e"}


def status_icon(status, frac):
    """Hexágono da Nexora + ponto de estado + barrinha de progresso (para o painel e a janela)."""
    icon = QIcon()
    base = QIcon(str(ICON))
    for size in (16, 22, 24, 32, 48, 64):
        pm = QPixmap(size, size)
        pm.fill(Qt.GlobalColor.transparent)
        p = QPainter(pm)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        inner = int(size * 0.86)
        p.drawPixmap(0, 0, base.pixmap(inner, inner))
        col = QColor(STATUS_COLORS.get(status, "#8b949e"))
        # barra de progresso em baixo
        h = max(2, size // 9)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(128, 128, 128, 140))
        p.drawRoundedRect(QRectF(0, size - h, size, h), h / 2, h / 2)
        p.setBrush(col)
        p.drawRoundedRect(QRectF(0, size - h, max(h, size * frac), h), h / 2, h / 2)
        # ponto de estado
        d = max(5, int(size * 0.36))
        p.setBrush(QColor(20, 20, 20, 200))
        p.drawEllipse(QRectF(size - d - 1, size - d - h - 1, d + 2, d + 2))
        p.setBrush(col)
        p.drawEllipse(QRectF(size - d, size - d - h, d, d))
        p.end()
        icon.addPixmap(pm)
    return icon


# ------------------------------------------------------------------ janela
class Window(QMainWindow):
    SPIN = "◐◓◑◒"

    def __init__(self):
        super().__init__()
        self.m = Model()
        self.setWindowTitle("Nexora Build")
        self.setWindowIcon(QIcon(str(ICON)))
        self.resize(1180, 760)
        self.setMinimumSize(920, 600)
        self.tick_n = 0
        self.prev_status = None
        self.prev_events = None
        self.selected_log = None   # pacote escolhido na lista (None = segue o atual)
        self.items = {}
        self.build_ui()
        self.quitting = False
        self.tray = None
        self.icon_key = None
        if QSystemTrayIcon.isSystemTrayAvailable():
            self.tray = QSystemTrayIcon(QIcon(str(ICON)), self)
            menu = QMenu()
            self.act_toggle = QAction("Esconder janela", self)
            self.act_toggle.triggered.connect(self.toggle_window)
            self.act_stop = QAction(QIcon.fromTheme("media-playback-stop"), "Parar build", self)
            self.act_stop.triggered.connect(self.stop_build)
            self.act_resume = QAction(QIcon.fromTheme("media-playback-start"), "Retomar build", self)
            self.act_resume.triggered.connect(self.resume_build)
            act_quit = QAction(QIcon.fromTheme("application-exit"), "Sair do monitor", self)
            act_quit.triggered.connect(self.quit_app)
            menu.addAction(self.act_toggle)
            menu.addSeparator()
            menu.addAction(self.act_stop)
            menu.addAction(self.act_resume)
            menu.addSeparator()
            menu.addAction(act_quit)
            self.tray_menu = menu
            self.tray.setContextMenu(menu)
            self.tray.activated.connect(self.tray_clicked)
            self.tray.show()
        self.refresh(full=True)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(1500)

    # ---------- UI
    def build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)
        v = QVBoxLayout(root)
        v.setContentsMargins(18, 14, 18, 14)
        v.setSpacing(12)

        # topo
        top = QHBoxLayout()
        logo = QLabel()
        logo.setPixmap(QIcon(str(ICON)).pixmap(QSize(40, 40)))
        top.addWidget(logo)
        tl = QVBoxLayout()
        tl.setSpacing(0)
        title = QLabel("Nexora Linux")
        title.setObjectName("title")
        self.subtitle = QLabel()
        self.subtitle.setObjectName("dim")
        tl.addWidget(title)
        tl.addWidget(self.subtitle)
        top.addLayout(tl)
        top.addStretch()
        self.clock = QLabel()
        self.clock.setObjectName("dim")
        top.addWidget(self.clock)
        self.pill = QLabel()
        self.pill.setObjectName("pill")
        self.pill.setFixedHeight(26)
        self.pill.setAlignment(Qt.AlignmentFlag.AlignCenter)
        top.addWidget(self.pill, 0, Qt.AlignmentFlag.AlignVCenter)
        v.addLayout(top)

        # progresso total
        self.total = QProgressBar()
        self.total.setObjectName("total")
        self.total.setFixedHeight(26)
        self.total.setFormat("%v / %m pacotes · %p%")
        v.addWidget(self.total)

        split = QSplitter(Qt.Orientation.Horizontal)
        v.addWidget(split, 1)

        # coluna esquerda: fases + recursos
        left = QWidget()
        lv = QVBoxLayout(left)
        lv.setContentsMargins(0, 0, 0, 0)
        lv.setSpacing(12)
        ph = Card("Fases")
        self.phase_rows = {}
        for key, label, _ in PHASES:
            r = PhaseRow(label)
            self.phase_rows[key] = r
            ph.lay.addWidget(r)
        lv.addWidget(ph)
        res = Card("Recursos")
        self.m_build = Meter("Memória do build")
        self.m_ram = Meter("RAM do PC")
        self.m_swap = Meter("Swap")
        self.m_disk = Meter("Disco da imagem")
        for w in (self.m_build, self.m_ram, self.m_swap, self.m_disk):
            res.lay.addWidget(w)
        self.cpu = QLabel()
        self.cpu.setObjectName("dim")
        res.lay.addWidget(self.cpu)
        lv.addWidget(res)
        lv.addStretch()
        left.setMinimumWidth(300)
        left.setMaximumWidth(380)
        split.addWidget(left)

        # coluna direita: pacote atual + abas
        right = QWidget()
        rv = QVBoxLayout(right)
        rv.setContentsMargins(0, 0, 0, 0)
        rv.setSpacing(12)
        cur = Card("A compilar agora")
        row = QHBoxLayout()
        self.cur_spin = QLabel()
        self.cur_spin.setObjectName("spin")
        self.cur_name = QLabel("—")
        self.cur_name.setObjectName("big")
        self.cur_time = QLabel()
        self.cur_time.setObjectName("bigdim")
        row.addWidget(self.cur_spin)
        row.addWidget(self.cur_name)
        row.addStretch()
        row.addWidget(self.cur_time)
        cur.lay.addLayout(row)
        self.cur_info = QLabel()
        self.cur_info.setObjectName("dim")
        self.cur_info.setWordWrap(True)
        cur.lay.addWidget(self.cur_info)
        rv.addWidget(cur)

        self.tabs = QTabWidget()
        # log
        logw = QWidget()
        lw = QVBoxLayout(logw)
        lw.setContentsMargins(0, 8, 0, 0)
        bar = QHBoxLayout()
        bar.setContentsMargins(4, 0, 8, 0)
        self.log_title = QLabel()
        self.log_title.setObjectName("dim")
        self.follow = QCheckBox("Seguir o fim")
        self.follow.setChecked(True)
        self.back_btn = QPushButton("Voltar ao atual")
        self.back_btn.clicked.connect(self.follow_current)
        self.back_btn.hide()
        bar.addWidget(self.log_title)
        bar.addStretch()
        bar.addWidget(self.back_btn)
        bar.addWidget(self.follow)
        lw.addLayout(bar)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        mono = QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont)
        mono.setPointSizeF(max(8.5, mono.pointSizeF() - 0.5))
        self.log.setFont(mono)
        self.log.setMaximumBlockCount(2000)
        lw.addWidget(self.log)
        self.tabs.addTab(logw, "Log ao vivo")
        # pacotes
        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["", "Pacote", "Fase", "Duração"])
        self.tree.setRootIsDecorated(True)
        self.tree.setUniformRowHeights(True)
        hdr = self.tree.header()
        hdr.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        hdr.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        hdr.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        hdr.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        self.tree.itemDoubleClicked.connect(self.pick_package)
        self.tabs.addTab(self.tree, "Pacotes")
        rv.addWidget(self.tabs, 1)
        split.addWidget(right)
        split.setStretchFactor(1, 1)
        split.setSizes([330, 850])

        # botões
        bb = QHBoxLayout()
        self.btn_log = QPushButton(QIcon.fromTheme("document-open"), "Abrir log")
        self.btn_log.clicked.connect(self.open_log)
        self.btn_folder = QPushButton(QIcon.fromTheme("folder-open"), "Pasta dos logs")
        self.btn_folder.clicked.connect(lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(str(LOGS))))
        self.btn_stop = QPushButton(QIcon.fromTheme("media-playback-stop"), "Parar build")
        self.btn_stop.clicked.connect(self.stop_build)
        self.btn_resume = QPushButton(QIcon.fromTheme("media-playback-start"), "Retomar build")
        self.btn_resume.setObjectName("primary")
        self.btn_resume.clicked.connect(self.resume_build)
        bb.addWidget(self.btn_log)
        bb.addWidget(self.btn_folder)
        bb.addStretch()
        self.hint = QLabel()
        self.hint.setObjectName("dim")
        bb.addWidget(self.hint)
        bb.addWidget(self.btn_stop)
        bb.addWidget(self.btn_resume)
        v.addLayout(bb)

        # árvore de pacotes (uma vez)
        for key, label, ids in self.m.phases:
            parent = QTreeWidgetItem(self.tree, ["", label, "", ""])
            f = parent.font(1)
            f.setBold(True)
            parent.setFont(1, f)
            parent.setFirstColumnSpanned(False)
            for pid in ids:
                it = QTreeWidgetItem(parent, ["·", nice(pid), key, ""])
                it.setToolTip(1, pid)
                it.setData(0, Qt.ItemDataRole.UserRole, pid)
                self.items[pid] = it
            parent.setData(0, Qt.ItemDataRole.UserRole + 1, key)

    # ---------- ações
    def pick_package(self, item, _col):
        pid = item.data(0, Qt.ItemDataRole.UserRole)
        if pid and (LOGS / f"{pid}.log").exists():
            self.selected_log = pid
            self.back_btn.show()
            self.tabs.setCurrentIndex(0)
            self.refresh_log(force=True)

    def follow_current(self):
        self.selected_log = None
        self.back_btn.hide()
        self.refresh_log(force=True)

    def open_log(self):
        pid = self.selected_log or self.current
        if pid:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(LOGS / f"{pid}.log")))

    def stop_build(self):
        if QMessageBox.question(self, "Parar o build",
                                "Parar o build da Nexora?\n\nO pacote a meio perde-se, mas tudo o que "
                                "já está feito fica. Depois é só carregar em Retomar.") \
                != QMessageBox.StandardButton.Yes:
            return
        subprocess.Popen(["systemctl", "stop", UNIT])   # o polkit do KDE pede a senha

    def pending_phases(self, done):
        out = []
        for key, _, ids in self.m.phases:
            if key in CHROOT_PHASES and any(i not in done for i in ids):
                out.append(key)
        return out

    def resume_build(self):
        mounted, done, _, _ = self.m.snapshot()
        phases = self.pending_phases(done)
        if not phases:
            QMessageBox.information(self, "Nada a fazer", "Todas as fases estão completas. 🎉")
            return
        if QMessageBox.question(self, "Retomar o build",
                                "Relançar estas fases (o que já está feito é saltado):\n\n  " +
                                "  →  ".join(phases)) != QMessageBox.StandardButton.Yes:
            return
        subprocess.Popen(["pkexec", str(SCRIPTS / "build-bg.sh"), *phases])

    def tray_clicked(self, reason):
        if reason in (QSystemTrayIcon.ActivationReason.Trigger, QSystemTrayIcon.ActivationReason.DoubleClick):
            self.toggle_window()

    def toggle_window(self):
        if self.isVisible() and not self.isMinimized():
            self.hide()
        else:
            self.showNormal()
            self.raise_()
            self.activateWindow()

    def quit_app(self):
        self.quitting = True
        QApplication.quit()

    def closeEvent(self, ev):
        # fechar a janela deixa o monitor no painel; "Sair do monitor" no menu do símbolo fecha mesmo
        if self.tray and not self.quitting:
            ev.ignore()
            self.hide()
            if not getattr(self, "_told_tray", False):
                self._told_tray = True
                self.tray.showMessage("Nexora Build", "Continuo no painel, junto ao relógio. "
                                      "Clica no símbolo para voltar.", QIcon(str(ICON)), 4000)
        else:
            ev.accept()

    def showEvent(self, ev):
        if self.tray:
            self.act_toggle.setText("Esconder janela")
        super().showEvent(ev)

    def hideEvent(self, ev):
        if self.tray:
            self.act_toggle.setText("Mostrar janela")
        super().hideEvent(ev)

    def notify(self, title, body, urgent=False):
        try:
            subprocess.Popen(["notify-send", "-a", "Nexora Build", "-i", str(ICON),
                              "-u", "critical" if urgent else "normal", title, body])
        except Exception:
            pass

    # ---------- atualização
    def refresh(self, full=False):
        self.tick_n += 1
        if full or self.tick_n % 20 == 0:
            self.m.load_scripts()
        if full or self.tick_n % 2 == 0:
            self.m.read_journal()
        svc = self.m.service()
        active = svc.get("ActiveState") == "active"
        result = svc.get("Result", "")
        mounted, done, logs, cached_at = self.m.snapshot()

        # pacote atual: o último 🔨 do journal ainda sem ✔/✘; senão o log mais recente sem .done
        cur = None
        if active and self.m.last_start and self.m.last_start != self.m.last_closed \
                and self.m.last_start not in done:
            cur = self.m.last_start
        if not cur:
            cands = [i for i in self.m.order if i in logs and i not in done]
            if cands and mounted:
                cands.sort(key=lambda i: (LOGS / f"{i}.log").stat().st_mtime)
                cur = cands[-1]
            elif cands:
                cur = cands[0]
        self.current = cur
        n_done = sum(1 for i in self.m.order if i in done)
        total = len(self.m.order)
        self.total.setRange(0, total)
        self.total.setValue(n_done)

        # estado geral
        if active:
            status, color = "A compilar", ACCENT
        elif self.current and result not in ("", "success"):
            status, color = "Falhou", "#e5534b"
        elif self.current:
            status, color = "Parado", "#8b949e"
        elif n_done == total:
            status, color = "Completo", "#3fb950"
        else:
            status, color = "Parado", "#8b949e"
        self.pill.setText(f"  {status}  ")
        self.pill.setStyleSheet(f"#pill {{ background:{color}; color:white; border-radius:11px; "
                                f"padding:3px 6px; font-weight:600; }}")
        self.btn_stop.setEnabled(active)
        self.btn_resume.setEnabled(not active)

        # subtítulo
        ph_cur = self.m.phase_of.get(self.current) if self.current else None
        label = dict((k, l) for k, l, _ in PHASES).get(ph_cur, "")
        if not mounted:
            age = time.strftime("%H:%M", time.localtime(cached_at)) if cached_at else "?"
            self.subtitle.setText(f"Imagem desmontada · último estado às {age}")
        else:
            self.subtitle.setText(label or ("Tudo compilado" if n_done == total else "À espera"))
        if active and svc.get("ExecMainStartTimestamp"):
            try:
                t0 = time.mktime(time.strptime(" ".join(svc["ExecMainStartTimestamp"].split()[1:3]),
                                               "%Y-%m-%d %H:%M:%S"))
                self.clock.setText(f"build a correr há {hms(time.time() - t0)}   ")
            except Exception:
                self.clock.setText("")
        else:
            self.clock.setText("")

        # fases
        for key, _, ids in self.m.phases:
            n = sum(1 for i in ids if i in done)
            self.phase_rows[key].set(n, len(ids), key == ph_cur)

        # pacote atual
        if self.current:
            t0 = self.m.starts.get(self.current) or self.m.first_seen.setdefault(self.current, time.time())
            self.cur_name.setText(nice(self.current))
            if active:
                self.cur_spin.setText(self.SPIN[self.tick_n % 4])
                self.cur_time.setText(hms(time.time() - t0))
                self.cur_info.setText(f"{self.current} · {label}")
            else:
                self.cur_spin.setText("✘" if status == "Falhou" else "⏸")
                self.cur_time.setText("")
                why = "falhou — vê o log abaixo" if status == "Falhou" else "parado a meio, retoma quando quiseres"
                self.cur_info.setText(f"{self.current} · {why}")
            ids_of = {k: ids for k, _, ids in self.m.phases}
            chain = svc.get("chain") or [k for k, _, _ in self.m.phases]
            seq = list(ids_of.get(ph_cur, []))
            if ph_cur in chain:
                for k in chain[chain.index(ph_cur) + 1:]:
                    seq += ids_of.get(k, [])
            after = seq[seq.index(self.current) + 1:] if self.current in seq else []
            nxt = [nice(i) for i in after if i not in done][:3]
            if nxt:
                self.cur_info.setText(self.cur_info.text() + "   ·   a seguir: " + ", ".join(nxt))
        else:
            self.cur_spin.setText("✔" if n_done == total else "")
            self.cur_name.setText("Nada a compilar" if n_done != total else "Tudo pronto")
            self.cur_time.setText("")
            self.cur_info.setText("")

        # lista de pacotes
        for pid, it in self.items.items():
            if pid in done:
                sym, col = "✔", QColor("#3fb950")
            elif pid == self.current:
                sym, col = (self.SPIN[self.tick_n % 4], QColor(ACCENT)) if active else \
                           (("✘", QColor("#e5534b")) if status == "Falhou" else ("⏸", QColor("#d29922")))
            else:
                sym, col = "·", self.palette().color(QPalette.ColorRole.PlaceholderText)
            it.setText(0, sym)
            it.setForeground(0, col)
            d = self.m.durations.get(pid)
            if pid == self.current and active:
                it.setText(3, hms(time.time() - (self.m.starts.get(pid) or time.time())))
            else:
                it.setText(3, hms(d) if d is not None else "")
        for i in range(self.tree.topLevelItemCount()):
            top = self.tree.topLevelItem(i)
            key = top.data(0, Qt.ItemDataRole.UserRole + 1)
            ids = [top.child(j).data(0, Qt.ItemDataRole.UserRole) for j in range(top.childCount())]
            n = sum(1 for x in ids if x in done)
            top.setText(2, f"{n}/{len(ids)}")
            top.setText(0, "✔" if n == len(ids) and ids else ("●" if key == ph_cur else ""))
            if full:
                top.setExpanded(key == ph_cur)

        self.refresh_resources()
        self.refresh_log()

        # notificações: fim de fase e fim do serviço
        if self.prev_events is not None and len(self.m.events) > self.prev_events:
            for _, txt in self.m.events[self.prev_events:]:
                self.notify("Nexora Linux", txt)
        self.prev_events = len(self.m.events)
        if self.prev_status is not None and status != self.prev_status:
            if status == "Falhou":
                self.notify("Build da Nexora falhou", f"Parou em {self.current}", urgent=True)
            elif status == "Completo":
                self.notify("Build da Nexora completo", "Está tudo compilado. 🎉")
        self.prev_status = status

        # símbolo do painel e da janela
        frac = n_done / total if total else 0
        key = (status, int(frac * 100))
        if key != self.icon_key:
            self.icon_key = key
            ic = status_icon(status, frac)
            self.setWindowIcon(ic)
            if self.tray:
                self.tray.setIcon(ic)
        if self.tray:
            now = f"{nice(self.current)} há {self.cur_time.text()}" if (self.current and active) else \
                  (nice(self.current) if self.current else "")
            self.tray.setToolTip(f"Nexora Build — {status}\n{now}\n{n_done}/{total} pacotes · {int(frac * 100)}%")
            self.act_stop.setEnabled(active)
            self.act_resume.setEnabled(not active)

        self.hint.setText("" if active else ("Retomar relança: " + " → ".join(self.pending_phases(done))
                                             if self.pending_phases(done) else ""))

    def refresh_resources(self):
        r = self.m.resources()
        if "b_cur" in r:
            lim = r.get("b_max") or r["ram_total"]
            high = r.get("b_high")
            txt = f"{r['b_cur'] / 2**30:.1f} / {gib(lim)}"
            self.m_build.set(r["b_cur"] / lim, txt, warn=bool(high and r["b_cur"] >= high * 0.95))
        else:
            self.m_build.set(0, "serviço parado")
        self.m_ram.set(r["ram_used"] / r["ram_total"], f"{gib(r['ram_used'])} de {gib(r['ram_total'])}",
                       warn=r["ram_used"] / r["ram_total"] > 0.9)
        if r["swap_total"]:
            self.m_swap.set(r["swap_used"] / r["swap_total"], f"{gib(r['swap_used'])} de {gib(r['swap_total'])}",
                            warn=r["swap_used"] / r["swap_total"] > 0.8)
        if "disk" in r:
            u, t = r["disk"]
            self.m_disk.set(u / t, f"{gib(u)} de {gib(t)}")
        else:
            self.m_disk.set(0, "desmontado")
        cores = r.get("cores")
        self.cpu.setText((f"CPU do build: {cores:.1f} de {os.cpu_count()} núcleos   ·   " if cores is not None else "")
                         + f"load {r['load']}")

    def refresh_log(self, force=False):
        pid = self.selected_log or self.current
        if not pid:
            self.log_title.setText("")
            return
        f = LOGS / f"{pid}.log"
        self.log_title.setText(f"{pid}.log" + ("  (escolhido)" if self.selected_log else ""))
        try:
            size = f.stat().st_size
            with open(f, "rb") as fh:
                fh.seek(max(0, size - 96 * 1024))
                data = fh.read().decode("utf-8", "replace")
        except Exception:
            return
        lines = ANSI.sub("", data).splitlines()[-400:]
        text = "\n".join(lines)
        if not force and text == getattr(self, "_last_log", None):
            return
        self._last_log = text
        sb = self.log.verticalScrollBar()
        at_end = sb.value() >= sb.maximum() - 4
        old = sb.value()
        self.log.setPlainText(text)
        if self.follow.isChecked() and (at_end or force):
            self.log.moveCursor(QTextCursor.MoveOperation.End)
            sb.setValue(sb.maximum())
        elif not self.follow.isChecked():
            sb.setValue(min(old, sb.maximum()))
        else:
            sb.setValue(sb.maximum())


STYLE = f"""
QLabel#title {{ font-size: 18pt; font-weight: 700; }}
QLabel#big {{ font-size: 16pt; font-weight: 600; }}
QLabel#bigdim {{ font-size: 14pt; color: palette(placeholder-text); }}
QLabel#spin {{ font-size: 16pt; color: {ACCENT}; min-width: 22px; }}
QLabel#dim {{ color: palette(placeholder-text); }}
QLabel#cardTitle {{ color: palette(placeholder-text); font-size: 8pt; font-weight: 700; letter-spacing: 1px; }}
QFrame#card {{ background: palette(base); border: 1px solid palette(mid); border-radius: 10px; }}
QProgressBar {{ border: none; border-radius: 3px; background: rgba(128,128,128,0.22); }}
QProgressBar::chunk {{ border-radius: 3px; background: {ACCENT}; }}
QProgressBar[complete="1"]::chunk {{ background: #3fb950; }}
QProgressBar[warn="1"]::chunk {{ background: #d29922; }}
QProgressBar#total {{ border-radius: 8px; font-weight: 600; text-align: center;
    background: rgba(128,128,128,0.22); }}
QProgressBar#total::chunk {{ border-radius: 8px; background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
    stop:0 #1098ad, stop:1 {ACCENT}); }}
QPushButton#primary {{ font-weight: 600; }}
QPlainTextEdit {{ border-radius: 8px; }}
"""


def main():
    QApplication.setDesktopFileName("nexora-monitor")
    app = QApplication(sys.argv)
    app.setApplicationName("Nexora Build")
    app.setWindowIcon(QIcon(str(ICON)))
    app.setStyleSheet(STYLE)
    app.setQuitOnLastWindowClosed(False)
    w = Window()
    if "--hidden" in sys.argv and w.tray:
        w.hide()
    else:
        w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
