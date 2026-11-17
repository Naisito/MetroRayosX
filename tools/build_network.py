"""Construye App/Resources/metro.json y relieve.bin a partir de raw/.

Entradas:
  raw/osm.json          (fetch_osm.py)
  raw/gtfs/             (fetch_gtfs.py)
  raw/dem/*.tif         (fetch_dem.py)
  depths.csv            cotas del carril por estación (se edita a mano)
  control_points.csv    puntos del carril fijados a mano (cruces bajo la ría)

Salidas:
  App/Resources/metro.json
  App/Resources/relieve.bin
  depths.csv            se completa con las estaciones que falten (nunca se pisan filas)
"""
from __future__ import annotations

import csv
import datetime
import glob
import json
import math
import unicodedata
from collections import defaultdict

import numpy as np
import rasterio
from pyproj import Transformer

from common import EARTH_RADIUS, RAW, RESOURCES, TOOLS, dist_m, local_xy

TRACK_RAILWAYS = {"subway", "narrow_gauge", "rail", "light_rail"}
MAX_STEP_M = 5.0            # separación máxima entre puntos de una vía
DEFAULT_DEPTH_M = 20.0      # estación subterránea sin dato: metros bajo su boca más baja
PLATFORM_ABOVE_RAIL_M = 1.05
MAX_SLOPE = 0.055           # pendiente máxima al estimar (el límite a validar es 6 %)
MIN_COVER_M = 7.0           # en túnel, el carril va al menos esto por debajo del suelo
COVER_RAMP = 0.05           # ...creciendo así desde la boca del túnel
SURFACE_SMOOTH_M = 20.0     # semiventana del suavizado del carril en superficie (ruido del LiDAR)
BRIDGE_MARGIN_M = 15.0      # metros junto a un puente que se tratan como puente
PORTAL_MARGIN_M = 15.0      # metros de superficie junto a una boca de túnel que se interpolan
SMOOTH_MIN_HALF_M = 6.0     # semiventana mínima de la media móvil en los extremos
CORRIDOR_M = 400.0          # pasillo de relieve.bin alrededor de las vías
GRID_STEP_M = 10.0
NODATA = -32768

LINE_INFO = {
    # Colores: L1 = naranja corporativo (route_color del GTFS de Metro Bilbao),
    # L2 = negro (etiqueta colour de OSM), L3 = #E3007D (etiqueta colour de OSM).
    "L1": {"nombre": "Etxebarri - Plentzia", "color": "#FF6505"},
    "L2": {"nombre": "Basauri - Kabiezes", "color": "#000000"},
    "L3": {"nombre": "Matiko - Kukullaga", "color": "#E3007D"},
}
# Sentido 0 = el direction_id 0 del GTFS (hacia Plentzia / Kabiezes).
ROUTE_TERMINALS = {
    "L1": [("Etxebarri", "Plentzia"), ("Plentzia", "Etxebarri")],
    "L2": [("Basauri", "Kabiezes"), ("Kabiezes", "Basauri")],
    "L3": [("Matiko", "Kukullaga"), ("Kukullaga", "Matiko")],
}


def norm(text: str) -> str:
    text = unicodedata.normalize("NFD", text or "")
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return "".join(c for c in text.lower() if c.isalnum())


# --------------------------------------------------------------------------
# Relieve
# --------------------------------------------------------------------------

