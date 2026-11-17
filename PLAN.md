# Metro Bilbao Rayos X — Plan maestro

17 de noviembre de 2026

## Estado

Actualizado el 17 de noviembre de 2026. Las nueve fases están escritas y el código está en GitHub, pero solo una parte está probada: GitHub Actions todavía no ha ejecutado ninguna compilación, así que la app no se ha compilado con Xcode ni se ha probado en el iPhone.

| Parte | Escrita | Probada |
| --- | --- | --- |
| Datos (Fase 1, con la línea 3) | Sí | Sí: `validate.py` da 0 fallos y 4 avisos |
| Núcleo `MetroCore` (lógica de las fases 2 a 7) | Sí | Sí: 143 tests en un contenedor Linux, con los datos reales |
| App (pantallas, AR, mapa, medición) | Sí | A medias: compila en Linux contra réplicas de los frameworks de Apple (`tools\check-app.ps1`); sin compilar con Xcode y sin probar en el iPhone |
| Workflows de GitHub Actions | Sí | No: nunca se han ejecutado |

Lo que falta, por orden:

1. Conseguir que GitHub Actions ejecute los workflows (el primer intento no llegó a arrancar).
2. Corregir los errores que dé la primera compilación de la app con Xcode.
3. Instalar el `.ipa` con SideStore y hacer las pruebas de calle de cada fase.
4. Apuntar aquí el resultado del botón «¿Hay geotracking?» (Más > Estado y registro). Decide si el Modo A sirve en Bilbao.
5. Medir profundidades reales: las 33 estaciones subterráneas tienen la cota estimada.

Cambios respecto al plan original:

- Los feeds en vivo no dan la posición del tren dentro del túnel, solo la hora de llegada a cada parada. Los trenes se colocan interpolando entre paradas. La línea 3 no tiene trenes en vivo.
- El GTFS-Realtime se decodifica con un lector propio, sin SwiftProtobuf: la app no tiene dependencias externas.
- `metro.json` lleva además las rutas de cada línea (para colocar trenes) y la rejilla de relieve va en grados, con un paso de unos 10 m, para que pese 5 MB.
- Moyua aparece como «Eliptikoa», que es el nombre de la estación en los datos de Metro Bilbao y en OpenStreetMap.
- Los rótulos de la pantalla AR se dibujan en 2D sobre la imagen en lugar de como texto 3D.
- El núcleo se prueba también en este PC con Docker (`tools\test-core.ps1`), sin esperar a GitHub, y la app se comprueba a medias con `tools\check-app.ps1`.
- No hay grabaciones reales todavía: el test de reproducción de sesiones usa una grabación sintética.

## Resumen

La app dibuja el túnel del metro en 3D bajo tus pies y lo superpone a la cámara, de modo que al apuntar al suelo parece que lo atraviesas con la vista. El móvil no detecta nada bajo tierra: coloca un modelo del trazado real usando GPS, brújula y ARKit.

Resultado final esperado:

- Apuntas el iPhone al suelo en Bilbao y ves las vías y las estaciones a su profundidad real, con su nombre y los metros que hay hasta ellas.
- Al andar, el túnel se queda fijo en su sitio, como si estuviera de verdad ahí abajo.
- Opcional: los trenes pasan por debajo en tiempo real.

Supuestos de partida (cámbialos aquí si no se cumplen):

- No tienes Mac: la app se compila en GitHub Actions, que presta un Mac en la nube, y se instala desde el propio iPhone con SideStore. Un PC con Windows hace falta una sola vez, para instalar SideStore. Doy por hecho que el iPhone es compatible con ARKit y tiene iOS 15 o posterior.
- App nativa en Swift: SwiftUI para la interfaz, ARKit + RealityKit para la vista AR, MapKit para el mapa 2D.
- Uso personal y coste cero: se firma con tu cuenta gratuita de Apple al instalarla, sin App Store ni programa de pago.
- Alcance: líneas 1 y 2 primero; la línea 3 después, porque en OpenStreetMap está etiquetada de otra forma.
- Precisión objetivo: 3-5 m en horizontal tras calibrar y 2-3 m en profundidad en las estaciones medidas.

## Cómo usar este plan con Claude Code

Guarda este documento como `PLAN.md` en la raíz del repositorio y trabaja una fase por sesión. Cada fase termina en algo que puedes probar tú en el iPhone antes de pasar a la siguiente.

Prompt inicial para Claude Code:

```text
Lee PLAN.md entero. Vamos a construir la app "Metro Bilbao Rayos X" siguiendo ese plan.
Reglas:
1. Trabaja solo en la fase que te indique. No adelantes fases.
2. Antes de escribir código, dime qué archivos vas a crear o tocar.
3. Toda la lógica que no necesite cámara va en el paquete Swift MetroCore, con tests.
4. No hay Mac: aquí no puedes compilar la app. El proyecto se define en project.yml
   (XcodeGen) y lo compila GitHub Actions. Tras cada push, sigue la ejecución con
   `gh run watch`, lee los errores con `gh run view --log-failed` y corrígelos
   antes de avisarme.
5. Agrupa los cambios: cada compilación tarda minutos y cada instalación la hago yo a mano.
6. Sin Xcode no hay consola: lo que quieras ver del iPhone tiene que escribirse en el
   registro de la app, que yo te enviaré.
7. Cuando una fase necesite una prueba en la calle, dame una lista corta de qué mirar.
8. Si un dato del plan no cuadra con lo que encuentras (URLs, etiquetas de OSM), para y dímelo.
Empieza por la Fase 0.
```

