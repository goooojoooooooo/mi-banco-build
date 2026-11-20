"""Comprueba el icono negro de titanio generado por tools/make_icon.py.

Uso: python tools/test_make_icon.py   (tras python tools/make_icon.py)

Mide los tres PNG del conjunto AppIcon: cuerpo negro puro, ola clara, canto fino de titanio y sin canal alfa.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ICONS = Path(__file__).resolve().parent.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"
NAMES = ("icon.png", "icon-dark.png", "icon-tinted.png")
SIZE = 1024
# Canto: 1/120 de inset y 2,2/120 de grosor sobre la esquina de iOS (26/120) -> su línea central queda a ~9,4 px del borde.
EDGE_INSET = 1 / 120 * SIZE + 1.1 / 120 * SIZE
EDGE_RADIUS = 26 / 120 * SIZE


def luminance(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def edge_ring_samples(lum: np.ndarray, inset: float, radius: float, steps: int = 2000) -> np.ndarray:
    """Luminancia a lo largo de un rectángulo redondeado inscrito a `inset` px del borde."""
    lo, hi = inset, SIZE - 1 - inset
    r = radius - inset
    pts = []
    straight = hi - lo - 2 * r
    arc = math.pi / 2 * r
    total = 4 * straight + 4 * arc
    for i in range(steps):
        d = total * i / steps
        seg = straight + arc
        side, d = divmod(d, seg)
        if d < straight:
            u = lo + r + d
            pts.append([(u, lo), (hi, u), (SIZE - 1 - u, hi), (lo, SIZE - 1 - u)][int(side)])
        else:
            a = (d - straight) / r  # 0..pi/2
            cx = [hi - r, hi - r, lo + r, lo + r][int(side)]
            cy = [lo + r, hi - r, hi - r, lo + r][int(side)]
            base = [-math.pi / 2, 0, math.pi / 2, math.pi][int(side)]
            pts.append((cx + r * math.cos(base + a), cy + r * math.sin(base + a)))
    return np.array([lum[int(round(y)), int(round(x))] for x, y in pts])


def check(name: str) -> list[str]:
    errors = []
    img = Image.open(ICONS / name)
    if img.mode != "RGB":
        errors.append(f"{name}: modo {img.mode}, debe ser RGB (sin alfa)")
    if img.size != (SIZE, SIZE):
        errors.append(f"{name}: tamaño {img.size}")
        return errors
    lum = luminance(img)
    for x, y in ((40, 40), (512, 980)):
        if lum[y, x] >= 14:
            errors.append(f"{name}: píxel ({x}, {y}) con luminancia {lum[y, x]:.1f}, debe ser < 14 (negro)")
    wave = lum[512, 300:725].max()
    if wave <= 215:
        errors.append(f"{name}: la ola llega a {wave:.1f} en la fila 512, debe superar 215")
    ring = edge_ring_samples(lum, EDGE_INSET, EDGE_RADIUS).mean()
    if not 40 <= ring <= 150:
        errors.append(f"{name}: el canto mide {ring:.1f}, debe estar entre 40 y 150")
    return errors


def main() -> int:
    errors = []
    for name in NAMES:
        errors += check(name)
    for e in errors:
        print("FALLO", e)
    if errors:
        return 1
    print("ok: icono negro con canto de titanio (", ", ".join(NAMES), ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
