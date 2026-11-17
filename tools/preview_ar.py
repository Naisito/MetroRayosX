"""Simulación de la pantalla de rayos X con los datos reales.

NO es una captura de la app: dibuja en perspectiva la misma geometría que la
app (carriles, anillos cada 10 m, caverna de la estación, bocas, rejilla del
suelo y línea de profundidad) vista desde una boca de metro, sobre un fondo
liso en lugar de la imagen de la cámara. Sirve para hacerse una idea.

Uso: .venv/Scripts/python.exe preview_ar.py [nombre de estación] [fichero.png]
"""
from __future__ import annotations

import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

from common import EARTH_RADIUS, RESOURCES, ROOT

W, H, S = 780, 1688, 2          # tamaño final y factor de sobremuestreo
EYE = 1.5                       # altura del móvil sobre el suelo
HFOV = math.radians(52)
RADIUS = 400.0
GAUGE, RING_R, RING_LIFT = 1.0, 2.9, 1.9

CYAN = (150, 235, 255)
WINDOW = (51, 230, 255)
YELLOW = (255, 235, 64)
GREEN = (153, 255, 153)
WHITE = (255, 255, 255)


def hex_rgb(text):
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def display_rgb(color, min_lum=0.45):
    """Como ColorHex.displayRGB: aclara los colores oscuros (la L2 es negra)."""
    r, g, b = (c / 255 for c in color)
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if lum >= min_lum:
        return color
    mix = (min_lum - lum) / max(1 - lum, 1e-6)
    return tuple(round(255 * (c + (1 - c) * mix)) for c in (r, g, b))


def lighten(color, amount):
    return tuple(round(c + (255 - c) * amount) for c in color)


def fade(distance):
    if distance <= 150:
        return 1.0
    if distance >= RADIUS:
        return 0.12
    return 1 - 0.88 * (distance - 150) / (RADIUS - 150)


