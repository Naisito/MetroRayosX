# Metro Bilbao Rayos X

App de iOS que dibuja el túnel del metro de Bilbao en AR bajo tus pies. El plan completo está en `PLAN.md`: léelo entero antes de tocar nada y trabaja solo en la fase que te indiquen.

## Compilación y tests

No hay Mac ni Swift en este PC (Windows): nada se compila en local. Todo pasa por GitHub Actions en `Naisito/MetroRayosX`.

- `test.yml`: `swift test --package-path MetroCore` en cada push.
- `build.yml`: en cada push a `main` que toque `App/`, `MetroCore/`, `project.yml` o el propio workflow. Pasa los tests, genera el proyecto con `xcodegen generate`, compila sin firmar con `xcodebuild archive` y publica `MetroRayosX.ipa` en una Release `build-N`.

Tras cada `git push`:

```bash
gh run list --limit 5                 # ejecuciones recientes
gh run watch <id> --exit-status       # seguir una hasta que acabe
gh run view <id> --log-failed         # errores de la que falle
gh release list --limit 5             # .ipa publicados
gh workflow run build.yml             # recompilar sin cambios
```

Corrige los errores de compilación antes de avisar al usuario. Agrupa los cambios: cada compilación tarda minutos y cada instalación en el iPhone es manual (SideStore).

El .ipa más reciente está siempre en `https://github.com/Naisito/MetroRayosX/releases/latest/download/MetroRayosX.ipa`.

## Reglas fijas

- Convención de ejes de la escena: x = este, y = arriba, z = sur (−z = norte), en metros.
- Toda la lógica que no necesite cámara va en el paquete `MetroCore` (sin ARKit ni UIKit), con tests.
- Los datos del metro se generan con `tools/` y nunca se editan a mano, salvo `tools/depths.csv`.
- No se añaden dependencias externas a la app sin preguntar.
- El proyecto de Xcode se genera con XcodeGen a partir de `project.yml` y no se sube al repositorio. `App/Info.plist` también lo genera XcodeGen: las claves se cambian en `project.yml`.
- Destino mínimo iOS 15: nada de APIs de iOS 16 o posterior (`NavigationStack`, `ShareLink`, `LabeledContent`…) sin comprobar disponibilidad.
- Sin Xcode no hay consola: lo que haya que ver del iPhone se escribe con `AppLog.shared.write(_:category:)`. El usuario envía el fichero `metro-rayosx.log` con el botón «Compartir registro».
- Si un dato del plan no cuadra con lo que encuentras (URLs, etiquetas de OSM), para y díselo al usuario.
- El repositorio es público: los commits usan el correo `noreply` de GitHub configurado en este repositorio. No subas claves ni datos personales.

## Estructura

- `App/`: app SwiftUI. `Services/` (ubicación, registro, geotracking), `Views/`.
- `MetroCore/`: paquete Swift con la lógica y sus tests.
- `tools/`: pipeline de datos en Python (Fase 1). `tools/raw/` no se sube a Git.
- `.github/workflows/`: `test.yml` y `build.yml`.
