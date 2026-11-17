"""Descarga los tres feeds GTFS-RT del CTB para Metro Bilbao y vuelca su contenido.

  python dump_realtime.py             resumen y primeras entidades de cada feed
  python dump_realtime.py --all       todas las entidades
  python dump_realtime.py --fixtures  además guarda las muestras que usan los tests de MetroCore
"""
from __future__ import annotations

import json
import sys

from google.protobuf.json_format import MessageToDict
from google.transit import gtfs_realtime_pb2

from common import RAW, ROOT, session

BASE = "https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-"
FEEDS = ["vehicle-positions", "trip-updates", "service-alerts"]
FIXTURES = ROOT / "MetroCore" / "Tests" / "MetroCoreTests" / "Fixtures"


def main() -> None:
    show_all = "--all" in sys.argv
    out = RAW / "rt"
    out.mkdir(parents=True, exist_ok=True)
    http = session()
    for name in FEEDS:
        response = http.get(f"{BASE}{name}.pb", timeout=60)
        response.raise_for_status()
        (out / f"{name}.pb").write_bytes(response.content)
        message = gtfs_realtime_pb2.FeedMessage()
        message.ParseFromString(response.content)
        data = MessageToDict(message, preserving_proto_field_name=True)
        entities = data.get("entity", [])
        print(f"== {name}: {len(response.content)} bytes, {len(entities)} entidades, "
              f"Last-Modified {response.headers.get('Last-Modified')}")
        print("   cabecera:", json.dumps(data.get("header"), ensure_ascii=False))
        for entity in entities if show_all else entities[:3]:
            print("  ", json.dumps(entity, ensure_ascii=False))
        if "--fixtures" in sys.argv and name != "service-alerts":
            FIXTURES.mkdir(parents=True, exist_ok=True)
            (FIXTURES / f"{name}.pb").write_bytes(response.content)
            print(f"   guardado en {FIXTURES / (name + '.pb')} "
                  "(recuerda actualizar feeds-resumen.json y los tests que dependan de sus valores)")


if __name__ == "__main__":
    main()