def font(size, bold=False):
    for name in (("segoeuib.ttf", "arialbd.ttf") if bold else ("segoeui.ttf", "arial.ttf")):
        try:
            return ImageFont.truetype(name, size * S)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    wanted = sys.argv[1] if len(sys.argv) > 1 else "Eliptikoa"
    out = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / "docs" / "simulacion-rayos-x.png")
    red = json.loads((RESOURCES / "metro.json").read_text(encoding="utf-8"))
    colors = {l["id"]: display_rgb(hex_rgb(l["color"])) for l in red["lineas"]}
    station = next(e for e in red["estaciones"] if e["nombre"].lower().startswith(wanted.lower()))

    # El usuario está en la boca de la estación más alejada del eje de las
    # vías: desde ahí se ve el túnel de lado y no justo debajo.
    def track_distance(b):
        kx0 = EARTH_RADIUS * math.pi / 180 * math.cos(math.radians(b["lat"]))
        k0 = EARTH_RADIUS * math.pi / 180
        return min(
            math.hypot((p[0] - b["lon"]) * kx0, (p[1] - b["lat"]) * k0)
            for via in red["vias"] for p in via["puntos"][::3]
        )

    boca = max(station["bocas"], key=track_distance)
    lon0, lat0, ground0 = boca["lon"], boca["lat"], boca["cotaSuelo"]
    k = EARTH_RADIUS * math.pi / 180
    kx = k * math.cos(math.radians(lat0))

    def local(lon, lat, cota):
        """Coordenadas de escena: x = este, y = arriba, z = sur."""
        return ((lon - lon0) * kx, cota - ground0, -(lat - lat0) * k)

    # Vía más cercana y dirección en la que mirar: 70 m vía adelante.
    best = None
    for via in red["vias"]:
        for i, p in enumerate(via["puntos"]):
            x, _, z = local(p[0], p[1], p[2])
            d = math.hypot(x, z)
            if best is None or d < best[0]:
                best = (d, via, i)
    _, near_via, near_i = best
    pts = near_via["puntos"]
    # Se mira al punto medio entre la vía más cercana y la estación, para que
    # entren en el encuadre la línea de profundidad y la caverna.
    n0 = local(pts[near_i][0], pts[near_i][1], pts[near_i][2])
    s0 = local(station["lon"], station["lat"], station["cotaCarril"])
    ax, ay, az = ((n0[i] + s0[i]) / 2 for i in range(3))
    yaw = math.atan2(ax, -az)
    pitch = math.atan2(EYE - (ay + 3), math.hypot(ax, az))
    pitch = min(max(pitch, math.radians(22)), math.radians(50))

    f = (math.sin(yaw) * math.cos(pitch), -math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
    r = (math.cos(yaw), 0.0, math.sin(yaw))
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    focal = (W * S / 2) / math.tan(HFOV / 2)
    cam = (0.0, EYE, 0.0)

    def to_camera(p):
        d = (p[0] - cam[0], p[1] - cam[1], p[2] - cam[2])
        return (sum(d[i] * r[i] for i in range(3)), sum(d[i] * u[i] for i in range(3)), sum(d[i] * f[i] for i in range(3)))

    def screen(c):
        return (W * S / 2 + focal * c[0] / c[2], H * S / 2 - focal * c[1] / c[2])

    prims = []  # (profundidad, p1, p2, color, alfa, grosor)

    def line(a, b, color, alpha, width):
        ca, cb = to_camera(a), to_camera(b)
        near = 0.4
        if ca[2] < near and cb[2] < near:
            return
        if ca[2] < near or cb[2] < near:  # recorte contra el plano cercano
            t = (near - ca[2]) / (cb[2] - ca[2])
            mid = tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3))
            ca, cb = (mid, cb) if ca[2] < near else (ca, mid)
        depth = (ca[2] + cb[2]) / 2
        w = max(1.3, min(width * 24 / max(depth, 1), width * 3.5)) * S
        prims.append((depth, screen(ca), screen(cb), color, alpha, w))

    # Rejilla del suelo con la ventana bajo los pies.
    step, hole, grid_r = 2.5, 2.5, 30.0
    n = int(grid_r / step) + 1
    for i in range(-n, n + 1):
        for j in range(-n, n):
            for a, b in (((i * step, 0, j * step), (i * step, 0, (j + 1) * step)),
                         ((j * step, 0, i * step), ((j + 1) * step, 0, i * step))):
                d = math.hypot((a[0] + b[0]) / 2, (a[2] + b[2]) / 2)
                if hole <= d <= grid_r:
                    band = min(int(d / grid_r * 3), 2)
                    line(a, b, CYAN, (0.55, 0.32, 0.14)[band], 0.5)
    for i in range(64):
        a0, a1 = 2 * math.pi * i / 64, 2 * math.pi * (i + 1) / 64
        line((hole * math.cos(a0), 0.02, hole * math.sin(a0)), (hole * math.cos(a1), 0.02, hole * math.sin(a1)), WINDOW, 0.9, 1.6)

    # Vías y túnel.
    for via in red["vias"]:
        color = colors.get(via["lineas"][0], (255, 122, 0)) if via["lineas"] else (255, 122, 0)
        path = [local(p[0], p[1], p[2]) for p in via["puntos"]]
        if min(math.hypot(p[0], p[2]) for p in path) > RADIUS:
            continue
        chain = 0.0
        next_ring = 0.0
        for a, b in zip(path, path[1:]):
            dx, dz = b[0] - a[0], b[2] - a[2]
            length = math.hypot(dx, dz)
            if length < 1e-6:
                continue
            dist = math.hypot((a[0] + b[0]) / 2, (a[2] + b[2]) / 2)
            if dist <= RADIUS:
                alpha = fade(dist)
                side = (-dz / length, 0.0, dx / length)

                def off(p, lateral, lift):
                    return (p[0] + side[0] * lateral, p[1] + lift, p[2] + side[2] * lateral)

                for lateral in (-GAUGE / 2, GAUGE / 2):
                    line(off(a, lateral, 0.02), off(b, lateral, 0.02), lighten(color, 0.65), alpha, 1.3)
                if via["tunel"]:
                    for lateral, lift in ((0, RING_LIFT + RING_R), (-RING_R, RING_LIFT), (RING_R, RING_LIFT)):
                        line(off(a, lateral, lift), off(b, lateral, lift), color, 0.85 * alpha, 0.9)
                    while next_ring < chain + length:
                        t = (next_ring - chain) / length
                        c = (a[0] + dx * t, a[1] + (b[1] - a[1]) * t + RING_LIFT, a[2] + dz * t)
                        ring = [
                            (c[0] + side[0] * RING_R * math.cos(2 * math.pi * s / 16),
                             c[1] + RING_R * math.sin(2 * math.pi * s / 16),
                             c[2] + side[2] * RING_R * math.cos(2 * math.pi * s / 16))
                            for s in range(17)
                        ]
                        for p, q in zip(ring, ring[1:]):
                            line(p, q, color, 0.85 * alpha, 1.5)
                        next_ring += 10
            while next_ring < chain + length:
                next_ring += 10
            chain += length

    # Estaciones y bocas.
    labels = []
    for e in red["estaciones"]:
        rail = local(e["lon"], e["lat"], e["cotaCarril"])
        dist = math.hypot(rail[0], rail[2])
        if dist > RADIUS + 50:
            continue
        # Dirección de la vía más cercana a la estación.
        nearest = None
        for via in red["vias"]:
            for i in range(len(via["puntos"]) - 1):
                p, q = via["puntos"][i], via["puntos"][i + 1]
                d = math.hypot((p[0] - e["lon"]) * kx, (p[1] - e["lat"]) * k)
                if nearest is None or d < nearest[0]:
                    nearest = (d, ((q[0] - p[0]) * kx, -(q[1] - p[1]) * k))
        dx, dz = nearest[1]
        norm = math.hypot(dx, dz) or 1.0
        dirv, sidev = (dx / norm, dz / norm), (-dz / norm, dx / norm)
        if e["subterranea"]:
            L, Wd, Ht, base = 95 / 2, 17 / 2, 7.5, rail[1] - 0.4
        else:
            L, Wd, Ht, base = 95 / 2, 12 / 2, 1.1, rail[1]
        corners = [
            (rail[0] + dirv[0] * sl * L + sidev[0] * sw * Wd, base, rail[2] + dirv[1] * sl * L + sidev[1] * sw * Wd)
            for sl, sw in ((-1, -1), (1, -1), (1, 1), (-1, 1))
        ]
        top = [(c[0], c[1] + Ht, c[2]) for c in corners]
        for i in range(4):
            j = (i + 1) % 4
            for p, q in ((corners[i], corners[j]), (top[i], top[j]), (corners[i], top[i])):
                line(p, q, WHITE, 0.9, 1.6)
        depth = e["cotaSuelo"] - e["cotaCarril"]
        detail = f"{depth:.0f} m bajo el suelo" + (" (estimado)" if e["origenCota"] == "estimado" else "") \
            if e["subterranea"] else "en superficie"
        labels.append(((rail[0], rail[1] + (9 if e["subterranea"] else 6), rail[2]), e["nombre"], detail, "station"))

        for b in e["bocas"]:
            g = local(b["lon"], b["lat"], b["cotaSuelo"])
            if math.hypot(g[0], g[2]) < 1.0:
                continue  # la boca donde está el usuario
            for i in range(28):
                a0, a1 = 2 * math.pi * i / 28, 2 * math.pi * (i + 1) / 28
                line((g[0] + 1.1 * math.cos(a0), g[1] + 0.05, g[2] + 1.1 * math.sin(a0)),
                     (g[0] + 1.1 * math.cos(a1), g[1] + 0.05, g[2] + 1.1 * math.sin(a1)), GREEN, 0.9, 1.4)
            line(g, (g[0], g[1] + 2.2, g[2]), GREEN, 0.9, 1.0)
            if math.hypot(g[0], g[2]) < 120:
                labels.append(((g[0], g[1] + 2.4, g[2]), b["nombre"] or "Boca", "Boca de " + e["nombre"], "boca"))

    # Línea de profundidad en el punto de vía más cercano.
    p = pts[near_i]
    topp, bottom = local(p[0], p[1], p[3]), local(p[0], p[1], p[2])
    line(topp, bottom, YELLOW, 0.95, 2.2)
    depth_here = p[3] - p[2]
    labels.append((tuple((topp[i] + bottom[i]) / 2 for i in range(3)), f"{depth_here:.0f} m", "hasta la vía", "depth"))

    # --- Dibujo ---
    image = Image.new("RGB", (W * S, H * S))
    draw = ImageDraw.Draw(image, "RGBA")
    horizon = H * S / 2 - focal * math.tan(pitch)
    for y in range(H * S):
        if y < horizon:
            t = y / max(horizon, 1)
            c = (round(96 + 40 * t), round(104 + 40 * t), round(118 + 38 * t))
        else:
            t = (y - horizon) / (H * S - horizon)
            c = (round(92 - 34 * t), round(94 - 34 * t), round(98 - 34 * t))
        draw.line([(0, y), (W * S, y)], fill=c)
    draw.text((W * S / 2, horizon + 60 * S), "aquí va la imagen de la cámara", font=font(15), fill=(255, 255, 255, 70), anchor="mm")

    for depth, a, b, color, alpha, width in sorted(prims, key=lambda item: -item[0]):
        draw.line([a, b], fill=(*color, round(255 * alpha)), width=max(1, round(width)))

    # Rótulos, del más lejano al más cercano, sin pisarse.
    placed = []
    order = sorted(labels, key=lambda item: (item[3] != "depth", math.dist(item[0], cam)))
    for pos, title, detail, kind in order:
        c = to_camera(pos)
        if c[2] < 0.5:
            continue
        x, y = screen(c)
        if not (40 * S < x < (W - 40) * S and 120 * S < y < (H - 280) * S):
            continue
        if any(abs(x - px) < 170 * S and abs(y - py) < 46 * S for px, py in placed):
            continue
        placed.append((x, y))
        if len(placed) > 8:
            break
        dist = math.dist(pos, cam)
        if kind == "station":
            detail = f"a {dist:.0f} m · {detail}"
        tf = font(19, True) if kind == "depth" else font(15 if kind == "station" else 12, True)
        df = font(11)
        tw = max(draw.textlength(title, font=tf), draw.textlength(detail, font=df)) + 18 * S
        th = (48 if kind == "depth" else 42 if kind == "station" else 38) * S
        x = min(max(x, tw / 2 + 8 * S), W * S - tw / 2 - 8 * S)
        box = [x - tw / 2, y - th / 2, x + tw / 2, y + th / 2]
        border = {"depth": (*YELLOW, 204), "station": (255, 255, 255, 110), "boca": (*GREEN, 153)}[kind]
        draw.rounded_rectangle(box, radius=8 * S, fill=(0, 0, 0, 150), outline=border, width=S)
        tcolor = {"depth": YELLOW, "station": WHITE, "boca": GREEN}[kind]
        draw.text((x, y - 8 * S), title, font=tf, fill=tcolor, anchor="mm")
        draw.text((x, y + 11 * S), detail, font=df, fill=(255, 255, 255, 217), anchor="mm")

    # Panel inferior, como el de la app.
    m = 10 * S
    panel = [m, (H - 250) * S, W * S - m, (H - 96) * S]
    draw.rounded_rectangle(panel, radius=16 * S, fill=(28, 28, 32, 215))
    draw.text((panel[0] + 14 * S, panel[1] + 24 * S), station["nombre"], font=font(18, True), fill=WHITE, anchor="lm")
    draw.text((panel[0] + 14 * S, panel[1] + 48 * S), f"estación a {math.hypot(*local(station['lon'], station['lat'], 0)[::2]):.0f} m · vía a {best[0]:.0f} m · anclado en {station['nombre']}",
              font=font(12), fill=(200, 200, 205), anchor="lm")
    draw.text((panel[2] - 14 * S, panel[1] + 24 * S), f"{depth_here:.0f} m", font=font(24, True), fill=WHITE, anchor="rm")
    draw.text((panel[2] - 14 * S, panel[1] + 48 * S), "bajo tus pies (estimado)", font=font(11), fill=(200, 200, 205), anchor="rm")
    names = ("Calibrar", "Trenes", "Grabar", "Datos")
    bw = (panel[2] - panel[0] - 20 * S - 30 * S) / 4
    for i, name in enumerate(names):
        x0 = panel[0] + 10 * S + i * (bw + 10 * S)
        active = name == "Trenes"
        draw.rounded_rectangle([x0, panel[1] + 72 * S, x0 + bw, panel[3] - 10 * S], radius=10 * S,
                               fill=(255, 101, 5, 255) if active else (255, 255, 255, 28))
        draw.text((x0 + bw / 2, panel[1] + 108 * S), name, font=font(12), fill=WHITE, anchor="mm")

    # Barra de pestañas.
    draw.rectangle([0, (H - 86) * S, W * S, H * S], fill=(20, 20, 24, 240))
    for i, name in enumerate(("Mapa", "Rayos X", "Medir", "Más")):
        x = W * S * (i + 0.5) / 4
        draw.text((x, (H - 50) * S), name, font=font(13, i == 1), fill=(255, 101, 5) if i == 1 else (150, 150, 156), anchor="mm")

    # Aviso de que es una simulación.
    draw.rounded_rectangle([m, 54 * S, W * S - m, 104 * S], radius=12 * S, fill=(0, 0, 0, 170))
    draw.text((W * S / 2, 70 * S), "SIMULACIÓN con los datos reales: no es una captura de la app", font=font(13, True), fill=WHITE, anchor="mm")
    draw.text((W * S / 2, 90 * S), f"Vista desde una boca de {station['nombre']}, mirando hacia la estación", font=font(11), fill=(220, 220, 225), anchor="mm")

    final = image.resize((W, H), Image.LANCZOS)
    from pathlib import Path
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    final.save(out, optimize=True)
    print(f"{out}: {len(prims)} segmentos, {len(placed)} rótulos, profundidad {depth_here:.1f} m, vía a {best[0]:.1f} m")


if __name__ == "__main__":
    main()
