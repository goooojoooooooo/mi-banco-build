"""Genera el icono de la app (1024x1024, sin alfa, sin esquinas: iOS aplica la máscara).

Marca negra de titanio (la del prototipo de movimiento): cuerpo negro puro con un degradado vertical
#18181B -> #070708 (55 %) -> #000, la ola "M4 16c3-6 5-6 8-2s5 4 8-2" (caja de 24) con degradado de titanio
#FFFFFF -> #D7DADF (45 %) -> #9DA2AA (75 %) -> #F3F4F6 y un canto fino de luz (2,2/120 del ancho, a 1/120 del borde,
sobre la esquina de iOS 26/120) para que el icono se lea sobre fondos oscuros y claros.

Variantes para iOS 18+: oscuro (idéntica) y tintada (grises sobre negro: iOS la tiñe).

Uso: python tools/make_icon.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supermuestreo para bordes suaves
UNIT = SIZE / 120  # píxeles por unidad de la caja de 120
OUT = Path(__file__).resolve().parent.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"

EDGE_INSET = 1.0 * UNIT          # separación del canto al borde
EDGE_WIDTH = 2.2 * UNIT          # grosor del canto
CORNER = 26.0 * UNIT             # esquina de iOS en el prototipo (26/120)
# La ola: caja de 24 unidades a escala 3,2 y desplazada (21,6; 15,2) dentro de la caja de 120, como en el prototipo.
WAVE_SCALE = 3.2 * UNIT
WAVE_ORIGIN = (21.6 * UNIT, 15.2 * UNIT)
WAVE_STROKE = 1.9 * WAVE_SCALE


def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def ramp(t: np.ndarray, stops) -> np.ndarray:
    """Degradado por tramos: stops = [(posición, '#rrggbb', alfa)] -> array (..., 4) con color y alfa por separado."""
    pos = np.array([s[0] for s in stops])
    out = np.zeros(t.shape + (4,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, [hex_rgb(s[1])[c] for s in stops])
    out[..., 3] = np.interp(t, pos, [s[2] for s in stops])
    return out


def cubic(p0, p1, p2, p3, steps=600):
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        yield (
            u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
        )


def wave_points():
    # M4 16 c3-6 5-6 8-2 s5 4 8-2  (la "s" refleja el segundo control: (9,10) respecto a (12,14) -> (15,18))
    pts = list(cubic((4, 16), (7, 10), (9, 10), (12, 14)))
    pts += list(cubic((12, 14), (15, 18), (17, 18), (20, 12)))
    return pts


def to_px(p):
    return (WAVE_ORIGIN[0] + p[0] * WAVE_SCALE, WAVE_ORIGIN[1] + p[1] * WAVE_SCALE)


def mask_from_draw(fn) -> np.ndarray:
    """Máscara 0..1 a 1024 dibujada a 4x y reducida."""
    big = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    fn(ImageDraw.Draw(big))
    return np.asarray(big.resize((SIZE, SIZE), Image.Resampling.LANCZOS), dtype=np.float64) / 255


def wave_mask() -> np.ndarray:
    r = WAVE_STROKE / 2 * SS

    def draw(d):
        for p in wave_points():
            x, y = (v * SS for v in to_px(p))
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return mask_from_draw(draw)


def edge_mask() -> np.ndarray:
    """Anillo de 2,2/120 centrado a 1/120 + 1,1/120 del borde, sobre la esquina de iOS."""
    mid = EDGE_INSET + EDGE_WIDTH / 2
    outer, inner = mid - EDGE_WIDTH / 2, mid + EDGE_WIDTH / 2

    def draw(d):
        d.rounded_rectangle((outer * SS, outer * SS, (SIZE - outer) * SS - 1, (SIZE - outer) * SS - 1),
                            radius=(CORNER - EDGE_INSET + 0) * SS + 0, fill=255)
        d.rounded_rectangle((inner * SS, inner * SS, (SIZE - inner) * SS - 1, (SIZE - inner) * SS - 1),
                            radius=(CORNER - EDGE_INSET - EDGE_WIDTH) * SS, fill=0)
    return mask_from_draw(draw)


def body_mask() -> np.ndarray:
    """La pieza (esquina de iOS); fuera de ella, negro puro."""
    def draw(d):
        d.rounded_rectangle((0, 0, SIZE * SS - 1, SIZE * SS - 1), radius=CORNER * SS, fill=255)
    return mask_from_draw(draw)


def body_image() -> np.ndarray:
    y = (np.mgrid[0:SIZE, 0:SIZE][0] + 0.5) / SIZE
    rgba = ramp(y, [(0, "#18181B", 1), (0.55, "#070708", 1), (1, "#000000", 1)])
    return rgba[..., :3] * body_mask()[..., None]


def over(base: np.ndarray, rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    return base * (1 - alpha[..., None]) + rgb * alpha[..., None]


def wave_gradient() -> np.ndarray:
    """Degradado de la ola (x1=0,y1=0 -> x2=1,y2=0,35 en la caja de la ola, como el SVG)."""
    pts = [to_px(p) for p in wave_points()]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    nx, ny = (xx + 0.5 - x0) / (x1 - x0), (yy + 0.5 - y0) / (y1 - y0)
    dx, dy = 1.0, 0.35
    t = np.clip((nx * dx + ny * dy) / (dx * dx + dy * dy), 0, 1)
    return ramp(t, [(0, "#FFFFFF", 1), (0.45, "#D7DADF", 1), (0.75, "#9DA2AA", 1), (1, "#F3F4F6", 1)])[..., :3]


def edge_gradient() -> np.ndarray:
    """Degradado diagonal del canto, con su opacidad (blanco 85 % -> plata 30 % -> gris 18 % -> claro 65 %)."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    t = np.clip(((xx + 0.5) + (yy + 0.5)) / (2 * SIZE), 0, 1)
    return ramp(t, [(0, "#FFFFFF", 0.85), (0.32, "#A9ADB3", 0.30), (0.68, "#6B6F75", 0.18), (1, "#E9EBEE", 0.65)])


def titanium_icon() -> Image.Image:
    img = body_image()
    e = edge_gradient()
    img = over(img, e[..., :3], e[..., 3] * edge_mask())
    img = over(img, wave_gradient(), wave_mask())
    return Image.fromarray(np.clip(img.round(), 0, 255).astype(np.uint8), "RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    light = titanium_icon()
    dark = light.copy()
    tinted = light.convert("L").convert("RGB")

    for name, img in (("icon.png", light), ("icon-dark.png", dark), ("icon-tinted.png", tinted)):
        assert img.mode == "RGB" and img.size == (SIZE, SIZE)
        img.save(OUT / name, "PNG", optimize=True)
        print("ok", name)


if __name__ == "__main__":
    main()
