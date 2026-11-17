"""Dibuja el icono de la app (1024 x 1024) en el catálogo de recursos.

Uso: .venv/Scripts/python.exe make_icon.py
Necesita Pillow (pip install pillow).
"""
from __future__ import annotations

import json

from PIL import Image, ImageDraw, ImageFilter

from common import RESOURCES

SIZE = 1024
SCALE = 2  # se dibuja al doble y se reduce, para suavizar los bordes
ORANGE = (255, 101, 5)
CYAN = (60, 225, 255)
ICONSET = RESOURCES / "Assets.xcassets" / "AppIcon.appiconset"


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main() -> None:
    n = SIZE * SCALE
    image = Image.new("RGB", (n, n))
    draw = ImageDraw.Draw(image)

    # Fondo: degradado vertical azul noche.
    top, bottom = (10, 14, 32), (24, 30, 62)
    for y in range(n):
        draw.line([(0, y), (n, y)], fill=lerp(top, bottom, y / n))

    cx, cy = n / 2, n * 0.52
    window = n * 0.40

    # Rejilla del suelo, fuera de la ventana.
    grid = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    step = n // 12
    for k in range(0, n + 1, step):
        grid_draw.line([(k, 0), (k, n)], fill=(*CYAN, 46), width=SCALE * 3)
        grid_draw.line([(0, k), (n, k)], fill=(*CYAN, 46), width=SCALE * 3)
    hole = Image.new("L", (n, n), 255)
    ImageDraw.Draw(hole).ellipse([cx - window, cy - window, cx + window, cy + window], fill=0)
    image.paste(grid, (0, 0), Image.composite(grid.split()[3], Image.new("L", (n, n), 0), hole))

    # Interior de la ventana: más oscuro, es lo que hay bajo el suelo.
    inside = Image.new("RGB", (n, n), (6, 8, 18))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse([cx - window, cy - window, cx + window, cy + window], fill=255)
    image.paste(inside, (0, 0), mask)

    # Túnel en perspectiva: anillos que se alejan hacia un punto de fuga.
    tunnel = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    tunnel_draw = ImageDraw.Draw(tunnel)
    vx, vy = cx + n * 0.03, cy - n * 0.04
    rings = 7
    for i in range(rings):
        t = i / (rings - 1)
        depth = 1 / (1 + 2.6 * t)          # tamaño aparente
        radius = window * 0.86 * depth
        ox = cx + (vx - cx) * (1 - depth)
        oy = cy + n * 0.03 + (vy - cy) * (1 - depth)
        alpha = round(255 * (1 - 0.72 * t))
        width = max(round(SCALE * 26 * depth), SCALE * 3)
        tunnel_draw.ellipse(
            [ox - radius, oy - radius, ox + radius, oy + radius],
            outline=(*ORANGE, alpha), width=width,
        )

    # Dos carriles blancos que convergen en el punto de fuga.
    near_y = cy + window * 0.80
    far_x, far_y = vx, vy + window * 0.20
    for side in (-1, 1):
        near_x = cx + side * window * 0.30
        tunnel_draw.line(
            [(near_x, near_y), (far_x + side * window * 0.035, far_y)],
            fill=(255, 255, 255, 235), width=SCALE * 13,
        )
    # Traviesas.
    for i in range(1, 7):
        t = i / 7
        s = (1 - t) ** 1.6
        y = far_y + (near_y - far_y) * s
        half = window * (0.035 + (0.36 - 0.035) * s)
        x = far_x + (cx - far_x) * s
        tunnel_draw.line([(x - half, y), (x + half, y)], fill=(255, 255, 255, round(70 + 110 * s)), width=max(round(SCALE * 9 * s), SCALE * 2))

    clipped = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    clipped.paste(tunnel, (0, 0), mask)
    glow = clipped.filter(ImageFilter.GaussianBlur(SCALE * 9))
    image.paste(glow, (0, 0), glow)
    image.paste(clipped, (0, 0), clipped)

    # Borde de la ventana.
    ring = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse(
        [cx - window, cy - window, cx + window, cy + window], outline=(*CYAN, 255), width=SCALE * 20
    )
    ring_glow = ring.filter(ImageFilter.GaussianBlur(SCALE * 12))
    image.paste(ring_glow, (0, 0), ring_glow)
    image.paste(ring, (0, 0), ring)

    final = image.resize((SIZE, SIZE), Image.LANCZOS)
    ICONSET.mkdir(parents=True, exist_ok=True)
    final.save(ICONSET / "icon-1024.png", optimize=True)

    (ICONSET / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n", encoding="utf-8")

    catalog = ICONSET.parent
    (catalog / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8"
    )
    accent = catalog / "AccentColor.colorset"
    accent.mkdir(exist_ok=True)
    (accent / "Contents.json").write_text(json.dumps({
        "colors": [{
            "idiom": "universal",
            "color": {
                "color-space": "srgb",
                "components": {"red": "1.000", "green": "0.396", "blue": "0.020", "alpha": "1.000"},
            },
        }],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n", encoding="utf-8")

    print(f"icono: {ICONSET / 'icon-1024.png'} ({(ICONSET / 'icon-1024.png').stat().st_size} bytes)")


if __name__ == "__main__":
    main()
