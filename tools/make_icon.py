"""Genera el icono de Mi Banco (1024x1024, sin alfa, sin esquinas: iOS aplica la máscara).

Marca de la maqueta (.appic): degradado violeta en diagonal (#8B6CFF -> #3B2A86) y la ola
blanca "M4 16c3-6 5-6 8-2s5 4 8-2" (caja de 24) con trazo redondeado, centrada con aire.

Variantes para iOS 18+: oscuro (fondo casi negro, ola lila) y tintado (gris puro sobre negro).

Uso: python tools/make_icon.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supermuestreo para bordes suaves
OUT = Path(__file__).resolve().parent.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"


def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def diagonal_gradient(start: str, end: str, size: int) -> Image.Image:
    """Degradado de arriba-izquierda a abajo-derecha (140 grados en CSS, casi diagonal)."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float64)
    angle = np.deg2rad(140 - 90)  # CSS: 0deg = hacia arriba; aquí, ángulo desde el eje x
    dx, dy = np.cos(angle), np.sin(angle)
    t = (x - size / 2) * dx + (y - size / 2) * dy
    half = abs(size / 2 * dx) + abs(size / 2 * dy)
    t = np.clip((t + half) / (2 * half), 0, 1)[..., None]
    rgb = hex_rgb(start) * (1 - t) + hex_rgb(end) * t
    return Image.fromarray(rgb.round().astype(np.uint8), "RGB")


def cubic(p0, p1, p2, p3, steps=400):
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


def draw_wave(img: Image.Image, color, glyph_fraction=0.52, stroke_units=2.4):
    """Dibuja la ola centrada (por su caja real, incluido el grosor del trazo)."""
    big = img.resize((SIZE * SS, SIZE * SS), Image.Resampling.NEAREST)
    canvas = SIZE * SS
    pts = wave_points()
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    scale = canvas * glyph_fraction / 16  # la ola ocupa 16 de las 24 unidades de ancho
    radius = stroke_units * scale / 2
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    draw = ImageDraw.Draw(big)
    for x, y in pts:
        px = canvas / 2 + (x - cx) * scale
        py = canvas / 2 + (y - cy) * scale
        draw.ellipse((px - radius, py - radius, px + radius, py + radius), fill=color)
    return big.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    light = draw_wave(diagonal_gradient("#8B6CFF", "#3B2A86", SIZE), (255, 255, 255))
    dark = draw_wave(diagonal_gradient("#2A2148", "#0D0A17", SIZE), (0xB9, 0xA4, 0xFF))
    tinted = draw_wave(Image.new("RGB", (SIZE, SIZE), (0, 0, 0)), (255, 255, 255)).convert("L").convert("RGB")

    for name, img in (("icon.png", light), ("icon-dark.png", dark), ("icon-tinted.png", tinted)):
        assert img.mode == "RGB" and img.size == (SIZE, SIZE)
        img.save(OUT / name, "PNG", optimize=True)
        print("ok", name)


if __name__ == "__main__":
    main()