class Dem:
    """Mosaico en memoria de las teselas de 5 m (EPSG:25830)."""

    def __init__(self) -> None:
        paths = sorted(glob.glob(str(RAW / "dem" / "mdt5_*.tif")))
        if not paths:
            raise SystemExit("No hay teselas en raw/dem/. Ejecuta fetch_dem.py.")
        bounds = []
        for path in paths:
            with rasterio.open(path) as ds:
                if ds.crs.to_epsg() != 25830:
                    raise SystemExit(f"{path}: CRS inesperado {ds.crs}")
                bounds.append(ds.bounds)
                self.res = ds.res[0]
        self.x_min = min(b.left for b in bounds)
        self.x_max = max(b.right for b in bounds)
        self.y_min = min(b.bottom for b in bounds)
        self.y_max = max(b.top for b in bounds)
        cols = int(round((self.x_max - self.x_min) / self.res))
        rows = int(round((self.y_max - self.y_min) / self.res))
        self.data = np.full((rows, cols), np.nan, dtype=np.float32)
        for path in paths:
            with rasterio.open(path) as ds:
                tile = ds.read(1).astype(np.float32)
                tile[(tile < -100) | (tile > 5000)] = np.nan
                col = int(round((ds.bounds.left - self.x_min) / self.res))
                row = int(round((self.y_max - ds.bounds.top) / self.res))
                self.data[row:row + tile.shape[0], col:col + tile.shape[1]] = tile
        self.to_utm = Transformer.from_crs(4326, 25830, always_xy=True)
        print(f"relieve: {len(paths)} teselas, mosaico {cols}x{rows} px de {self.res:g} m")

    def sample_xy(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        """Interpolación bilineal; NaN donde no hay dato."""
        fc = (np.asarray(x) - self.x_min) / self.res - 0.5
        fr = (self.y_max - np.asarray(y)) / self.res - 0.5
        rows, cols = self.data.shape
        inside = (fc >= 0) & (fr >= 0) & (fc <= cols - 1) & (fr <= rows - 1)
        fc = np.clip(fc, 0, cols - 1 - 1e-6)
        fr = np.clip(fr, 0, rows - 1 - 1e-6)
        c0 = np.floor(fc).astype(int)
        r0 = np.floor(fr).astype(int)
        tc = fc - c0
        tr = fr - r0
        v00 = self.data[r0, c0]
        v01 = self.data[r0, c0 + 1]
        v10 = self.data[r0 + 1, c0]
        v11 = self.data[r0 + 1, c0 + 1]
        value = (v00 * (1 - tc) + v01 * tc) * (1 - tr) + (v10 * (1 - tc) + v11 * tc) * tr
        # Si alguna esquina no tiene dato, se usa la esquina válida más cercana.
        bad = np.isnan(value)
        if np.any(bad):
            nearest = self.data[np.rint(fr).astype(int), np.rint(fc).astype(int)]
            value = np.where(bad, nearest, value)
        return np.where(inside, value, np.nan)

    def sample(self, lon, lat) -> np.ndarray:
        x, y = self.to_utm.transform(np.asarray(lon, dtype=float), np.asarray(lat, dtype=float))
        return self.sample_xy(x, y)

    def at(self, lon: float, lat: float) -> float:
        return float(self.sample([lon], [lat])[0])


# --------------------------------------------------------------------------
# OSM
# --------------------------------------------------------------------------

def load_osm():
    osm = json.loads((RAW / "osm.json").read_text(encoding="utf-8"))
    nodes, ways, rels = {}, {}, {}
    for element in osm["elements"]:
        {"node": nodes, "way": ways, "relation": rels}[element["type"]][element["id"]] = element
    return nodes, ways, rels


def route_ways(rel, ways) -> list[int]:
    return [
        m["ref"] for m in rel["members"]
        if m["type"] == "way" and m["role"] == "" and m["ref"] in ways
        and ways[m["ref"]].get("tags", {}).get("railway") in TRACK_RAILWAYS
    ]


def route_sequence(rel, ways) -> list[tuple[int, bool]]:
    """Ways de la ruta en orden de marcha, con `inv` si se recorren al revés."""
    ids = route_ways(rel, ways)
    sequence: list[tuple[int, bool]] = []
    previous_end = None
    for index, way_id in enumerate(ids):
        first, last = ways[way_id]["nodes"][0], ways[way_id]["nodes"][-1]
        if index == 0:
            if len(ids) > 1:
                nxt = ways[ids[1]]["nodes"]
                inv = first in (nxt[0], nxt[-1]) and last not in (nxt[0], nxt[-1])
            else:
                inv = False
        elif first == previous_end:
            inv = False
        elif last == previous_end:
            inv = True
        else:
            raise SystemExit(
                f"La ruta {rel['id']} ({rel['tags'].get('name')}) no es continua en el way {way_id}"
            )
        previous_end = first if inv else last
        sequence.append((way_id, inv))
    return sequence


def way_length(way) -> float:
    g = way["geometry"]
    return sum(dist_m(g[i]["lon"], g[i]["lat"], g[i + 1]["lon"], g[i + 1]["lat"]) for i in range(len(g) - 1))


def densify(geometry: list[dict]) -> list[tuple[float, float]]:
    """Conserva todos los nodos de OSM y parte los segmentos de más de 5 m."""
    points: list[tuple[float, float]] = [(geometry[0]["lon"], geometry[0]["lat"])]
    for a, b in zip(geometry, geometry[1:]):
        length = dist_m(a["lon"], a["lat"], b["lon"], b["lat"])
        pieces = max(1, math.ceil(length / MAX_STEP_M))
        for k in range(1, pieces):
            t = k / pieces
            points.append((
                round(a["lon"] + (b["lon"] - a["lon"]) * t, 7),
                round(a["lat"] + (b["lat"] - a["lat"]) * t, 7),
            ))
        points.append((b["lon"], b["lat"]))
    return points


# --------------------------------------------------------------------------
# Perfil del carril a lo largo de una ruta
# --------------------------------------------------------------------------

def lipschitz_min(values: np.ndarray, s: np.ndarray, slope: float) -> np.ndarray:
    """Mayor función con pendiente <= slope que queda por debajo de `values`."""
    out = values.copy()
    for i in range(1, len(out)):
        out[i] = min(out[i], out[i - 1] + slope * (s[i] - s[i - 1]))
    for i in range(len(out) - 2, -1, -1):
        out[i] = min(out[i], out[i + 1] + slope * (s[i + 1] - s[i]))
    return out


def lipschitz_max(values: np.ndarray, s: np.ndarray, slope: float) -> np.ndarray:
    return -lipschitz_min(-values, s, slope)


def smooth_surface(values: np.ndarray, s: np.ndarray, half_window: float) -> np.ndarray:
    """Suaviza la cota del suelo a lo largo de un tramo en superficie.

    Primero una mediana móvil (quita taludes, pasos y otros picos cortos del
    MDT) y después una media móvil. La ventana es simétrica y se estrecha cerca
    de los extremos para que el resultado no se retrase respecto al terreno.
    """
    n = len(values)

    def windows():
        for i in range(n):
            half = min(half_window, max(SMOOTH_MIN_HALF_M, min(s[i] - s[0], s[-1] - s[i])))
            left = int(np.searchsorted(s, s[i] - half, side="left"))
            right = int(np.searchsorted(s, s[i] + half, side="right"))
            yield i, left, right

    median = np.empty_like(values)
    for i, left, right in windows():
        median[i] = np.median(values[left:right])
    out = np.empty_like(values)
    for i, left, right in windows():
        out[i] = median[left:right].mean()
    return out


def rail_profile(s, ground, tunnel, bridge, hard_points, soft_points):
    """Cota del carril en cada punto de una ruta.

    s, ground: distancia recorrida y cota del suelo de cada punto.
    tunnel, bridge: máscaras booleanas.
    hard_points: {índice: cota} fijados (puntos de control, estaciones medidas).
    soft_points: {índice: cota} estimados (estaciones sin dato); se ajustan para
                 respetar la pendiente máxima y el recubrimiento.
    """
    n = len(s)
    inf = float("inf")
    surface = ~tunnel & ~bridge

    # 1. En superficie el carril es el suelo, suavizado para quitar ruido.
    smooth = ground.copy()
    start = 0
    while start < n:
        if not surface[start]:
            start += 1
            continue
        end = start
        while end + 1 < n and surface[end + 1]:
            end += 1
        smooth[start:end + 1] = smooth_surface(ground[start:end + 1], s[start:end + 1], SURFACE_SMOOTH_M)
        start = end + 1

    # Junto a una boca de túnel el MDT puede dar ya la ladera de encima: esos
    # metros de superficie se interpolan en vez de fiarse del suelo.
    near_tunnel = np.zeros(n, dtype=bool)
    if tunnel.any():
        tunnel_s = s[tunnel]
        pos = np.searchsorted(tunnel_s, s)
        before = np.where(pos > 0, s - tunnel_s[np.maximum(pos - 1, 0)], inf)
        after = np.where(pos < len(tunnel_s), tunnel_s[np.minimum(pos, len(tunnel_s) - 1)] - s, inf)
        near_tunnel = np.minimum(before, after) < PORTAL_MARGIN_M

    known = np.full(n, np.nan)
    trusted = surface & ~near_tunnel
    known[trusted] = smooth[trusted]
    for index, value in hard_points.items():
        known[index] = value
    is_hard = ~np.isnan(known)

    # 2. Recubrimiento mínimo en túnel, creciendo desde las bocas.
    portal_distance = np.full(n, inf)
    last_portal = None
    for i in range(n):
        if tunnel[i]:
            if i > 0 and not tunnel[i - 1]:
                last_portal = s[i - 1]
            if last_portal is not None:
                portal_distance[i] = s[i] - last_portal
        else:
            last_portal = None
    next_portal = None
    for i in range(n - 1, -1, -1):
        if tunnel[i]:
            if i + 1 < n and not tunnel[i + 1]:
                next_portal = s[i + 1]
            if next_portal is not None:
                portal_distance[i] = min(portal_distance[i], next_portal - s[i])
        else:
            next_portal = None
    cover = np.minimum(MIN_COVER_M, COVER_RAMP * portal_distance)
    # Justo en la boca (mismo nodo que el último punto de superficie) no se
    # limita: ahí manda la cota del suelo ya suavizada.
    cap = np.where(tunnel & (portal_distance >= 1.0), ground - cover, inf)
    cap_envelope = lipschitz_min(cap, s, MAX_SLOPE)

    # 3. Límites que imponen los puntos fijos con la pendiente máxima.
    upper = lipschitz_min(np.where(is_hard, known, inf), s, MAX_SLOPE)
    lower = lipschitz_max(np.where(is_hard, known, -inf), s, MAX_SLOPE)
    upper = np.minimum(upper, cap_envelope)

    # 4. Estaciones estimadas: dentro de los límites y coherentes entre sí.
    soft_index = sorted(i for i in soft_points if not is_hard[i])
    targets = {}
    for i in soft_index:
        targets[i] = min(max(soft_points[i], lower[i]), upper[i])
    for a, b in zip(soft_index, soft_index[1:]):
        targets[b] = min(targets[b], targets[a] + MAX_SLOPE * (s[b] - s[a]))
    for a, b in zip(reversed(soft_index[:-1]), reversed(soft_index[1:])):
        targets[a] = min(targets[a], targets[b] + MAX_SLOPE * (s[b] - s[a]))
    for i, value in targets.items():
        known[i] = value

    # 5. Interpolación lineal entre puntos conocidos y tope del recubrimiento.
    idx = np.flatnonzero(~np.isnan(known))
    if len(idx) == 0:
        rail = ground - DEFAULT_DEPTH_M
    else:
        rail = np.interp(s, s[idx], known[idx])
    # En los puntos no fijados: tope del recubrimiento, pero sin bajar más de lo
    # que permite la pendiente máxima desde los puntos fijos (bocas de túnel).
    free = np.isnan(known)
    limited = np.maximum(np.minimum(rail, cap_envelope), lower)
    rail = np.where(free, limited, rail)
    adjusted = {i: float(rail[i]) for i in soft_index}
    return rail, adjusted


# --------------------------------------------------------------------------
# Programa principal
# --------------------------------------------------------------------------

def read_csv_rows(path, **kwargs):
    with open(path, encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle, **kwargs))