Pide también a Claude Code que cree un `CLAUDE.md` con estas notas fijas:

- Comandos de compilación y test del proyecto.
- Convención de ejes: x = este, y = arriba, z = sur (−z = norte), en metros.
- Los datos del metro se generan con `tools/` y nunca se editan a mano, salvo `depths.csv`.
- No se añaden dependencias externas a la app sin preguntar. El proyecto de Xcode se genera con XcodeGen y no se sube al repositorio; la compilación la hace GitHub Actions.

Lo que Claude Code no puede hacer y te toca a ti: conectar el iPhone, aceptar permisos, descargar el .ipa de GitHub, instalarlo con SideStore, salir a la calle a probar y medir profundidades en las estaciones.

## Qué necesitas conseguir

Coste total: cero, usando el PC y el iPhone que ya tengas.

| Qué | Para qué | Coste | Cómo |
| --- | --- | --- | --- |
| Cuenta de GitHub y repositorio público | Compilar la app en un Mac en la nube (GitHub Actions) | Gratis | github.com |
| iPhone con ARKit | Ejecutar la app | El tuyo | Activa Ajustes > Privacidad y seguridad > Modo de desarrollador |
| Cuenta de Apple | Firmar la app | Gratis | La que ya usas en el iPhone, o una secundaria |
| PC con Windows, iTunes e iloader, solo el primer día | Instalar SideStore en el iPhone y emparejarlo | Gratis | iTunes de Apple; iloader en github.com/nab138/iloader |
| SideStore y LocalDevVPN en el iPhone | Firmar, instalar y renovar la app desde el móvil | Gratis | LocalDevVPN en el App Store; SideStore lo instala iloader |
| Claude Code | Escribir el código | Tu plan de Claude | En tu PC o en la web, conectado al repositorio |
| Python 3 | Scripts de datos | Gratis | python.org |
| Git + repositorio | Historial y vuelta atrás | Gratis | `git init` y subida a GitHub |
| Cable USB | Primera instalación | — | Del iPhone al PC |

