"""Utilidades compartidas por los scripts del pipeline de datos."""
from __future__ import annotations

import math
import sys
import time
from pathlib import Path

# En este PC un antivirus intercepta TLS y su raíz solo está en el almacén de
# Windows. truststore hace que Python use ese almacén sin desactivar la
# verificación. Si no está instalado, se sigue con los certificados de certifi.
try:  # pragma: no cover
    import truststore

    truststore.inject_into_ssl()
except Exception:  # noqa: BLE001
    pass

import requests

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
RAW = TOOLS / "raw"
RESOURCES = ROOT / "App" / "Resources"

USER_AGENT = "MetroRayosX-data-pipeline/1.0 (script de uso personal)"

# Recuadro que cubre las líneas 1, 2 y 3 con margen: sur, oeste, norte, este.
BBOX = (43.20, -3.10, 43.42, -2.85)

EARTH_RADIUS = 6_378_137.0

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def session() -> requests.Session:
    s = requests.Session()
    s.headers["User-Agent"] = USER_AGENT
    return s


def download(url: str, dest: Path, *, force: bool = False, timeout: int = 180, **kwargs) -> Path:
    """Descarga `url` en `dest` si no existe ya (caché en raw/)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0 and not force:
        print(f"  en caché: {dest.relative_to(TOOLS)}")
        return dest
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with session().get(url, timeout=timeout, stream=True, **kwargs) as response:
                response.raise_for_status()
                tmp = dest.with_suffix(dest.suffix + ".part")
                with open(tmp, "wb") as handle:
                    for chunk in response.iter_content(1 << 16):
                        handle.write(chunk)
                tmp.replace(dest)
            print(f"  descargado: {dest.relative_to(TOOLS)} ({dest.stat().st_size} bytes)")
            return dest
        except Exception as error:  # noqa: BLE001
            last_error = error
            print(f"  intento {attempt + 1} fallido: {error}")
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"No se pudo descargar {url}: {last_error}")


def local_xy(lon: float, lat: float, lon0: float, lat0: float) -> tuple[float, float]:
    """Metros (este, norte) respecto a (lon0, lat0), aproximación plana del plan."""
    east = EARTH_RADIUS * math.radians(lon - lon0) * math.cos(math.radians(lat0))
    north = EARTH_RADIUS * math.radians(lat - lat0)
    return east, north


def dist_m(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Distancia horizontal en metros entre dos puntos cercanos."""
    # El coseno se toma en la latitud media, pero la diferencia de latitud es
    # la completa: pasar la latitud media como origen a local_xy la dejaría a la mitad.
    east = EARTH_RADIUS * math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    north = EARTH_RADIUS * math.radians(lat2 - lat1)
    return math.hypot(east, north)
