#!/usr/bin/env python3
"""Wallpaper "aurora" da Nexora: manchas de luz suaves (ciano, índigo, violeta) sobre azul-noite,
um véu de hexágonos quase invisível e um grão fino (para não haver bandas no degradê).

Uso: python3 make_wallpaper_aurora.py <saida.png> [largura altura]
"""
import math
import random
import sys

from PyQt6.QtCore import QPointF, Qt
from PyQt6.QtGui import QColor, QGuiApplication, QImage, QLinearGradient, QPainter, QPainterPath, QPen, QRadialGradient


def blob(p, x, y, r, color, alpha):
    g = QRadialGradient(QPointF(x, y), r)
    c = QColor(color)
    for stop, a in ((0.0, alpha), (0.35, alpha * 0.6), (0.7, alpha * 0.18), (1.0, 0)):
        c.setAlpha(int(a))
        g.setColorAt(stop, QColor(c))
    p.setBrush(g)
    p.setPen(Qt.PenStyle.NoPen)
    p.drawEllipse(QPointF(x, y), r, r)


def hexagon(cx, cy, r):
    path = QPainterPath()
    for i in range(6):
        a = math.radians(-30 + 60 * i)
        pt = QPointF(cx + r * math.cos(a), cy + r * math.sin(a))
        path.moveTo(pt) if i == 0 else path.lineTo(pt)
    path.closeSubpath()
    return path


def main():
    out = sys.argv[1]
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (3840, 2160)
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    img = QImage(w, h, QImage.Format.Format_ARGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)

    base = QLinearGradient(0, 0, w, h)
    base.setColorAt(0, QColor("#06111d"))
    base.setColorAt(0.55, QColor("#040912"))
    base.setColorAt(1, QColor("#020409"))
    p.fillRect(img.rect(), base)

    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_Screen)
    blob(p, w * 0.16, h * 0.92, w * 0.46, "#12c8e6", 215)   # ciano vivo (canto inferior esquerdo)
    blob(p, w * 0.30, h * 0.62, w * 0.22, "#22b8cf", 120)   # brilho ciano
    blob(p, w * 0.66, h * 0.10, w * 0.36, "#4c6ef5", 175)   # índigo (cima)
    blob(p, w * 0.95, h * 0.80, w * 0.34, "#ae3ec9", 165)   # violeta (direita)
    blob(p, w * 0.80, h * 0.45, w * 0.18, "#5f3dc4", 90)    # ponte índigo-violeta
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceOver)

    # véu de hexágonos, mais visível onde há luz
    r = h / 16
    dx, dy = r * math.sqrt(3), r * 1.5
    p.setBrush(Qt.BrushStyle.NoBrush)
    for row in range(int(h / dy) + 2):
        for col in range(int(w / dx) + 2):
            cx = col * dx + (dx / 2 if row % 2 else 0)
            cy = row * dy
            d = math.hypot(cx - w * 0.2, cy - h * 0.85) / w
            a = max(0, int(22 - d * 26))
            if a:
                p.setPen(QPen(QColor(150, 230, 245, a), max(1.0, h / 1440)))
                p.drawPath(hexagon(cx, cy, r * 0.96))

    # vinheta suave
    vg = QRadialGradient(QPointF(w / 2, h / 2), max(w, h) * 0.75)
    vg.setColorAt(0.6, QColor(0, 0, 0, 0))
    vg.setColorAt(1.0, QColor(0, 0, 0, 120))
    p.fillRect(img.rect(), vg)
    p.end()

    # grão fino (quebra as bandas de cor dos degradês)
    rnd = random.Random(7)
    noise = QImage(256, 256, QImage.Format.Format_ARGB32)
    for y in range(256):
        for x in range(256):
            v = rnd.randint(0, 255)
            noise.setPixelColor(x, y, QColor(v, v, v, 7))
    p = QPainter(img)
    p.setCompositionMode(QPainter.CompositionMode.CompositionMode_Overlay)
    for y in range(0, h, 256):
        for x in range(0, w, 256):
            p.drawImage(x, y, noise)
    p.end()

    img.convertToFormat(QImage.Format.Format_RGB32).save(out, quality=95)
    print(f"✔ {out} ({w}x{h})")


if __name__ == "__main__":
    main()
