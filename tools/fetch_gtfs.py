"""Descarga el GTFS y el CSV de estaciones de Metro Bilbao en raw/gtfs/.

Usa --force para volver a descargar.
"""
from __future__ import annotations

import sys
import zipfile

from common import RAW, download

GTFS_URL = "https://cms.metrobilbao.eus/es/get/open_data/horarios/es"
STATIONS_URL = "https://cms.metrobilbao.eus/es/get/open_data/estaciones/es"


def main() -> None:
    force = "--force" in sys.argv
    out = RAW / "gtfs"
    gtfs_zip = download(GTFS_URL, out / "gtfs.zip", force=force)
    download(STATIONS_URL, out / "estaciones.csv", force=force)

    if zipfile.is_zipfile(gtfs_zip):
        with zipfile.ZipFile(gtfs_zip) as archive:
            archive.extractall(out / "gtfs")
            print("  ficheros del GTFS:", ", ".join(sorted(archive.namelist())))
    else:
        head = gtfs_zip.read_bytes()[:200]
        raise SystemExit(f"El GTFS descargado no es un ZIP. Empieza por: {head!r}")


if __name__ == "__main__":
    main()
