# Metro Bilbao Rayos X

App de iOS que dibuja el túnel del metro de Bilbao en realidad aumentada: apuntas el iPhone al suelo y ves las vías y las estaciones a su profundidad real. El móvil no detecta nada bajo tierra; coloca un modelo del trazado usando GPS, brújula y ARKit.

Proyecto personal, en construcción por fases. El plan completo está en [PLAN.md](PLAN.md).

## Estado

Fase 0: la app muestra posición, precisión del GPS y rumbo, comprueba si hay geotracking de ARKit en Bilbao y guarda un registro que se puede compartir.

## Instalación

La app se compila en GitHub Actions y se instala sin Mac con SideStore. Los pasos están en el apartado «Pruebas e instalación» de [PLAN.md](PLAN.md).

El .ipa más reciente está en [Releases](../../releases/latest).

## Datos

- Trazado y bocas: © OpenStreetMap contributors (ODbL).
- Estaciones y horarios: Metro Bilbao.
- Trenes en vivo: Consorcio de Transportes de Bizkaia.
- Relieve: geoEuskadi, MDT LiDAR 2017 (CC BY 4.0).
