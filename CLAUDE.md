# Metro Bilbao Rayos X

App de iOS que dibuja el túnel del metro de Bilbao en AR bajo tus pies. El plan original está en `PLAN.md`; el apartado «Estado» del principio dice qué está hecho, qué está probado y qué falta.

## Compilación y tests

No hay Mac ni Swift en este PC (Windows). Hay tres niveles de comprobación:

1. **Núcleo (`MetroCore`), en local con Docker.** Con Docker Desktop arrancado:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\test-core.ps1
   ```

   Copia el paquete y los datos a un contenedor `swift:6.0`, compila y pasa cada test en su propio proceso. Termina con una línea `tests: N  ok: N  fallidos: 0`. No montes carpetas de Windows en el contenedor (`docker run -v`): Docker pide permiso en una ventana y el comando se queda colgado. No ejecutes `swift test` a secas dentro del contenedor: el XCTest de Linux se cuelga a veces al cerrar un test.

2. **App, comprobación parcial en local con Docker.**

   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\check-app.ps1
   ```

   Compila todos los fuentes de `App/` contra módulos de pega con los nombres de los frameworks de Apple (`tools/appcheck/Stubs`) y el `MetroCore` real. Caza errores de lenguaje, de llamadas a `MetroCore`, de acceso, de tipos y de aislamiento de actores. No garantiza que compile en Xcode: las firmas de Apple de los módulos de pega están escritas a mano. Si usas una API de Apple que no está en `Stubs`, añádela con su firma real (compruébala en developer.apple.com).

3. **App de verdad (SwiftUI, ARKit, RealityKit), solo en GitHub Actions.**
   - `test.yml`: `swift test --package-path MetroCore` en cada push.
   - `build.yml`: en cada push a `main` que toque `App/`, `MetroCore/`, `project.yml` o el propio workflow. Pasa los tests, genera el proyecto con `xcodegen generate`, compila sin firmar con `xcodebuild archive` y publica `MetroRayosX.ipa` en una Release `build-N`.

   ```bash
   gh run list --limit 5                 # ejecuciones recientes
   gh run watch <id> --exit-status       # seguir una hasta que acabe
   gh run view <id> --log-failed         # errores de la que falle
   gh release list --limit 5             # .ipa publicados
   ```

   Corrige los errores de compilación antes de avisar al usuario. Agrupa los cambios: cada compilación tarda minutos y cada instalación en el iPhone es manual (SideStore).

El repositorio es `Naisito/MetroRayosX` (público). Subir correcciones para que la app compile está autorizado; cualquier otra publicación, pregúntala.

Si un job falla sin pasos ni registro, no es un error del código sino de la cuenta o de los ejecutores, y lo tiene que resolver el usuario. Mira las anotaciones del job antes de tocar nada:

```bash
gh api repos/Naisito/MetroRayosX/actions/runs/<id>/jobs --jq ".jobs[0].id"
gh api repos/Naisito/MetroRayosX/check-runs/<job>/annotations --jq ".[].message"
```

## Datos

```bash
cd tools
.venv/Scripts/python.exe fetch_osm.py      # --force para repetir la descarga
.venv/Scripts/python.exe fetch_gtfs.py
.venv/Scripts/python.exe fetch_dem.py
.venv/Scripts/python.exe build_network.py  # escribe App/Resources/metro.json y relieve.bin
.venv/Scripts/python.exe validate.py       # código 1 si hay fallos; escribe preview.geojson
.venv/Scripts/python.exe dump_realtime.py  # vuelca los feeds en vivo del CTB
```

El venv se crea con `py -3.11 -m venv tools\.venv` y `pip install -r tools\requirements.txt`. Un antivirus intercepta TLS en este PC: los scripts usan `truststore`; para pip, `--cert tools\.venv\win-roots.pem`.

Después de regenerar los datos, pasa `tools\test-core.ps1`: varios tests cargan la red real.

Cosas que no son obvias en los datos:

- Moyua se llama «Eliptikoa» en el GTFS y en OSM (estación `8`).
- Zazpikaleak/Casco Viejo son dos estaciones: `6` (L1/L2) y `osm-5294695227` (L3).
- Las estaciones de la L3 llevan id `osm-<nodo>` y no tienen `paradas`: no hay trenes en vivo de la L3.
- Todas las cotas de carril subterráneas son `estimado` (20 m bajo la boca más baja, ajustado para no pasar del 5,5 % de pendiente). Los tres cruces bajo la ría están en `tools/control_points.csv` con valores estimados.
- Feeds en vivo: `route_id` es siempre "MB" (la línea se deduce de las paradas), `direction_id` vale 1 o 2, solo hay hora de llegada por parada y las posiciones solo listan trenes parados en estación. Urduliz llega con el `stop_id` de Gobela (`20.0`); `TrainLocator` lo corrige.

## Reglas fijas

- Convención de ejes de la escena: x = este, y = arriba, z = sur (−z = norte), en metros. El único sitio donde se cambia el signo del norte es `LocalFrame` (MetroCore). El giro del plano y el giro 3D alrededor de +y llevan signo contrario (`RigidTransform2D.yawAroundY`); hay tests que lo fijan.
- Toda la lógica que no necesite cámara va en el paquete `MetroCore` (sin ARKit ni UIKit, y compilable en Linux: nada de `import simd` ni de `String(format:)` con `%@`), con tests.
- Los datos del metro se generan con `tools/` y nunca se editan a mano, salvo `tools/depths.csv` y `tools/control_points.csv`.
- No se añaden dependencias externas a la app sin preguntar. El GTFS-Realtime se decodifica con un lector protobuf propio (`TrainFeed.swift`).
- El proyecto de Xcode se genera con XcodeGen a partir de `project.yml` y no se sube al repositorio. `App/Info.plist` también lo genera XcodeGen: las claves se cambian en `project.yml`.
- Destino mínimo iOS 15: nada de APIs de iOS 16 o posterior (`NavigationStack`, `ShareLink`, `LabeledContent`…) sin comprobar disponibilidad.
- Las clases que tocan RealityKit (`ARExperience`, `SceneBuilder`, `GroundGrid`, `Materials`, `MeshFactory`, `LabelProjector`) son `@MainActor`. No uses `Timer` ni cierres `@Sendable` para llamarlas: el trabajo periódico sale del callback de cada imagen.
- Sin Xcode no hay consola: lo que haya que ver del iPhone se escribe con `AppLog.shared.write(_:category:)`. El usuario envía `metro-rayosx.log` desde Más > Estado y registro.
- El repositorio es público: los commits usan el correo `noreply` de GitHub configurado en este repositorio. No subas claves ni datos personales.

## Estructura

- `App/`: app SwiftUI.
  - `Services/`: ubicación, sesión de ARKit (modos A y B), trenes en vivo, barómetro, grabación de sesiones, registro.
  - `Rendering/`: `ARExperience` (une sesión, ajuste y escena), `SceneBuilder`, materiales, rejilla, rótulos.
  - `Views/`: mapa, rayos X, medición, bienvenida, estado, acerca de.
  - `Resources/`: `metro.json`, `relieve.bin`, catálogo de recursos (icono).
- `MetroCore/`: paquete Swift con la lógica y sus tests. `Tests/MetroCoreTests/Fixtures/` tiene muestras reales de los feeds.
- `tools/`: pipeline de datos en Python, `make_icon.py` y el script de tests en Docker. `tools/raw/` no se sube a Git.
- `.github/workflows/`: `test.yml` y `build.yml`.
