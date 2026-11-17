"""Descarga de OpenStreetMap las vías, rutas, paradas y bocas del metro.

Una sola consulta Overpass, guardada en raw/osm.json. Usa --force para repetirla.
"""
from __future__ import annotations

import json
import sys
import time

from common import BBOX, RAW, session

OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

# Red "Metro Bilbao" (8692908) -> route_master de cada línea -> rutas.
# La línea 3 la explota Euskotren y puede no colgar de esa red: se añade a
# mano a partir de su ruta 7141756 y del route_master que la contiene.
QUERY = """
[out:json][timeout:180];
rel(8692908)->.red;
rel(r.red)->.lineas;
rel(7141756)->.l3;
rel(br.l3)->.l3m;
(.lineas; .l3m;)->.maestras;
(rel(r.maestras); .l3;)->.rutas;
.red out tags;
.maestras out body;
.rutas out body;
way(r.rutas);
out body geom;
node(r.rutas);
out body;
(
  node["railway"="subway_entrance"]({s},{w},{n},{e});
  node["railway"="station"]["station"~"subway|light_rail"]({s},{w},{n},{e});
  node["railway"="station"]["network"~"Metro Bilbao|Euskotren"]({s},{w},{n},{e});
)->.sueltos;
.sueltos out body;
rel["public_transport"="stop_area"]({s},{w},{n},{e});
out body;
""".format(s=BBOX[0], w=BBOX[1], n=BBOX[2], e=BBOX[3])


def main() -> None:
    dest = RAW / "osm.json"
    if dest.exists() and "--force" not in sys.argv:
        print(f"en caché: {dest}")
        return
    RAW.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for url in OVERPASS_URLS:
        for attempt in range(2):
            try:
                print(f"consultando {url} ...")
                response = session().post(url, data={"data": QUERY}, timeout=240)
                response.raise_for_status()
                data = response.json()
                if not data.get("elements"):
                    raise RuntimeError("respuesta sin elementos")
                dest.write_text(json.dumps(data), encoding="utf-8")
                print(f"guardado {dest} con {len(data['elements'])} elementos")
                return
            except Exception as error:  # noqa: BLE001
                last_error = error
                print(f"  fallo: {error}")
                time.sleep(15)
    raise SystemExit(f"Overpass no respondió: {last_error}")


if __name__ == "__main__":
    main()
