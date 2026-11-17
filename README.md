# Metro Bilbao Rayos X

App de iOS que dibuja el túnel del metro de Bilbao en realidad aumentada: apuntas el iPhone al suelo y ves las vías y las estaciones a su profundidad real. El móvil no detecta nada bajo tierra; coloca un modelo del trazado usando GPS, brújula y ARKit.

Proyecto personal, sin relación con Metro Bilbao, el Consorcio de Transportes de Bizkaia ni Euskotren. El plan completo y el estado de cada fase están en [PLAN.md](PLAN.md).

## Qué hace

- **Mapa:** las líneas 1, 2 y 3 con sus estaciones y bocas, tu posición, la estación más cercana y los metros de tierra que hay entre tus pies y la vía.
- **Rayos X:** el túnel, las estaciones y las bocas dibujados sobre la cámara, con una rejilla en el suelo y una línea vertical con la profundidad. Se alinea con el GPS al andar y, mejor, anclándote en una boca de metro.
- **Trenes en vivo:** los trenes de las líneas 1 y 2 moviéndose por el mapa y por el túnel, a partir de los datos abiertos del CTB.
- **Medir:** mide con el barómetro lo que bajas de la boca al andén, para sustituir las profundidades estimadas por reales.

## Estado

El código de todas las fases está escrito. Los datos y la lógica (`MetroCore`) están probados con tests; la app aún no se ha compilado ni probado en un iPhone. Las profundidades de las estaciones subterráneas son estimaciones hasta que se midan.

## Instalación

La app se compila en GitHub Actions y se instala sin Mac con SideStore. Los pasos están en el apartado «Pruebas e instalación» de [PLAN.md](PLAN.md). El `.ipa` más reciente estará en [Releases](../../releases/latest).

## Datos

- Trazado y bocas: © OpenStreetMap contributors (ODbL).
- Estaciones y horarios: Metro Bilbao, datos abiertos publicados por el CTB (CC BY 4.0).
- Trenes en vivo: Consorcio de Transportes de Bizkaia, feeds GTFS-Realtime (CC BY 4.0).
- Relieve: geoEuskadi, MDT LiDAR 2017 (CC BY 4.0).

Los datos se regeneran con los scripts de `tools/`; las instrucciones están en [CLAUDE.md](CLAUDE.md).