Límites de la cuenta gratuita según [Apple](https://developer.apple.com/support/compare-memberships): el perfil caduca a los 7 días, con un máximo de 3 dispositivos, 10 App IDs y 3 apps por dispositivo. Para esta app basta y no hay que pagar nada: SideStore la renueva desde el propio iPhone. SideStore cuenta como una de las 3 apps. El programa de pago de Apple queda fuera del plan.

GitHub Actions es gratis en repositorios públicos con los ejecutores estándar, según [GitHub](https://docs.github.com/en/billing/concepts/product-billing/github-actions). En uno privado, el plan gratuito incluye 12 USD de uso al mes y el minuto de macOS cuesta 0,062 USD: unos 190 minutos de compilación. Recomendación: repositorio público, ya que todos los datos son abiertos y el código no lleva claves.

No hace falta ninguna clave de API: OpenStreetMap, Metro Bilbao, CTB y geoEuskadi publican sus datos en abierto.

## Datos: qué hace falta y de dónde sale

Cuatro de los cinco datos se descargan; el quinto, la profundidad, hay que medirlo o estimarlo porque no existe un fichero público.

| Dato | Fuente | Cómo se obtiene | Licencia |
| --- | --- | --- | --- |
| Trazado de las vías y tramos en túnel | [OpenStreetMap](https://www.openstreetmap.org/relation/7106760) | Consulta Overpass sobre la red «Metro Bilbao» (relación 8692908) | ODbL: citar «© OpenStreetMap contributors» |
| Bocas de estación (fosteritos, ascensores) | OpenStreetMap | Nodos `railway=subway_entrance` en la misma consulta | ODbL |
| Estaciones y horarios | [API de Metro Bilbao](https://www.metrobilbao.eus/es/open-data/dataset/api-guide) | `GET https://cms.metrobilbao.eus/es/get/open_data/horarios/es` (GTFS) y `/estaciones/es` (CSV) | No indicada en la página: revisar el aviso legal |
| Relieve (cota del suelo) | [MDT LiDAR 2017 de geoEuskadi](https://datos.gob.es/es/catalogo/e0dat0002-modelo-digital-del-terreno-mdt-de-1m-de-la-comunidad-autonoma-del-pais-vasco-ano-2017) | Servicio WCS por recuadro, o ZIP de 5 m | CC BY 4.0 |
| Trenes en vivo | [Feeds GTFS-RT del CTB](https://mobilitydatabase.org/feeds/gtfs_rt/mdb-3058) | Tres ficheros `.pb`, sin clave | Aviso legal de data.ctb.eus |
| Profundidad del carril | No hay fuente única | Medición propia + proyectos oficiales + interpolación | Propia |

### Vías (OpenStreetMap)

Las vías del área de Bilbao llevan `tunnel=yes`, `layer` y ancho de vía, con origen en cartografía del Gobierno Vasco. Consulta de partida, a validar en overpass-turbo.eu antes de automatizarla:

```text
[out:json][timeout:180];
rel(8692908)->.red;            // red "Metro Bilbao"
rel(r.red)->.lineas;           // route_master: L1, L2...
rel(r.lineas)->.rutas;         // una ruta por sentido y variante
.rutas out tags;
way(r.rutas)->.vias;
.vias out tags geom;           // vías con su geometría
node(r.rutas);
out body;                      // paradas, con coordenadas
node["railway"="subway_entrance"](43.20,-3.10,43.42,-2.85);
out body;                      // bocas, con coordenadas
```

Puntos a vigilar:

- Los miembros de una ruta incluyen andenes. Quédate solo con las vías cuyo `railway` sea `subway`, `narrow_gauge`, `rail` o `light_rail`.
- La línea 3 circula por vías de Euskal Trenbide Sarea etiquetadas `railway=narrow_gauge`, no `subway`. Su ruta es la relación 7141756 y su sentido contrario; comprueba si cuelga de la red 8692908 y, si no, añádela a mano.
- Cada vía puede ser un `way` propio o un único `way` con `tracks=2`. El pipeline debe tratar los dos casos.

### Estaciones y horarios (Metro Bilbao)

El CSV de estaciones trae `stop_id, stop_name, stop_lat, stop_lon, location_type, parent_station`. La guía de la API tiene URLs de ejemplo mal escritas (falta una barra antes de `get`); la forma correcta es la de la tabla. Mira si el GTFS incluye `shapes.txt`: sirve para contrastar el trazado de OSM. El feed del [Punto de Acceso Nacional](https://mobilitydatabase.org/feeds/gtfs/mdb-2683) sí declara shapes, pero pide registro.

### Relieve (geoEuskadi)

Bilbao tiene cuestas, así que la profundidad cambia aunque el túnel vaya horizontal. Se necesita la cota del suelo en cada punto del trazado y en un pasillo de unos 150 m a cada lado.

- WCS: `https://www.geo.euskadi.eus/WCS_KARTOGRAFIA?request=getcapabilities&service=wcs`. Permite pedir solo los recuadros del pasillo.
- ZIP de 5 m: `https://www.geo.euskadi.eus/lidar/DatosDescarga/MDT_LIDAR_2017_ETRS89/mdt_lidar_2017_5m_etrs89.zip`. Cubre toda Euskadi; pesa más pero es un solo fichero.
- El sistema de referencia parece ETRS89 por el nombre de los ficheros. Confirma el código EPSG en los metadatos antes de reproyectar.

### Trenes en vivo (CTB)

- Posiciones: `https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-vehicle-positions.pb`
- Actualizaciones de viaje: `https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-trip-updates.pb`
- Alertas: `https://ctb-gtfs-rt.s3.eu-south-2.amazonaws.com/metro-bilbao-service-alerts.pb`

Pregunta abierta: no he comprobado si las posiciones traen coordenadas dentro del túnel o solo la parada actual. La Fase 7 empieza descargando el feed y mirándolo.

### Profundidad del carril

Se guarda la cota absoluta del carril (metros sobre el nivel del mar) en cada estación y se interpola entre ellas. Tres fuentes, por orden de fiabilidad:

1. Medición propia con el barómetro del iPhone. Empiezas en la boca, bajas al andén y la app registra el desnivel con `CMAltimeter`. Precisión esperable: 1-2 m. Es una estación por viaje, así que se va completando con el uso.
2. Proyectos oficiales del Gobierno Vasco en euskadi.eus. Los anejos de trazado listan coordenadas UTM y cota del carril cada 20 m en algunos tramos, por ejemplo [Kabiezes](https://www.euskadi.eus/contenidos/informacion/cocheras_kabiezes/eu_def/adjuntos/PB-AN002-Trazado.pdf). Cubren sobre todo ampliaciones recientes.
3. Estimación. Valor provisional de 20 m bajo la boca para estaciones subterráneas sin dato. No tiene fuente: sirve solo para que la app funcione desde el primer día.

Reglas de interpolación:

- En tramos sin `tunnel=yes`, la cota del carril es la del suelo.
- En las bocas de túnel, carril y suelo coinciden.
- Entre dos puntos conocidos, la cota varía de forma lineal con la distancia recorrida por la vía.
- Bajo la ría hay que fijar puntos a mano: en el tramo entre San Ignazio y Gurutzeta/Cruces, el más profundo, el cauce queda unos 12 m por encima del túnel y la pendiente llega al 5,8 %, según [Deia](https://www.deia.eus/bizkaia/2024/03/24/entranas-metropoli-paseo-metro-bilbao-8038217.html).

## Pipeline de datos

Cinco scripts de Python en `tools/` convierten las fuentes en un único `metro.json` que viaja dentro de la app, de modo que la app funciona sin conexión salvo para los trenes en vivo.

1. `fetch_osm.py`: lanza la consulta Overpass contra `https://overpass-api.de/api/interpreter` y guarda `raw/osm.json`.
2. `fetch_gtfs.py`: descarga el GTFS y el CSV de estaciones de Metro Bilbao en `raw/gtfs/`.
3. `fetch_dem.py`: pide al WCS de geoEuskadi los recuadros del pasillo de vías y los guarda en `raw/dem/`.
4. `build_network.py`: une los tramos de OSM en polilíneas continuas por línea y vía, las remuestrea a un punto cada 5 m, asocia estaciones y bocas, calcula cotas con `depths.csv` y escribe `metro.json`.
5. `validate.py`: comprueba el resultado y genera `preview.geojson` para verlo en geojson.io.

Dependencias: `requests`, `shapely`, `pyproj`, `rasterio`, `numpy` y `gtfs-realtime-bindings`. La carpeta `raw/` no se sube a Git.

`depths.csv` es el único fichero que se edita a mano o desde el modo medición de la app:

```csv
stop_id,nombre,cota_carril_m,desnivel_medido_m,cota_boca_m,metodo,fecha
,Moyua,,,,estimado,
```

Formato de `metro.json`:

```json
{
  "version": 1,
  "generado": "2026-11-17",
  "atribucion": ["© OpenStreetMap contributors (ODbL)", "Metro Bilbao", "CTB", "geoEuskadi (CC BY 4.0)"],
  "lineas": [{"id": "L1", "nombre": "Etxebarri - Plentzia", "color": "#rrggbb"}],
  "vias": [{
    "id": "L1L2-0001",
    "lineas": ["L1", "L2"],
    "tunel": true,
    "puntos": [[lon, lat, cotaCarril, cotaSuelo]]
  }],
  "estaciones": [{
    "id": "stop_id del GTFS",
    "nombre": "Moyua",
    "lat": 0.0, "lon": 0.0,
    "cotaCarril": 0.0, "cotaSuelo": 0.0,
    "subterranea": true,
    "origenCota": "medido | proyecto | estimado",
    "bocas": [{"nombre": "", "lat": 0.0, "lon": 0.0, "cotaSuelo": 0.0}]
  }],
  "relieve": {"paso_m": 5, "origen": [lon, lat], "filas": 0, "columnas": 0, "fichero": "relieve.bin"}
}
```

`relieve.bin` es la rejilla de cotas del pasillo en enteros de 16 bits (decímetros). La app la usa para saber a qué altura está el suelo donde pisas.

Comprobaciones de `validate.py`:

- Ningún hueco mayor de 1 m entre tramos consecutivos de una misma vía.
- Cada estación queda a menos de 30 m de una vía.
- El número de estaciones coincide con el del GTFS.
- Ninguna pendiente del carril supera el 6 %; el tramo bajo la ría llega al 5,8 %. Las que lo superen se listan para revisar.
- En túnel, el carril queda siempre por debajo del suelo.

## Arquitectura de la app

La app se divide en un núcleo sin cámara, que se prueba automáticamente en GitHub Actions con `swift test`, y una capa fina de AR que solo se puede probar en el iPhone.

```text
MetroRayosX/
  PLAN.md  CLAUDE.md  project.yml  .github/workflows/
  tools/                      Pipeline de datos en Python
    depths.csv  raw/ (fuera de Git)
  MetroCore/                  Paquete Swift, sin ARKit ni UIKit
    Sources/MetroCore/
      Model.swift             Red, Via, Estacion, Boca
      NetworkLoader.swift     Lee metro.json y relieve.bin
      Geo.swift               Lat/lon <-> metros locales, punto más cercano a una polilínea
      SpatialIndex.swift      Rejilla para pedir "vías a menos de R metros"
      Terrain.swift           Cota del suelo en un punto
      Alignment.swift         Ajuste GPS <-> AR por mínimos cuadrados
      TunnelMesher.swift      Polilínea -> vértices e índices de túnel y raíles
      TrainFeed.swift         Decodifica GTFS-RT y coloca trenes sobre la vía
    Tests/MetroCoreTests/
  App/
    MetroRayosXApp.swift
    Services/
      LocationService.swift   CLLocationManager: posición, precisión y rumbo
      ARSessionController.swift  Configura y vigila la sesión de ARKit
      AltimeterService.swift  CMAltimeter para el modo medición
      RealtimeService.swift   Descarga los .pb cada 15-30 s
      SessionRecorder.swift   Graba GPS + poses AR a JSON para depurar
    Rendering/
      SceneBuilder.swift      Crea y recicla las entidades de RealityKit
      Materials.swift         Materiales sin iluminación, colores por línea
      GroundGrid.swift        Rejilla del suelo
      Labels.swift            Nombres y distancias
    Views/
      MapScreen.swift         Mapa 2D con MapKit
      ARScreen.swift          ARView dentro de SwiftUI
      CalibrationOverlay.swift
      MeasureScreen.swift     Modo medición de profundidad
      DebugHUD.swift
      AboutScreen.swift       Atribuciones de datos
    Resources/ metro.json  relieve.bin
```

Decisiones técnicas:

- RealityKit con `ARView` y sesión de ARKit configurada a mano. Sin oclusión: lo virtual se pinta siempre encima de la cámara, que es justo el efecto rayos X.
- Dos modos de seguimiento, elegidos al arrancar:
  - Modo A, geotracking: `ARGeoTrackingConfiguration` si `checkAvailability` dice que hay cobertura donde estás. Apple coloca la escena con precisión de calle comparándola con sus propias imágenes.
  - Modo B, manual: `ARWorldTrackingConfiguration` con `worldAlignment = .gravityAndHeading`, más el ajuste propio de GPS descrito en «Alineación y calibración». Funciona en cualquier sitio.
- Detección de planos horizontales activada para saber a qué altura está el suelo respecto al móvil.
- Solo se dibuja lo que hay a menos de 400 m. La escena se regenera cuando te alejas 50 m del último centro.
- Sin dependencias externas en la app, salvo SwiftProtobuf para GTFS-RT en la Fase 7.

Claves de `Info.plist`: `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSMotionUsageDescription` y `arkit` en `UIRequiredDeviceCapabilities`.

Requisitos del Modo A según [Apple](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration): chip A12 o posterior, iPhone con GPS, conexión a internet y uso en exteriores. La cobertura abarca zonas de más de 20 países, Europa incluida, pero la documentación no lista ciudades: si Bilbao entra se averigua en la Fase 0.

## Matemáticas clave

Todo se reduce a pasar latitud, longitud y cota a metros alrededor de ti, con los ejes de ARKit: x = este, y = arriba, z = sur.

De coordenadas geográficas a metros locales, respecto a un punto de referencia (latitud y longitud en radianes, R = 6 378 137 m). El error es menor de 1 m a varios kilómetros:

```latex
\begin{aligned}
E &= R\,(\lambda - \lambda_0)\cos\varphi_0 \\
N &= R\,(\varphi - \varphi_0)
\end{aligned}
```

Posición de un punto de la vía en la escena, donde y_suelo es la altura del plano del suelo detectado por ARKit (o −1,4 m si aún no hay plano):

```latex
\begin{aligned}
x &= E \\
z &= -N \\
y &= y_{suelo} + (cota_{carril} - cota_{suelo,\,usuario})
\end{aligned}
```

La profundidad que se muestra en pantalla es cota del suelo donde pisas menos cota del carril.

Ajuste GPS-AR (Modo B). Cada lectura de GPS con precisión mejor de 15 m da una pareja: g_i, su posición en metros locales ya pasada a ejes de escena (x = E, z = −N), y a_i, la posición (x, z) del móvil en la escena en ese instante. Se busca el giro θ y el desplazamiento t que mejor las casan, con peso w_i = 1/precisión²:

```latex
\min_{\theta,\,t}\ \sum_i w_i\,\lVert R(\theta)\,g_i + t - a_i \rVert^2
```

Tiene solución directa, con las coordenadas centradas en sus medias ponderadas:

```latex
\begin{aligned}
\theta &= \operatorname{atan2}\Big(\sum_i w_i\,(g'_i \times a'_i),\ \sum_i w_i\,(g'_i \cdot a'_i)\Big) \\
t &= \bar a - R(\theta)\,\bar g
\end{aligned}
```

Reglas de uso:

- Ventana deslizante de las últimas 30-60 parejas.
- Con menos de 20 m andados, θ no se puede estimar: se fija θ = 0, se confía en la brújula y solo se calcula t.
- El resultado se aplica suavizado, medio metro por segundo como máximo, para que el túnel no dé saltos.
- Ojo con el signo de z al pasar de norte a la escena: es el error más probable. Debe haber un test que lo fije.

## Fases de construcción

Nueve fases, cada una con una prueba que haces tú antes de seguir. Las fases 0 a 3 dan ya una primera versión que enseña el túnel; el resto la hace fiel.

| Fase | Qué sale | Quién la prueba |
| --- | --- | --- |
| 0. Arranque | App vacía en tu iPhone y respuesta a «¿hay geotracking en Bilbao?» | Tú, en casa |
| 1. Datos | `metro.json` validado | Claude Code + tú en geojson.io |
| 2. Mapa 2D | Mapa con vías, estaciones y tu posición | Tú, en una boca de metro |
| 3. AR básica | Túnel bajo el suelo a profundidad fija | Tú, en la calle |
| 4. Profundidad real | Cotas reales, estaciones y modo medición | Tú, en una estación |
| 5. Alineación | El túnel cuadra con la calle y no deriva | Tú, andando 100 m |
| 6. Aspecto rayos X | Efecto visual convincente | Tú |
| 7. Trenes en vivo | Trenes moviéndose bajo tus pies | Tú, junto a una estación |
| 8. Pulido | Avisos, atribuciones, línea 3 | Tú |

### Fase 0. Arranque

- [ ] Crear el repositorio público en GitHub, el `project.yml` de XcodeGen y el paquete local `MetroCore`.
- [ ] Workflow `build.yml` en un ejecutor `macos-latest`: genera el proyecto con XcodeGen, compila con `xcodebuild archive` sin firmar (`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`), mete el `.app` en una carpeta `Payload/`, la comprime como `.ipa` y la publica como fichero de una Release, para poder descargarla desde Safari en el iPhone.
- [ ] Workflow `test.yml`: `swift test` de `MetroCore` en cada push.
- [x] Crear `CLAUDE.md` con los comandos de `gh` para seguir las compilaciones.
- [ ] Pantalla única que muestre latitud, longitud, precisión del GPS y rumbo.
- [ ] Botón «¿Hay geotracking?» que llame a `ARGeoTrackingConfiguration.checkAvailability(at:)` para tu posición, Moyua y Zazpikaleak/Casco Viejo.
- [ ] Registro en fichero con botón de compartir: sin Xcode es la única forma de ver qué pasa dentro de la app.
- [ ] Instalar en el iPhone siguiendo «Pruebas e instalación».

Hecho cuando: GitHub Actions produce el .ipa, SideStore lo instala, la app abre en el iPhone, muestra tu posición y el resultado del botón queda apuntado en `PLAN.md`. Ese resultado decide si la Fase 5 usa el Modo A. Esta fase valida toda la cadena sin Mac: si no se consigue instalar, se pasa al plan B antes de invertir más.

### Fase 1. Datos

- [x] Escribir los cinco scripts de «Pipeline de datos».
- [x] Rellenar `depths.csv` con todas las estaciones en `estimado`.
- [ ] Buscar en euskadi.eus los anejos de trazado disponibles y pasar a `depths.csv` las cotas que aparezcan, con `metodo = proyecto`.

Hecho cuando: `validate.py` pasa y `preview.geojson` muestra en geojson.io las líneas enteras, sin huecos y sobre las calles correctas.

### Fase 2. Mapa 2D

- [x] `MetroCore`: `Model`, `NetworkLoader`, `Geo`, `SpatialIndex`, `Terrain`, con tests.
- [ ] `MapScreen`: vías por color de línea, estaciones, bocas y tu posición.
- [ ] Panel inferior: estación más cercana, distancia a la vía y metros bajo tus pies.

Hecho cuando: de pie junto a una boca, la app nombra la estación correcta y te sitúa a menos de 15 m de ella.

### Fase 3. AR básica

- [ ] `ARScreen` y `ARSessionController` en Modo B.
- [ ] `TunnelMesher`: dos raíles por vía y un anillo de túnel cada 10 m, a 15 m de profundidad fija.
- [ ] Rejilla del suelo a la altura del plano detectado.
- [ ] `DebugHUD`: precisión del GPS, estado del seguimiento, rumbo, número de entidades e imágenes por segundo.

Hecho cuando: en una calle bajo la que pasa el metro, el túnel aparece bajo ella con la dirección correcta y se queda quieto al andar 20 m. Un error de hasta 15 m es aceptable todavía.

### Fase 4. Profundidad real y estaciones

- [ ] Usar `cotaCarril` y `relieve.bin` en lugar de la profundidad fija.
- [ ] Dibujar cada estación como una caverna con su nombre y su profundidad.
- [ ] `MeasureScreen`: pulsar Inicio en la boca, bajar al andén, pulsar Fin; guarda el desnivel de `CMAltimeter` y permite compartir la fila para `depths.csv`.
- [ ] Marcar en pantalla las profundidades que sean `estimado`.

Hecho cuando: en una estación medida, la profundidad mostrada coincide con la medición con un margen de 3 m, y al subir una cuesta la profundidad aumenta.

### Fase 5. Alineación

- [x] `Alignment.swift` con tests de trayectorias sintéticas: con 8 m de ruido y 15° de giro, recupera el giro con 3° de margen y el desplazamiento con 3 m.
- [ ] `SessionRecorder` y tests que reproduzcan grabaciones reales.
- [ ] `CalibrationOverlay`: un dedo mueve, dos dedos giran, botón «Estoy en esta boca» con las tres más cercanas, botón de reinicio.
- [ ] Modo A si la Fase 0 dio cobertura: `ARGeoTrackingConfiguration` con un `ARGeoAnchor` como origen de la escena, y caída al Modo B si falla.

Hecho cuando: tras fijarte en una boca y andar 100 m, el túnel sigue bajo la calle con menos de 5 m de error.

### Fase 6. Aspecto rayos X

- [ ] Rejilla del suelo que se desvanece con la distancia y una «ventana» circular bajo tus pies.
- [ ] Túnel con brillo del color de la línea y desvanecido hacia los 400 m.
- [ ] Etiquetas de estación que miran a la cámara, con distancia y profundidad.
- [ ] Línea vertical desde tus pies hasta la vía con los metros.
- [ ] Mallas agrupadas en tramos de 100 m para mantener 60 imágenes por segundo.

Hecho cuando: se entiende de un vistazo qué está cerca, qué lejos y a qué profundidad, sin tirones.

### Fase 7. Trenes en vivo

- [ ] Script que descargue los tres feeds y vuelque su contenido, para ver si las posiciones traen coordenadas.
- [ ] Si las traen: proyectar cada tren sobre la vía más cercana. Si no: interpolar entre paradas con las actualizaciones de viaje y el horario.
- [ ] `RealtimeService` cada 15-30 s y movimiento interpolado entre lecturas.
- [ ] Tren dibujado como una caja del largo de una unidad, con el color de su línea.

Hecho cuando: junto a una estación, el tren dibujado llega a la vez que el real con un margen de 20 s.

### Fase 8. Pulido

- [ ] Avisos claros: GPS impreciso, interior, sin conexión para trenes.
- [ ] `AboutScreen` con las atribuciones de OpenStreetMap, Metro Bilbao, CTB y geoEuskadi.
- [ ] Añadir la línea 3.
- [ ] Icono y pantalla de permisos.

## Alineación y calibración

Este es el punto que decide si la app convence: el GPS falla 5-10 m entre edificios y la brújula 10-20°, suficiente para que el túnel salga bajo la acera de enfrente o girado respecto a la calle.

Modo A, geotracking de Apple. Si hay cobertura, ARKit compara la cámara con imágenes de calle de Apple y sitúa la escena sin calibrar nada. Solo funciona en exteriores, con conexión y en calles por las que haya pasado el coche de Apple, así que el Modo B hace falta igualmente.

Modo B, tres capas que se suman:

1. Arranque. La escena se orienta al norte con la brújula y se sitúa con la primera lectura buena de GPS. Sirve para ver algo, con error visible.
2. Ajuste por trayectoria. Mientras andas, el algoritmo de «Matemáticas clave» compara tu recorrido según el GPS con tu recorrido según ARKit. ARKit mide bien la forma del recorrido y el GPS su posición media, así que juntos corrigen giro y desplazamiento. Necesita unos 20-30 m andados.
3. Anclaje en una boca. Te colocas en la entrada de una estación y pulsas «Estoy en esta boca». La app toma la coordenada exacta de esa boca como tu posición. Es lo más preciso y lo recomendable al empezar cada sesión.

Ajuste manual, siempre disponible: arrastrar con un dedo desplaza el túnel y girar con dos dedos lo rota. La corrección manual se guarda como un desplazamiento extra encima del ajuste automático.

Cuándo avisar al usuario:

- Precisión del GPS peor de 20 m: «Señal débil, acércate a una boca y ánclate».
- ARKit en estado limitado: «Mueve el móvil despacio y apunta a una zona con detalle».
- Rumbo con precisión peor de 25°: «Aléjate de coches o estructuras metálicas».

## Pruebas e instalación

La instalación es gratuita y sin Mac: GitHub Actions genera el .ipa sin firmar y SideStore lo firma con tu cuenta de Apple y lo instala en el propio iPhone. El PC solo se usa el primer día.

Preparación, una sola vez y con un PC ([guía paso a paso](https://wezlemin.github.io/delta-docs/docs/external-sideloading/sidestore-tutorial)):

1. En el iPhone, pon un código de desbloqueo si no lo tienes y activa Ajustes > Privacidad y seguridad > Modo de desarrollador. El iPhone se reinicia.
2. Instala LocalDevVPN desde el App Store, ábrela, pulsa Connect y acepta el perfil de VPN. Si no aparece en el App Store, la guía da una fuente alternativa para usuarios de la UE.
3. En el PC, con Windows de 64 bits, instala iTunes y después iloader desde `github.com/nab138/iloader`.
4. Conecta el iPhone por cable, abre iloader, entra con tu cuenta de Apple y escribe el código de verificación que aparece en el iPhone.
5. Elige tu iPhone y pulsa «SideStore (Stable)». iloader instala SideStore y coloca el fichero de emparejamiento.
6. En el iPhone: Ajustes > General > VPN y gestión de dispositivos > confía en la app de desarrollador de tu cuenta.
7. Abre SideStore, inicia sesión con la misma cuenta de Apple y pulsa el contador «7 DAYS» junto a SideStore para renovarla.

Cada versión nueva, solo con el iPhone:

1. Conecta LocalDevVPN.
2. En Safari, abre la página de Releases del repositorio y descarga el `.ipa`.
3. En SideStore, entra en My Apps, pulsa + y elige el `.ipa` en Archivos.
4. Abre la app.

Renovación: con LocalDevVPN conectada, SideStore renueva las apps antes de que caduquen; si alguna caduca, se pulsa su contador en My Apps. Tras actualizar iOS o restablecer el iPhone, el emparejamiento puede perderse y hay que repetir los pasos 4 y 5 con el PC.

iloader y SideStore te piden la contraseña de tu cuenta de Apple. No tiene que ser la cuenta con la que usas el iPhone: si prefieres, crea una secundaria solo para esto.

Cada cambio tarda unos minutos en llegar al iPhone: compilar en GitHub, descargar e instalar. Por eso conviene agrupar cambios y dejar que los tests cacen los errores antes.

Dónde probar, por orden:

1. Un tramo en superficie. Los raíles dibujados deben coincidir con los reales, que están a la vista: es la única prueba con verdad absoluta.
2. Una boca de estación en una calle ancha, con buen GPS.
3. Una calle estrecha entre edificios altos, el peor caso para el GPS.
4. Una cuesta, para comprobar que la profundidad cambia con el relieve.

Qué apuntar en cada prueba: precisión del GPS que marca el panel de depuración, error horizontal a ojo, y cuánto se ha movido el túnel tras andar 100 m y volver.

Cuando algo falle, graba la sesión con `SessionRecorder`, envíate el fichero al PC y dáselo a Claude Code: puede reproducirlo en un test y ajustar el algoritmo sin que vuelvas a salir.

Precauciones: párate para mirar la pantalla y no cruces mirando el móvil. La AR calienta el teléfono y gasta batería rápido.

## Riesgos, límites y plan B

El riesgo mayor es el ciclo lento de prueba sin Mac: cada cambio tarda en llegar al iPhone y no hay depurador. Los demás tienen arreglo dentro del plan.

| Riesgo | Qué pasaría | Qué se hace |
| --- | --- | --- |
| Sin Mac no hay consola ni depurador | Los fallos en el iPhone cuestan más de diagnosticar | Registro en fichero, panel de depuración y tests en GitHub Actions |
| GPS malo entre edificios | Túnel desplazado varios metros | Anclaje en boca, ajuste por trayectoria, Modo A |
| Brújula desviada por metal | Túnel girado respecto a la calle | Ajuste por trayectoria y giro manual |
| Profundidades sin dato | Cotas inventadas en muchas estaciones | Modo medición; marcar «estimado» en pantalla |
| Trazado de OSM incompleto o viejo | Huecos o vías mal situadas | Contrastar con `shapes.txt` del GTFS; `validate.py` |
| El feed en vivo no da posición en túnel | Trenes a saltos de estación en estación | Interpolar con horario y actualizaciones de viaje |
| ARKit deriva en paseos largos | El túnel se va moviendo | Recentrado cada 50 m y ajuste continuo |
| La app caduca a los 7 días | Deja de abrirse | Renovarla en SideStore con LocalDevVPN conectada |
| Cambian las URLs de los datos | Los scripts fallan | Están aisladas en `tools/`; la app no depende de ellas salvo los trenes |
| SideStore deja de funcionar tras un cambio de Apple | No se puede instalar la app | Instalar el .ipa desde el PC con iloader o Sideloadly; si no, plan B |
| Se pierde el emparejamiento al actualizar iOS | SideStore no instala ni renueva | Repetir el paso de iloader con el PC |

Límites que no se pueden salvar:

- La app funciona en la calle. Dentro del metro no hay GPS.
- La precisión horizontal no bajará de unos pocos metros sin el Modo A.
- La profundidad entre estaciones es una interpolación, no un dato medido.

Plan B, versión web, por si la cadena de GitHub Actions y SideStore fallara. Una página con la cámara de fondo, three.js para el 3D, la orientación del móvil y la geolocalización del navegador, alojada gratis en GitHub Pages y abierta en Safari. Reutiliza `metro.json` y todo el pipeline de datos. Pierde el seguimiento de ARKit: el túnel gira bien al mover el móvil, pero al andar depende solo del GPS y tiembla. Sirve como demostración, no como versión fiel.

## Fuentes

Páginas consultadas el 17 de noviembre de 2026:

- [Guía de la API de datos abiertos de Metro Bilbao](https://www.metrobilbao.eus/es/open-data/dataset/api-guide)
- [Metro Bilbao, posiciones de vehículos (Mobility Database)](https://mobilitydatabase.org/feeds/gtfs_rt/mdb-3058)
- [Metro Bilbao, actualizaciones de viaje (Mobility Database)](https://mobilitydatabase.org/feeds/gtfs_rt/mdb-3057)
- [Metro Bilbao, alertas de servicio (Mobility Database)](https://mobilitydatabase.org/feeds/gtfs_rt/mdb-3056)
- [Metro Bilbao, GTFS del Punto de Acceso Nacional (Mobility Database)](https://mobilitydatabase.org/feeds/gtfs/mdb-2683)
- [Relación L1 de Metro Bilbao en OpenStreetMap](https://www.openstreetmap.org/relation/7106760)
- [MDT LiDAR 2017 del País Vasco (datos.gob.es)](https://datos.gob.es/es/catalogo/e0dat0002-modelo-digital-del-terreno-mdt-de-1m-de-la-comunidad-autonoma-del-pais-vasco-ano-2017)
- [Anejo de trazado de las cocheras de Kabiezes (Gobierno Vasco)](https://www.euskadi.eus/contenidos/informacion/cocheras_kabiezes/eu_def/adjuntos/PB-AN002-Trazado.pdf)
- [En las entrañas de la metrópoli (Deia)](https://www.deia.eus/bizkaia/2024/03/24/entranas-metropoli-paseo-metro-bilbao-8038217.html)
- [ARGeoTrackingConfiguration (Apple)](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration)
- [Choosing a Membership (Apple)](https://developer.apple.com/support/compare-memberships)
- [Facturación de GitHub Actions (GitHub)](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Instalación de SideStore con iloader, paso a paso](https://wezlemin.github.io/delta-docs/docs/external-sideloading/sidestore-tutorial)
- [Preguntas frecuentes de Sideloadly, alternativa desde el PC](https://sideloadly.io/faq)

Sin comprobar en fuente: las etiquetas exactas de las bocas en OpenStreetMap, el contenido real del feed de posiciones, el aviso legal de data.ctb.eus y el valor provisional de 20 m de profundidad. Están marcados en el plan como cosas a verificar.
