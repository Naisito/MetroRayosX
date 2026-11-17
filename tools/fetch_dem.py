"""Descarga el relieve (MDT LiDAR 2017 de 5 m, geoEuskadi) del pasillo de vías.

Pide al servicio WCS solo las teselas de 2 km que tocan el pasillo y las guarda
como GeoTIFF en raw/dem/. Sistema de referencia confirmado con DescribeCoverage:
EPSG:25830 (ETRS89 / UTM 30N), rejilla nativa de 5 m.
"""
from __future__ import annotations

import json
import sys
import time

from pyproj import Transformer

from common import RAW, session

WCS_URL = "https://www.geo.euskadi.eus/WCS_KARTOGRAFIA"
COVERAGE = "MDT_LIDAR_2017_5M"
EPSG = 25830
# Esquina de la rejilla nativa (DescribeCoverage) para pedir teselas alineadas.
GRID_X0 = 462975
GRID_Y0 = 4702000
TILE_M = 2000
PIXEL_M = 5
MARGIN_M = 600  # el pasillo de relieve.bin es de 400 m; se deja holgura

TRACK_RAILWAYS = {"subway", "narrow_gauge", "rail", "light_rail"}


def corridor_tiles() -> list[tuple[int, int]]:
    osm = json.loads((RAW / "osm.json").read_text(encoding="utf-8"))
    to_utm = Transformer.from_crs(4326, EPSG, always_xy=True)
    tiles: set[tuple[int, int]] = set()
    for element in osm["elements"]:
        if element["type"] != "way" or element.get("tags", {}).get("railway") not in TRACK_RAILWAYS:
            continue
        for vertex in element["geometry"]:
            x, y = to_utm.transform(vertex["lon"], vertex["lat"])
            for dx in (-MARGIN_M, 0, MARGIN_M):
                for dy in (-MARGIN_M, 0, MARGIN_M):
                    tiles.add((
                        int((x + dx - GRID_X0) // TILE_M),
                        int((y + dy - GRID_Y0) // TILE_M),
                    ))
    return sorted(tiles)


def tile_path(ix: int, iy: int):
    return RAW / "dem" / f"mdt5_{ix}_{iy}.tif"


def main() -> None:
    force = "--force" in sys.argv
    tiles = corridor_tiles()
    print(f"{len(tiles)} teselas de {TILE_M} m")
    (RAW / "dem").mkdir(parents=True, exist_ok=True)
    http = session()
    size = TILE_M // PIXEL_M
    for number, (ix, iy) in enumerate(tiles, 1):
        dest = tile_path(ix, iy)
        if dest.exists() and dest.stat().st_size > 1000 and not force:
            continue
        x0 = GRID_X0 + ix * TILE_M
        y0 = GRID_Y0 + iy * TILE_M
        params = {
            "service": "WCS",
            "version": "1.0.0",
            "request": "GetCoverage",
            "coverage": COVERAGE,
            "CRS": f"EPSG:{EPSG}",
            "BBOX": f"{x0},{y0},{x0 + TILE_M},{y0 + TILE_M}",
            "WIDTH": size,
            "HEIGHT": size,
            "FORMAT": "GeoTIFF",
        }
        for attempt in range(4):
            try:
                response = http.get(WCS_URL, params=params, timeout=240)
                response.raise_for_status()
                if not response.content.startswith((b"II*", b"MM\x00*")):
                    raise RuntimeError(f"respuesta no TIFF: {response.content[:200]!r}")
                dest.write_bytes(response.content)
                print(f"  [{number}/{len(tiles)}] {dest.name}")
                break
            except Exception as error:  # noqa: BLE001
                print(f"  [{number}/{len(tiles)}] intento {attempt + 1} fallido: {error}")
                time.sleep(5 * (attempt + 1))
        else:
            raise SystemExit(f"No se pudo descargar la tesela {ix},{iy}")
        time.sleep(0.3)
    print("relieve descargado en raw/dem/")


if __name__ == "__main__":
    main()
