#!/usr/bin/env python3
"""Mais fundos da Nexora (variações da "aurora") e o fundo do ecrã de login.

Uso: python3 make_wallpaper_set.py <pasta_de_saida> [largura altura]
Gera: nexora-dusk.png, nexora-tide.png, nexora-graphite.png, nexora-login.png
"""
import os
import random
import sys

from PyQt6.QtCore import QPointF, Qt
from PyQt6.QtGui import QColor, QGuiApplication, QImage, QLinearGradient, QPainter, QRadialGradient

SETS = {
    # nome: (fundo [3 cores], manchas [(x, y, raio, cor, alfa)], vinheta)
    "nexora-dusk": (("#140a1c", "#0b0712", "#050308"),
                    [(0.18, 0.95, 0.48, "#ff6b3d", 200), (0.42, 0.70, 0.22, "#ff8f5a", 90),
                     (0.70, 0.12, 0.38, "#7b5cff", 175), (0.96, 0.78, 0.34, "#d6336c", 160)], 130),
    "nexora-tide": (("#04151a", "#030d11", "#010608"),
                    [(0.12, 0.88, 0.46, "#12b886", 190), (0.36, 0.58, 0.22, "#22b8cf", 120),
                     (0.72, 0.10, 0.36, "#1c7ed6", 160), (0.94, 0.86, 0.30, "#0ca678", 120)], 130),
    "nexora-graphite": (("#111418", "#0b0d10", "#060708"),
                        [(0.20, 0.90, 0.44, "#495057", 160), (0.70, 0.15, 0.36, "#22b8cf", 70),
                         (0.92, 0.80, 0.30, "#7b5cff", 60)], 110),
    "nexora-login": (("#050d16", "#03070d", "#010306"),
                     [(0.14, 0.94, 0.50, "#12c8e6", 150), (0.66, 0.06, 0.38, "#4c6ef5", 120),
                      (0.96, 0.84, 0.36, "#ae3ec9", 120), (0.50, 0.50, 0.30, "#0b2235", 90)], 160),
}


def blob(p, x, y, r, color, alpha):
    g = QRadialGradient(QPointF(x, y), r)
    c = QColor(color)
    for stop, a in ((0.0, alpha), (0.35, alpha * 0.6), (0.7, alpha * 0.18), (1.0, 0)):
        c.setAlpha(int(a))
        g.setColorAt(stop, QColor(c))
    p.setBrush(g)
    p.setPen(Qt.PenStyle.NoPen)
    p.drawEllipse(QPointF(x, y), r, r)


def make(name, w, h, out):
    base_c, blobs, vig = SETS[name]
    img = QImage(w, h, QImage.Format.Format_ARGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    base = QLinearGradient(0, 0, w, h)
    for stop, c in zip((0, 0.55, 1), base_c):
        base.setColorAt(stop, QColor(c))
    p.fillRect(img.rect(), base)
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_Screen)
    for x, y, r, c, a in blobs:
        blob(p, w * x, h * y, w * r, c, a)
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceOver)
    vg = QRadialGradient(QPointF(w / 2, h / 2), max(w, h) * 0.75)
    vg.setColorAt(0.55, QColor(0, 0, 0, 0))
    vg.setColorAt(1.0, QColor(0, 0, 0, vig))
    p.fillRect(img.rect(), vg)
    p.end()
    # grão fino contra as bandas dos degradês
    rnd = random.Random(11)
    p = QPainter(img)
    for _ in range(w * h // 90):
        v = rnd.randint(0, 255)
        p.setPen(QColor(v, v, v, 6))
        p.drawPoint(rnd.randrange(w), rnd.randrange(h))
    p.end()
    img.save(os.path.join(out, name + ".png"), "PNG")


def main():
    out = sys.argv[1]
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (3840, 2160)
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    os.makedirs(out, exist_ok=True)
    for name in SETS:
        make(name, w, h, out)
        print("✔", name)


if __name__ == "__main__":
    main()