def to_float(text):
    try:
        return float(str(text).strip())
    except (TypeError, ValueError):
        return None


def main() -> None:
    nodes, ways, rels = load_osm()
    dem = Dem()

    # ---- Rutas -----------------------------------------------------------
    routes = []
    for rel in rels.values():
        tags = rel.get("tags", {})
        if tags.get("type") == "route" and tags.get("ref") in LINE_INFO:
            sequence = route_sequence(rel, ways)
            routes.append({
                "rel": rel,
                "linea": tags["ref"],
                "desde": tags.get("from", ""),
                "hasta": tags.get("to", ""),
                "seq": sequence,
                "largo": sum(way_length(ways[w]) for w, _ in sequence),
            })
    if not routes:
        raise SystemExit("No hay relaciones de ruta en raw/osm.json")

    main_routes = []
    for line, terminals in ROUTE_TERMINALS.items():
        for direction, (start, end) in enumerate(terminals):
            candidates = [
                r for r in routes
                if r["linea"] == line and norm(r["desde"]) == norm(start) and norm(r["hasta"]) == norm(end)
            ]
            if not candidates:
                raise SystemExit(f"No encuentro en OSM la ruta {line} {start} -> {end}")
            best = max(candidates, key=lambda r: r["largo"])
            best["id"] = f"{line}-{direction}"
            best["nombre"] = f"{start} → {end}"
            main_routes.append(best)
    other_routes = [r for r in routes if "id" not in r]

    # ---- Vías ------------------------------------------------------------
    way_lines: dict[int, set[str]] = defaultdict(set)
    for route in routes:
        for way_id, _ in route["seq"]:
            way_lines[way_id].add(route["linea"])

    vias = {}
    for way_id in way_lines:
        way = ways[way_id]
        tags = way.get("tags", {})
        points = densify(way["geometry"])
        lon = np.array([p[0] for p in points])
        lat = np.array([p[1] for p in points])
        ground = dem.sample(lon, lat)
        if np.any(np.isnan(ground)):
            raise SystemExit(f"El way {way_id} sale del relieve descargado")
        tracks = tags.get("tracks", "1")
        vias[way_id] = {
            "id": f"w{way_id}",
            "lineas": sorted(way_lines[way_id]),
            "tunel": tags.get("tunnel", "no") != "no",
            "puente": tags.get("bridge", "no") != "no",
            "pistas": int(tracks) if str(tracks).isdigit() else 1,
            "lon": lon,
            "lat": lat,
            "suelo": ground,
            "carril": None,
        }

    def route_points(route):
        """Puntos de la ruta: (via, índice dentro de la vía) y distancia recorrida.

        El nodo que comparten dos tramos consecutivos aparece dos veces (una por
        vía) a distancia cero, para que cada vía reciba su cota en ese punto.
        """
        refs = []
        for way_id, inv in route["seq"]:
            count = len(vias[way_id]["lon"])
            order = range(count - 1, -1, -1) if inv else range(count)
            refs.extend((way_id, k) for k in order)
        lon = np.array([vias[w]["lon"][k] for w, k in refs])
        lat = np.array([vias[w]["lat"][k] for w, k in refs])
        s = np.zeros(len(refs))
        for i in range(1, len(refs)):
            s[i] = s[i - 1] + dist_m(lon[i - 1], lat[i - 1], lon[i], lat[i])
        return refs, lon, lat, s

    def project(lon_pts, lat_pts, lon, lat):
        """Índice del punto más cercano y su distancia en metros."""
        east, north = local_xy_arrays(lon_pts, lat_pts, lon, lat)
        d2 = east * east + north * north
        i = int(np.argmin(d2))
        return i, float(math.sqrt(d2[i]))

    def local_xy_arrays(lon_pts, lat_pts, lon0, lat0):
        east = EARTH_RADIUS * np.radians(lon_pts - lon0) * math.cos(math.radians(lat0))
        north = EARTH_RADIUS * np.radians(lat_pts - lat0)
        return east, north

    # ---- Estaciones --------------------------------------------------------
    # Se agrupan las paradas (stop_position) de todas las rutas por nombre y cercanía.
    stop_lines: dict[int, set[str]] = defaultdict(set)
    for route in routes:
        for member in route["rel"]["members"]:
            if member["type"] == "node" and member["role"].startswith("stop") and member["ref"] in nodes:
                stop_lines[member["ref"]].add(route["linea"])

    clusters: list[dict] = []
    for node_id, lines in stop_lines.items():
        node = nodes[node_id]
        name = node.get("tags", {}).get("name", "")
        target = None
        for cluster in clusters:
            if cluster["key"] == norm(name) and dist_m(node["lon"], node["lat"], cluster["lon"], cluster["lat"]) < 200:
                # Casco Viejo tiene dos cavernas (L1/L2 y L3): no se mezclan.
                if (cluster["lineas"] <= {"L3"}) == (lines <= {"L3"}):
                    target = cluster
                    break
        if target is None:
            target = {"key": norm(name), "nombre_osm": name, "nodos": [], "lineas": set(), "lon": node["lon"], "lat": node["lat"]}
            clusters.append(target)
        target["nodos"].append(node_id)
        target["lineas"] |= lines
        target["lon"] = sum(nodes[n]["lon"] for n in target["nodos"]) / len(target["nodos"])
        target["lat"] = sum(nodes[n]["lat"] for n in target["nodos"]) / len(target["nodos"])

    # GTFS: estaciones padre y sus andenes.
    gtfs_stops = read_csv_rows(RAW / "gtfs" / "gtfs" / "stops.txt")
    gtfs_parents = {}
    gtfs_children = defaultdict(list)
    code_to_parent = {}
    for row in gtfs_stops:
        stop_id = row["stop_id"].strip()
        location_type = row["location_type"].strip()
        parent = row["parent_station"].strip()
        if location_type == "1":
            gtfs_parents[stop_id] = row
        elif location_type == "0" and parent:
            gtfs_children[parent].append(stop_id)
            if row["stop_code"].strip():
                code_to_parent[row["stop_code"].strip()] = parent

    osm_station_nodes = [n for n in nodes.values() if n.get("tags", {}).get("railway") == "station"]
    stations = []
    unmatched_gtfs = dict(gtfs_parents)
    for cluster in clusters:
        station = {
            "nombre": cluster["nombre_osm"],
            "lon": cluster["lon"],
            "lat": cluster["lat"],
            "lineas": sorted(cluster["lineas"]),
            "nodos": cluster["nodos"],
            "paradas": [],
            "bocas": [],
        }
        match = None
        if cluster["lineas"] & {"L1", "L2"}:
            for stop_id, row in gtfs_parents.items():
                if norm(row["stop_name"]) == cluster["key"]:
                    match = stop_id
                    break
        if match is not None:
            row = gtfs_parents[match]
            station["id"] = match
            station["nombre"] = row["stop_name"].strip()
            station["paradas"] = [match] + sorted(gtfs_children[match])
            unmatched_gtfs.pop(match, None)
        else:
            # Línea 3 (Euskotren): no está en el GTFS de Metro Bilbao.
            best = None
            for node in osm_station_nodes:
                if norm(node["tags"].get("name", "")) != cluster["key"]:
                    continue
                d = dist_m(node["lon"], node["lat"], cluster["lon"], cluster["lat"])
                if best is None or d < best[0]:
                    best = (d, node["id"])
            station["id"] = f"osm-{best[1]}" if best and best[0] < 400 else f"osm-{cluster['nodos'][0]}"
        stations.append(station)
    if unmatched_gtfs:
        names = ", ".join(r["stop_name"].strip() for r in unmatched_gtfs.values())
        print(f"AVISO: estaciones del GTFS sin pareja en OSM: {names}")
    by_id = {s["id"]: s for s in stations}
    if len(by_id) != len(stations):
        raise SystemExit("Hay identificadores de estación repetidos")

    # ---- Bocas ---------------------------------------------------------------
    entrances = {n["id"]: n for n in nodes.values() if n.get("tags", {}).get("railway") == "subway_entrance"}
    node_station = {}
    for station in stations:
        for node_id in station["nodos"]:
            node_station[node_id] = station["id"]
    station_node_ids = {}
    for station in stations:
        if station["id"].startswith("osm-"):
            station_node_ids[int(station["id"][4:])] = station["id"]
    for node in osm_station_nodes:
        # Nodo railway=station de OSM -> estación nuestra con el mismo nombre más cercana.
        best = None
        for station in stations:
            if norm(station["nombre"]) != norm(node["tags"].get("name", "")):
                continue
            d = dist_m(node["lon"], node["lat"], station["lon"], station["lat"])
            if d < 300 and (best is None or d < best[0]):
                best = (d, station["id"])
        if best and node["id"] not in station_node_ids:
            station_node_ids[node["id"]] = best[1]

    assigned: dict[int, str] = {}
    in_any_area: set[int] = set()
    for rel in rels.values():
        if rel.get("tags", {}).get("public_transport") != "stop_area":
            continue
        members = [m["ref"] for m in rel["members"] if m["type"] == "node"]
        owner = None
        for ref in members:
            if ref in node_station:
                owner = node_station[ref]
                break
        if owner is None:
            for ref in members:
                if ref in station_node_ids:
                    owner = station_node_ids[ref]
                    break
        for ref in members:
            if ref in entrances:
                in_any_area.add(ref)
                if owner is not None:
                    assigned.setdefault(ref, owner)
    for ref, node in entrances.items():
        if ref in assigned or ref in in_any_area:
            continue  # las de otras redes (Renfe, funicular...) se descartan
        best = None
        for station in stations:
            d = dist_m(node["lon"], node["lat"], station["lon"], station["lat"])
            if d < 250 and (best is None or d < best[0]):
                best = (d, station["id"])
        if best:
            assigned[ref] = best[1]

    # Bocas publicadas por Metro Bilbao (estaciones.csv): dan nombre a las bocas
    # de OSM sin nombre y cubren las estaciones que no tienen bocas en OSM.
    official: dict[str, list[dict]] = defaultdict(list)
    csv_path = RAW / "gtfs" / "estaciones.csv"
    if csv_path.exists():
        with open(csv_path, encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle, delimiter=";")
            next(reader, None)
            by_code: dict[str, list[dict]] = defaultdict(list)
            for row in reader:
                if len(row) < 5:
                    continue
                lat, lon = to_float(row[3]), to_float(row[4])
                if lat is None or lon is None:
                    continue
                by_code[row[1].strip()].append({"nombre": row[2].strip(), "lat": lat, "lon": lon})
        for code, items in by_code.items():
            if code in code_to_parent and code_to_parent[code] in by_id:
                official[code_to_parent[code]].extend(items)
                continue
            # Códigos sin andén en el GTFS (MOY, ZZA...): estación más cercana.
            c_lat = sum(i["lat"] for i in items) / len(items)
            c_lon = sum(i["lon"] for i in items) / len(items)
            l3_code = code.startswith("ZZ")
            best = None
            for station in stations:
                if l3_code != (station["id"].startswith("osm-")):
                    continue
                d = dist_m(c_lon, c_lat, station["lon"], station["lat"])
                if d < 400 and (best is None or d < best[0]):
                    best = (d, station["id"])
            if best:
                official[best[1]].extend(items)

    for ref, station_id in assigned.items():
        node = entrances[ref]
        tags = node.get("tags", {})
        name = tags.get("name", "")
        if not name:
            near = [
                (dist_m(node["lon"], node["lat"], o["lon"], o["lat"]), o["nombre"])
                for o in official.get(station_id, [])
            ]
            near = [n for n in near if n[0] < 35]
            if near:
                name = min(near)[1]
            elif tags.get("highway") == "elevator":
                name = "Ascensor"
        by_id[station_id]["bocas"].append({"nombre": name, "lat": node["lat"], "lon": node["lon"]})
    for station in stations:
        if not station["bocas"]:
            seen = set()
            for item in official.get(station["id"], []):
                key = (round(item["lat"], 5), round(item["lon"], 5))
                if key in seen:
                    continue
                seen.add(key)
                station["bocas"].append({"nombre": item["nombre"], "lat": item["lat"], "lon": item["lon"]})
    # Casco Viejo: las dos cavernas comparten bocas.
    for a in stations:
        for b in stations:
            if a is b or norm(a["nombre"]) != norm(b["nombre"]):
                continue
            if dist_m(a["lon"], a["lat"], b["lon"], b["lat"]) < 300:
                known = {(x["lat"], x["lon"]) for x in a["bocas"]}
                a["bocas"].extend(dict(x) for x in b["bocas"] if (x["lat"], x["lon"]) not in known)
    for station in stations:
        for boca in station["bocas"]:
            ground = dem.at(boca["lon"], boca["lat"])
            boca["cotaSuelo"] = None if math.isnan(ground) else ground
        station["bocas"] = [b for b in station["bocas"] if b["cotaSuelo"] is not None]
        station["bocas"].sort(key=lambda b: (b["nombre"], b["lat"], b["lon"]))
        station["cotaSuelo"] = dem.at(station["lon"], station["lat"])

    # ---- depths.csv --------------------------------------------------------
    depth_fields = ["stop_id", "nombre", "cota_carril_m", "desnivel_medido_m", "cota_boca_m", "metodo", "fecha"]
    depths_path = TOOLS / "depths.csv"
    depth_rows = read_csv_rows(depths_path) if depths_path.exists() else []
    depth_by_id = {}
    for row in depth_rows:
        key = (row.get("stop_id") or "").strip()
        if key:
            depth_by_id[key] = row
        else:
            # Filas sin stop_id (como la de ejemplo del plan): se casan por nombre.
            for station in stations:
                if norm(station["nombre"]) == norm(row.get("nombre", "")) and station["id"] not in depth_by_id:
                    row["stop_id"] = station["id"]
                    depth_by_id[station["id"]] = row
                    break
    for station in sorted(stations, key=lambda s: (s["id"].startswith("osm-"), s["nombre"])):
        if station["id"] not in depth_by_id:
            row = {f: "" for f in depth_fields}
            row.update({"stop_id": station["id"], "nombre": station["nombre"], "metodo": "estimado"})
            depth_rows.append(row)
            depth_by_id[station["id"]] = row
    with open(depths_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=depth_fields, extrasaction="ignore")
        writer.writeheader()
        for row in depth_rows:
            if (row.get("stop_id") or "").strip():
                writer.writerow(row)

    for station in stations:
        row = depth_by_id[station["id"]]
        method = (row.get("metodo") or "estimado").strip() or "estimado"
        rail = to_float(row.get("cota_carril_m"))
        if rail is None:
            drop = to_float(row.get("desnivel_medido_m"))
            mouth = to_float(row.get("cota_boca_m"))
            if drop is not None and mouth is not None:
                # Medición con barómetro: de la boca al andén; el carril va 1,05 m más abajo.
                rail = mouth - abs(drop) - PLATFORM_ABOVE_RAIL_M
                if method == "estimado":
                    method = "medido"
        if rail is not None and method == "estimado":
            method = "proyecto"
        station["cota_dato"] = rail
        station["origenCota"] = method if rail is not None else "estimado"
        lowest = min((b["cotaSuelo"] for b in station["bocas"]), default=station["cotaSuelo"])
        station["cota_estimada"] = lowest - DEFAULT_DEPTH_M

    # ---- Puntos de control ---------------------------------------------------
    control_points = []
    control_path = TOOLS / "control_points.csv"
    if control_path.exists():
        for row in read_csv_rows(control_path):
            lon, lat, rail = to_float(row.get("lon")), to_float(row.get("lat")), to_float(row.get("cota_carril_m"))
            if None not in (lon, lat, rail):
                control_points.append({"lon": lon, "lat": lat, "cota": rail, "nota": row.get("nota", "")})

    # ---- Cotas del carril, ruta a ruta ----------------------------------------
    station_samples: dict[str, list[float]] = defaultdict(list)
    station_tunnel: dict[str, list[bool]] = defaultdict(list)
    used_control = set()
    for route in main_routes + sorted(other_routes, key=lambda r: -r["largo"]):
        refs, lon, lat, s = route_points(route)
        ground = np.array([vias[w]["suelo"][k] for w, k in refs])
        tunnel = np.array([vias[w]["tunel"] for w, _ in refs])
        bridge = np.array([vias[w]["puente"] for w, _ in refs]) & ~tunnel
        if bridge.any():
            # El MDT no incluye los puentes y junto a los estribos da la cota del
            # paso inferior: esos metros también se interpolan.
            near = np.abs(s[:, None] - s[bridge][None, :]).min(axis=1) <= BRIDGE_MARGIN_M
            bridge = (bridge | near) & ~tunnel

        hard: dict[int, float] = {}
        soft: dict[int, float] = {}
        # Vías ya calculadas por una ruta anterior: se respetan tal cual.
        for i, (w, k) in enumerate(refs):
            if vias[w]["carril"] is not None:
                hard[i] = float(vias[w]["carril"][k])
        for number, point in enumerate(control_points):
            i, d = project(lon, lat, point["lon"], point["lat"])
            if d <= 40 and i not in hard:
                hard[i] = point["cota"]
                used_control.add(number)
        route_stations = []
        stop_ids = {m["ref"] for m in route["rel"]["members"] if m["type"] == "node" and m["role"].startswith("stop")}
        for station in stations:
            if not stop_ids & set(station["nodos"]):
                continue
            i, d = project(lon, lat, station["lon"], station["lat"])
            if d > 60:
                continue
            route_stations.append((station, i))
            if not tunnel[i] or i in hard:
                continue
            if station["cota_dato"] is not None:
                hard[i] = station["cota_dato"]
            else:
                soft[i] = station["cota_estimada"]

        rail, _ = rail_profile(s, ground, tunnel, bridge, hard, soft)
        for w, _ in route["seq"]:
            if vias[w]["carril"] is None:
                vias[w]["carril"] = np.full(len(vias[w]["lon"]), np.nan)
        for i, (w, k) in enumerate(refs):
            if math.isnan(vias[w]["carril"][k]):
                vias[w]["carril"][k] = rail[i]
        if "id" in route:
            for station, i in route_stations:
                station_samples[station["id"]].append(float(rail[i]))
                station_tunnel[station["id"]].append(bool(tunnel[i]))

    for number, point in enumerate(control_points):
        if number not in used_control:
            print(f"AVISO: el punto de control {number + 1} ({point['nota']}) no cae a menos de 40 m de ninguna ruta")

    for station in stations:
        samples = station_samples.get(station["id"])
        if not samples:
            raise SystemExit(f"La estación {station['nombre']} no cae sobre ninguna ruta principal")
        station["cotaCarril"] = sum(samples) / len(samples)
        station["subterranea"] = any(station_tunnel[station["id"]])
        if station["subterranea"] and station["cotaCarril"] > station["cotaSuelo"] - 1:
            # El suelo justo encima puede ser un desmonte: se usa como referencia la boca.
            pass

    # ---- relieve.bin -----------------------------------------------------------
    all_lon = np.concatenate([v["lon"] for v in vias.values()])
    all_lat = np.concatenate([v["lat"] for v in vias.values()])
    lat_mid = float((all_lat.min() + all_lat.max()) / 2)
    step_lat = round(math.degrees(GRID_STEP_M / EARTH_RADIUS), 9)
    step_lon = round(math.degrees(GRID_STEP_M / (EARTH_RADIUS * math.cos(math.radians(lat_mid)))), 9)
    margin = CORRIDOR_M + 5 * GRID_STEP_M
    margin_lat = math.degrees(margin / EARTH_RADIUS)
    margin_lon = math.degrees(margin / (EARTH_RADIUS * math.cos(math.radians(lat_mid))))
    origin_lon = round(float(all_lon.min()) - margin_lon, 7)
    origin_lat = round(float(all_lat.min()) - margin_lat, 7)
    n_cols = int(math.ceil((float(all_lon.max()) + margin_lon - origin_lon) / step_lon)) + 1
    n_rows = int(math.ceil((float(all_lat.max()) + margin_lat - origin_lat) / step_lat)) + 1

    # Máscara del pasillo: discos de 400 m alrededor de los puntos de las vías.
    mask = np.zeros((n_rows, n_cols), dtype=bool)
    cell_m_lat = step_lat * math.pi / 180 * EARTH_RADIUS
    radius_rows = int(math.ceil(CORRIDOR_M / cell_m_lat))
    for via in vias.values():
        for k in range(0, len(via["lon"]), 4):
            row = int(round((via["lat"][k] - origin_lat) / step_lat))
            col = int(round((via["lon"][k] - origin_lon) / step_lon))
            cell_m_lon = step_lon * math.pi / 180 * EARTH_RADIUS * math.cos(math.radians(via["lat"][k]))
            radius_cols = int(math.ceil(CORRIDOR_M / cell_m_lon))
            r0, r1 = max(row - radius_rows, 0), min(row + radius_rows + 1, n_rows)
            c0, c1 = max(col - radius_cols, 0), min(col + radius_cols + 1, n_cols)
            rr, cc = np.ogrid[r0:r1, c0:c1]
            disk = ((rr - row) * cell_m_lat) ** 2 + ((cc - col) * cell_m_lon) ** 2 <= CORRIDOR_M ** 2
            mask[r0:r1, c0:c1] |= disk
    grid_lon = origin_lon + np.arange(n_cols) * step_lon
    grid_lat = origin_lat + np.arange(n_rows) * step_lat
    rows_idx, cols_idx = np.nonzero(mask)
    values = dem.sample(grid_lon[cols_idx], grid_lat[rows_idx])
    grid = np.full((n_rows, n_cols), NODATA, dtype="<i2")
    ok = ~np.isnan(values)
    grid[rows_idx[ok], cols_idx[ok]] = np.clip(np.rint(values[ok] * 10), -32767, 32767).astype("<i2")
    RESOURCES.mkdir(parents=True, exist_ok=True)
    (RESOURCES / "relieve.bin").write_bytes(grid.tobytes(order="C"))
    print(
        f"relieve.bin: {n_rows} filas x {n_cols} columnas, "
        f"{int(ok.sum())} celdas con dato ({100 * ok.sum() / grid.size:.1f} %), "
        f"{int((~ok).sum())} del pasillo sin dato"
    )

    # ---- metro.json --------------------------------------------------------------
    def r7(value):
        return round(float(value), 7)

    def r1(value):
        return round(float(value), 1)

    out_vias = []
    for way_id in sorted(vias):
        via = vias[way_id]
        if via["carril"] is None or np.any(np.isnan(via["carril"])):
            raise SystemExit(f"La vía {via['id']} se ha quedado sin cota de carril")
        out_vias.append({
            "id": via["id"],
            "lineas": via["lineas"],
            "tunel": bool(via["tunel"]),
            "pistas": via["pistas"],
            "puntos": [
                [r7(via["lon"][k]), r7(via["lat"][k]), r1(via["carril"][k]), r1(via["suelo"][k])]
                for k in range(len(via["lon"]))
            ],
        })
    out_routes = [
        {
            "id": route["id"],
            "linea": route["linea"],
            "nombre": route["nombre"],
            "tramos": [{"via": f"w{w}", "inv": bool(inv)} for w, inv in route["seq"]],
        }
        for route in main_routes
    ]
    line_order = {line: i for i, line in enumerate(LINE_INFO)}
    out_stations = []
    for station in sorted(stations, key=lambda s: (line_order[s["lineas"][0]], s["id"].startswith("osm-"), s["nombre"])):
        out_stations.append({
            "id": station["id"],
            "nombre": station["nombre"],
            "lat": r7(station["lat"]),
            "lon": r7(station["lon"]),
            "cotaCarril": r1(station["cotaCarril"]),
            "cotaSuelo": r1(station["cotaSuelo"]),
            "subterranea": bool(station["subterranea"]),
            "origenCota": station["origenCota"],
            "lineas": station["lineas"],
            "paradas": station["paradas"],
            "bocas": [
                {"nombre": b["nombre"], "lat": r7(b["lat"]), "lon": r7(b["lon"]), "cotaSuelo": r1(b["cotaSuelo"])}
                for b in station["bocas"]
            ],
        })
    network = {
        "version": 1,
        "generado": datetime.date.today().isoformat(),
        "atribucion": [
            "© OpenStreetMap contributors (ODbL)",
            "Metro Bilbao",
            "CTB",
            "geoEuskadi (CC BY 4.0)",
        ],
        "lineas": [{"id": line, **info} for line, info in LINE_INFO.items()],
        "vias": out_vias,
        "rutas": out_routes,
        "estaciones": out_stations,
        "relieve": {
            "paso_m": int(GRID_STEP_M) if float(GRID_STEP_M).is_integer() else GRID_STEP_M,
            "origen": [origin_lon, origin_lat],
            "paso_lon": step_lon,
            "paso_lat": step_lat,
            "filas": n_rows,
            "columnas": n_cols,
            "sin_dato": NODATA,
            "fichero": "relieve.bin",
        },
    }
    out_path = RESOURCES / "metro.json"
    out_path.write_text(json.dumps(network, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    total_points = sum(len(v["puntos"]) for v in out_vias)
    print(
        f"metro.json: {len(out_vias)} vías, {total_points} puntos, {len(out_routes)} rutas, "
        f"{len(out_stations)} estaciones, {sum(len(s['bocas']) for s in out_stations)} bocas, "
        f"{out_path.stat().st_size} bytes"
    )


if __name__ == "__main__":
    main()
