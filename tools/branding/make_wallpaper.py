#!/usr/bin/env python3
"""Gera o wallpaper da Nexora Linux (PNG) com Qt, sem precisar de SVG no sistema alvo.

Uso: python3 make_wallpaper.py <saida.png> [largura altura]
"""
import math
import sys

from PyQt6.QtCore import QPointF, QRectF, Qt
from PyQt6.QtGui import (QColor, QFont, QGuiApplication, QImage, QLinearGradient, QPainter, QPainterPath,
                         QPen, QRadialGradient)


def hexagon(cx, cy, r, rot=-90):
    path = QPainterPath()
    for i in range(6):
        a = math.radians(rot + 60 * i)
        p = QPointF(cx + r * math.cos(a), cy + r * math.sin(a))
        path.moveTo(p) if i == 0 else path.lineTo(p)
    path.closeSubpath()
    return path


def main():
    out = sys.argv[1]
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (2560, 1440)
    app = QGuiApplication(sys.argv[:1])  # noqa: F841 (precisa de existir para as fontes)
    img = QImage(w, h, QImage.Format.Format_RGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)

    # fundo: azul-noite com um brilho ciano à esquerda
    g = QLinearGradient(0, 0, w, h)
    g.setColorAt(0, QColor("#0b1622"))
    g.setColorAt(1, QColor("#070b12"))
    p.fillRect(img.rect(), g)
    glow = QRadialGradient(QPointF(w * 0.30, h * 0.55), w * 0.55)
    glow.setColorAt(0, QColor(34, 184, 207, 70))
    glow.setColorAt(1, QColor(34, 184, 207, 0))
    p.fillRect(img.rect(), glow)

    # padrão de hexágonos muito subtil
    r = h / 22
    dx, dy = r * math.sqrt(3), r * 1.5
    p.setBrush(Qt.BrushStyle.NoBrush)
    for row in range(int(h / dy) + 2):
        for col in range(int(w / dx) + 2):
            cx = col * dx + (dx / 2 if row % 2 else 0)
            cy = row * dy
            d = math.hypot(cx - w * 0.30, cy - h * 0.55) / w
            alpha = max(0, int(26 - d * 40))
            if alpha:
                p.setPen(QPen(QColor(120, 210, 230, alpha), 1.2))
                p.drawPath(hexagon(cx, cy, r * 0.94, rot=-30))

    # logo grande: hexágono com o N
    cx, cy, R = w * 0.30, h * 0.55, h * 0.20
    lg = QLinearGradient(cx - R, cy - R, cx + R, cy + R)
    lg.setColorAt(0, QColor("#22b8cf"))
    lg.setColorAt(1, QColor("#0b6e8a"))
    p.setPen(Qt.PenStyle.NoPen)
    p.setBrush(QColor(34, 184, 207, 40))
    p.drawPath(hexagon(cx, cy, R * 1.12))
    p.setBrush(lg)
    p.drawPath(hexagon(cx, cy, R))
    # o "N" (mesma geometria do ícone, escalada de 64x64)
    s = R / 29
    ox, oy = cx - 32 * s, cy - 32 * s
    n = QPainterPath()
    pts = [(21, 44), (21, 20), (25.6, 20), (38.8, 36.4), (38.8, 20), (43, 20), (43, 44), (38.4, 44),
           (25.2, 27.6), (25.2, 44)]
    n.moveTo(ox + pts[0][0] * s, oy + pts[0][1] * s)
    for x, y in pts[1:]:
        n.lineTo(ox + x * s, oy + y * s)
    n.closeSubpath()
    p.setBrush(QColor("white"))
    p.drawPath(n)

    # nome
    f = QFont("DejaVu Sans", int(h * 0.075))
    f.setWeight(QFont.Weight.Light)
    f.setLetterSpacing(QFont.SpacingType.PercentageSpacing, 118)
    p.setFont(f)
    p.setPen(QColor(230, 245, 250))
    tx = cx + R * 1.45
    p.drawText(QRectF(tx, cy - h * 0.085, w - tx, h * 0.12), Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, "NEXORA")
    f2 = QFont("DejaVu Sans", int(h * 0.022))
    f2.setLetterSpacing(QFont.SpacingType.PercentageSpacing, 140)
    p.setFont(f2)
    p.setPen(QColor(34, 184, 207, 220))
    p.drawText(QRectF(tx + h * 0.006, cy + h * 0.035, w - tx, h * 0.05),
               Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter, "L I N U X")
    p.end()
    img.save(out, quality=95)
    print(f"✔ {out} ({w}x{h})")


if __name__ == "__main__":
    main()
