"""Comprueba App/Resources/metro.json y relieve.bin y genera preview.geojson.

Sale con código 1 si alguna comprobación obligatoria falla. Los avisos no
hacen fallar, pero conviene leerlos.
"""
from __future__ import annotations

import csv
import json
import math
import sys

import numpy as np

from common import EARTH_RADIUS, RAW, RESOURCES, TOOLS, dist_m

MAX_GAP_M = 1.0
MAX_POINT_STEP_M = 5.5
MAX_STATION_TO_TRACK_M = 30.0
MAX_SLOPE = 0.06
SLOPE_BASE_M = 20.0          # la pendiente se mide sobre tramos de al menos 20 m
PORTAL_TOLERANCE_M = 30.0    # junto a la boca del túnel carril y suelo coinciden

failures: list[str] = []
warnings: list[str] = []


def check(ok: bool, title: str, detail: str = "") -> None:
    print(("  OK    " if ok else "  FALLO ") + title + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(title)


def warn(title: str, detail: str = "") -> None:
    print("  AVISO " + title + (f" — {detail}" if detail else ""))
    warnings.append(title)


def nearest_distance(lon, lat, pts_lon, pts_lat) -> tuple[float, int]:
    east = EARTH_RADIUS * np.radians(pts_lon - lon) * math.cos(math.radians(lat))
    north = EARTH_RADIUS * np.radians(pts_lat - lat)
    d2 = east * east + north * north
    i = int(np.argmin(d2))
    return float(math.sqrt(d2[i])), i


def main() -> None:
    net = json.loads((RESOURCES / "metro.json").read_text(encoding="utf-8"))
    vias = {v["id"]: v for v in net["vias"]}
    lines = {l["id"] for l in net["lineas"]}
    print(f"metro.json generado el {net['generado']}: {len(vias)} vías, "
          f"{sum(len(v['puntos']) for v in vias.values())} puntos, {len(net['rutas'])} rutas, "
          f"{len(net['estaciones'])} estaciones, {sum(len(s['bocas']) for s in net['estaciones'])} bocas")

    # ---- Estructura --------------------------------------------------------
    print("Estructura")
    check(len(vias) == len(net["vias"]), "identificadores de vía únicos")
    bad = [v["id"] for v in vias.values() if len(v["puntos"]) < 2 or any(len(p) != 4 for p in v["puntos"])]
    check(not bad, "cada vía tiene al menos 2 puntos [lon, lat, cotaCarril, cotaSuelo]", ", ".join(bad[:5]))
    bad = [v["id"] for v in vias.values() if not v["lineas"] or not set(v["lineas"]) <= lines]
    check(not bad, "cada vía pertenece a alguna línea conocida", ", ".join(bad[:5]))
    worst = 0.0
    for v in vias.values():
        p = v["puntos"]
        for a, b in zip(p, p[1:]):
            worst = max(worst, dist_m(a[0], a[1], b[0], b[1]))
    check(worst <= MAX_POINT_STEP_M, f"puntos de vía separados como mucho {MAX_POINT_STEP_M} m", f"máximo {worst:.2f} m")
    ids = [s["id"] for s in net["estaciones"]]
    check(len(ids) == len(set(ids)), "identificadores de estación únicos")
    valid_origin = {"medido", "proyecto", "estimado"}
    bad = [s["nombre"] for s in net["estaciones"] if s["origenCota"] not in valid_origin]
    check(not bad, "origenCota es medido, proyecto o estimado", ", ".join(bad[:5]))

    # ---- Rutas -------------------------------------------------------------
    print("Rutas")
    routes = {}
    in_route = set()
    for route in net["rutas"]:
        points = []
        tunnel = []
        worst_gap = 0.0
        missing = [t["via"] for t in route["tramos"] if t["via"] not in vias]
        if missing:
            check(False, f"{route['id']}: tramos con vías inexistentes", ", ".join(missing[:5]))
            continue
        for tramo in route["tramos"]:
            via = vias[tramo["via"]]
            in_route.add(via["id"])
            pts = via["puntos"][::-1] if tramo["inv"] else via["puntos"]
            if points:
                worst_gap = max(worst_gap, dist_m(points[-1][0], points[-1][1], pts[0][0], pts[0][1]))
            points.extend(pts)
            tunnel.extend([via["tunel"]] * len(pts))
        arr = np.array(points)
        s = np.zeros(len(points))
        for i in range(1, len(points)):
            s[i] = s[i - 1] + dist_m(arr[i - 1, 0], arr[i - 1, 1], arr[i, 0], arr[i, 1])
        routes[route["id"]] = {"route": route, "pts": arr, "s": s, "tunnel": np.array(tunnel)}
        check(worst_gap <= MAX_GAP_M, f"{route['id']} ({route['nombre']}) es continua",
              f"{len(route['tramos'])} tramos, {s[-1] / 1000:.2f} km, hueco máximo {worst_gap:.2f} m")
    orphan = sorted(set(vias) - in_route)
    if orphan:
        warn(f"{len(orphan)} vías no están en ninguna ruta principal (apartaderos y variantes cortas)",
             ", ".join(orphan[:6]))

    # ---- Estaciones --------------------------------------------------------
    print("Estaciones")
    all_lon = np.concatenate([[p[0] for p in v["puntos"]] for v in vias.values()])
    all_lat = np.concatenate([[p[1] for p in v["puntos"]] for v in vias.values()])
    far, off_route = [], []
    for station in net["estaciones"]:
        d, _ = nearest_distance(station["lon"], station["lat"], all_lon, all_lat)
        if d > MAX_STATION_TO_TRACK_M:
            far.append(f"{station['nombre']} ({d:.0f} m)")
        for line in station["lineas"]:
            best = min(
                (nearest_distance(station["lon"], station["lat"], r["pts"][:, 0], r["pts"][:, 1])[0]
                 for r in routes.values() if r["route"]["linea"] == line),
                default=float("inf"),
            )
            if best > MAX_STATION_TO_TRACK_M:
                off_route.append(f"{station['nombre']}/{line} ({best:.0f} m)")
    check(not far, "cada estación está a menos de 30 m de una vía", ", ".join(far))
    check(not off_route, "cada estación proyecta a menos de 30 m sobre una ruta de cada una de sus líneas",
          ", ".join(off_route))

    stops_path = RAW / "gtfs" / "gtfs" / "stops.txt"
    if stops_path.exists():
        with open(stops_path, encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
        parents = {r["stop_id"].strip() for r in rows if r["location_type"].strip() == "1"}
        all_ids = {r["stop_id"].strip() for r in rows}
        ours = {s["id"] for s in net["estaciones"] if set(s["lineas"]) & {"L1", "L2"}}
        check(ours == parents, "las estaciones de L1 y L2 coinciden con las del GTFS",
              f"{len(ours)} nuestras, {len(parents)} en el GTFS; solo nuestras {sorted(ours - parents)}, "
              f"solo GTFS {sorted(parents - ours)}")
        unknown = [f"{s['nombre']}:{p}" for s in net["estaciones"] for p in s["paradas"] if p not in all_ids]
        check(not unknown, "todos los stop_id de `paradas` existen en el GTFS", ", ".join(unknown[:5]))
        l3 = [s for s in net["estaciones"] if s["lineas"] == ["L3"]]
        print(f"        (L3: {len(l3)} estaciones tomadas de OSM, sin GTFS)")
    else:
        warn("no está raw/gtfs/: no se compara el número de estaciones")

    no_mouth = [s["nombre"] for s in net["estaciones"] if s["subterranea"] and not s["bocas"]]
    check(not no_mouth, "cada estación subterránea tiene al menos una boca", ", ".join(no_mouth))
    far_mouth = [
        f"{s['nombre']}/{b['nombre']} ({dist_m(s['lon'], s['lat'], b['lon'], b['lat']):.0f} m)"
        for s in net["estaciones"] for b in s["bocas"]
        if dist_m(s["lon"], s["lat"], b["lon"], b["lat"]) > 400
    ]
    if far_mouth:
        warn("bocas a más de 400 m de su estación", ", ".join(far_mouth))
    estimated = [s["nombre"] for s in net["estaciones"] if s["subterranea"] and s["origenCota"] == "estimado"]
    underground = [s for s in net["estaciones"] if s["subterranea"]]
    warn(f"{len(estimated)} de {len(underground)} estaciones subterráneas tienen la cota del carril estimada, sin medir")

    # ---- Cotas -------------------------------------------------------------
    print("Cotas")
    steep_tunnel, steep_surface, above = [], [], []
    for rid, r in routes.items():
        pts, s, tunnel = r["pts"], r["s"], r["tunnel"]
        n = len(s)
        # Distancia de cada punto en túnel a la boca más cercana.
        portal = np.full(n, np.inf)
        last = None
        for i in range(n):
            if tunnel[i]:
                if i > 0 and not tunnel[i - 1]:
                    last = s[i - 1]
                if last is not None:
                    portal[i] = s[i] - last
            else:
                last = None
        last = None
        for i in range(n - 1, -1, -1):
            if tunnel[i]:
                if i + 1 < n and not tunnel[i + 1]:
                    last = s[i + 1]
                if last is not None:
                    portal[i] = min(portal[i], last - s[i])
            else:
                last = None
        for i in range(n):
            if tunnel[i] and portal[i] > PORTAL_TOLERANCE_M and pts[i, 2] >= pts[i, 3]:
                above.append(f"{rid} a {s[i]:.0f} m (carril {pts[i, 2]:.1f}, suelo {pts[i, 3]:.1f})")
        j = 0
        run_start = None
        worst = 0.0
        for i in range(n):
            while s[i] - s[j] > SLOPE_BASE_M:
                j += 1
            k = max(j - 1, 0)
            if s[i] - s[k] < SLOPE_BASE_M:
                continue
            slope = abs(pts[i, 2] - pts[k, 2]) / (s[i] - s[k])
            if slope > MAX_SLOPE:
                if run_start is None:
                    run_start = s[k]
                    worst = slope
                    kind_tunnel = bool(tunnel[i] or tunnel[k])
                worst = max(worst, slope)
                run_end = s[i]
            elif run_start is not None:
                text = f"{rid} de {run_start:.0f} a {run_end:.0f} m ({worst * 100:.1f} %)"
                (steep_tunnel if kind_tunnel else steep_surface).append(text)
                run_start = None
        if run_start is not None:
            text = f"{rid} de {run_start:.0f} a {run_end:.0f} m ({worst * 100:.1f} %)"
            (steep_tunnel if kind_tunnel else steep_surface).append(text)
    check(not above, "en túnel el carril queda por debajo del suelo (salvo a menos de 30 m de la boca)",
          "; ".join(above[:8]) + (f" ... y {len(above) - 8} más" if len(above) > 8 else ""))
    check(not steep_tunnel, "ninguna pendiente del carril en túnel supera el 6 %", "; ".join(steep_tunnel[:10]))
    if steep_surface:
        warn(f"{len(steep_surface)} tramos en superficie o viaducto superan el 6 % (revisar: ruido del relieve)",
             "; ".join(steep_surface[:10]))
    else:
        check(True, "ninguna pendiente del carril en superficie supera el 6 %")
    for station in net["estaciones"]:
        if station["subterranea"] and station["cotaCarril"] >= station["cotaSuelo"]:
            warn(f"{station['nombre']}: estación subterránea con el carril a la altura del suelo",
                 f"carril {station['cotaCarril']}, suelo {station['cotaSuelo']}")

    # ---- Relieve -----------------------------------------------------------
    print("Relieve")
    info = net["relieve"]
    path = RESOURCES / info["fichero"]
    expected = info["filas"] * info["columnas"] * 2
    check(path.exists() and path.stat().st_size == expected, "relieve.bin tiene filas × columnas × 2 bytes",
          f"{path.stat().st_size if path.exists() else 0} bytes, esperados {expected}")
    if path.exists() and path.stat().st_size == expected:
        grid = np.frombuffer(path.read_bytes(), dtype="<i2").reshape(info["filas"], info["columnas"])
        lon0, lat0 = info["origen"]

        def terrain(lon, lat):
            """Igual que hará la app: bilineal sobre las cuatro celdas vecinas."""
            fc = (lon - lon0) / info["paso_lon"]
            fr = (lat - lat0) / info["paso_lat"]
            c0, r0 = int(math.floor(fc)), int(math.floor(fr))
            if c0 < 0 or r0 < 0 or c0 + 1 >= info["columnas"] or r0 + 1 >= info["filas"]:
                return None
            cells = [grid[r0, c0], grid[r0, c0 + 1], grid[r0 + 1, c0], grid[r0 + 1, c0 + 1]]
            if any(c == info["sin_dato"] for c in cells):
                return None
            tc, tr = fc - c0, fr - r0
            return ((cells[0] * (1 - tc) + cells[1] * tc) * (1 - tr)
                    + (cells[2] * (1 - tc) + cells[3] * tc) * tr) / 10

        diffs, missing = [], 0
        for via in vias.values():
            for p in via["puntos"][::10]:
                value = terrain(p[0], p[1])
                if value is None:
                    missing += 1
                else:
                    diffs.append(abs(value - p[3]))
        diffs = np.array(diffs)
        check(missing == 0, "la rejilla cubre todos los puntos de las vías", f"{missing} sin dato")
        check(float(np.median(diffs)) < 0.5, "la rejilla de 10 m coincide con el suelo de las vías",
              f"diferencia mediana {np.median(diffs):.2f} m, percentil 95 {np.percentile(diffs, 95):.2f} m, "
              f"máxima {diffs.max():.1f} m")
        mouths = [(b["lon"], b["lat"]) for s in net["estaciones"] for b in s["bocas"]]
        outside = sum(1 for lon, lat in mouths if terrain(lon, lat) is None)
        if outside:
            warn(f"{outside} de {len(mouths)} bocas quedan fuera del pasillo de la rejilla "
                 "(la app debe usar su cotaSuelo)")
        else:
            check(True, "todas las bocas caen dentro de la rejilla")

    # ---- Contraste con el GTFS (shapes.txt) ----------------------------------
    shapes_path = RAW / "gtfs" / "gtfs" / "shapes.txt"
    if shapes_path.exists():
        print("Contraste con shapes.txt del GTFS")
        with open(shapes_path, encoding="utf-8-sig", newline="") as handle:
            shape_points = [
                (float(r["shape_pt_lon"]), float(r["shape_pt_lat"]))
                for r in csv.DictReader(handle) if r["shape_id"] in ("ETX_PLE", "BSR_KAB")
            ]
        distances = np.array([nearest_distance(lon, lat, all_lon, all_lat)[0] for lon, lat in shape_points])
        text = (f"{len(distances)} puntos de ETX_PLE y BSR_KAB: mediana {np.median(distances):.1f} m, "
                f"percentil 95 {np.percentile(distances, 95):.1f} m, máxima {distances.max():.0f} m")
        if np.percentile(distances, 95) <= 30:
            check(True, "el trazado de OSM coincide con el del GTFS", text)
        else:
            warn("el trazado de OSM se separa del GTFS", text)

    # ---- preview.geojson -------------------------------------------------------
    colors = {l["id"]: l["color"] for l in net["lineas"]}
    features = []
    for via in vias.values():
        features.append({
            "type": "Feature",
            "properties": {
                "tipo": "via",
                "id": via["id"],
                "lineas": ",".join(via["lineas"]),
                "tunel": via["tunel"],
                "stroke": colors[via["lineas"][0]] if len(via["lineas"]) == 1 else "#7a3cff",
                "stroke-width": 3 if via["tunel"] else 1.5,
                "stroke-opacity": 0.9,
            },
            "geometry": {"type": "LineString", "coordinates": [[p[0], p[1]] for p in via["puntos"]]},
        })
    for station in net["estaciones"]:
        features.append({
            "type": "Feature",
            "properties": {
                "tipo": "estacion",
                "id": station["id"],
                "nombre": station["nombre"],
                "lineas": ",".join(station["lineas"]),
                "cotaCarril": station["cotaCarril"],
                "cotaSuelo": station["cotaSuelo"],
                "profundidad": round(station["cotaSuelo"] - station["cotaCarril"], 1),
                "origenCota": station["origenCota"],
                "subterranea": station["subterranea"],
                "marker-color": colors[station["lineas"][0]],
                "marker-size": "medium",
            },
            "geometry": {"type": "Point", "coordinates": [station["lon"], station["lat"]]},
        })
        for boca in station["bocas"]:
            features.append({
                "type": "Feature",
                "properties": {
                    "tipo": "boca",
                    "estacion": station["nombre"],
                    "nombre": boca["nombre"],
                    "cotaSuelo": boca["cotaSuelo"],
                    "marker-color": "#2e9bff",
                    "marker-size": "small",
                },
                "geometry": {"type": "Point", "coordinates": [boca["lon"], boca["lat"]]},
            })
    preview = TOOLS / "preview.geojson"
    preview.write_text(json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False,
                                  separators=(",", ":")), encoding="utf-8")
    print(f"preview.geojson: {len(features)} elementos, {preview.stat().st_size} bytes")

    print()
    print(f"Resultado: {len(failures)} fallos, {len(warnings)} avisos")
    for title in failures:
        print("  FALLO: " + title)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
