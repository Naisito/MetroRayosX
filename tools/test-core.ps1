# Compila MetroCore y pasa sus tests en un contenedor Linux de Swift.
#
# En este PC no hay Mac ni Swift: es la única forma de probar el núcleo sin
# esperar a GitHub Actions. Necesita Docker Desktop arrancado.
#
# Uso (desde PowerShell):  powershell -ExecutionPolicy Bypass -File tools\test-core.ps1
#
# No se monta ninguna carpeta de Windows (Docker pediría permiso y se queda
# esperando): los fuentes se copian al contenedor con `docker cp`.
# Cada test corre en su propio proceso porque el XCTest de Linux se queda a
# veces colgado al cerrar un test cuando se ejecutan todos seguidos.

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$name = "swiftbox"

$daemon = docker info --format "{{.ServerVersion}}" 2>$null
if (-not $daemon) { Write-Host "Docker no está arrancado. Abre Docker Desktop y vuelve a intentarlo."; exit 2 }

$running = docker ps -q --filter "name=^$name$"
if (-not $running) {
    if (docker ps -aq --filter "name=^$name$") { docker rm -f $name | Out-Null }
    docker run -d --name $name -w /pkg swift:6.0 sleep infinity | Out-Null
}

docker exec $name sh -c "rm -rf /pkg/Sources /pkg/Tests /pkg/Package.swift /App && mkdir -p /App"
docker cp "$repo\MetroCore\Package.swift" "${name}:/pkg/Package.swift" | Out-Null
docker cp "$repo\MetroCore\Sources" "${name}:/pkg/Sources" | Out-Null
docker cp "$repo\MetroCore\Tests" "${name}:/pkg/Tests" | Out-Null
# Los tests con datos reales leen App/Resources por ruta relativa.
docker cp "$repo\App\Resources" "${name}:/App/Resources" | Out-Null
docker cp "$repo\tools\docker\one.sh" "${name}:/usr/local/bin/one.sh" | Out-Null
docker cp "$repo\tools\docker\runtests.sh" "${name}:/usr/local/bin/runtests.sh" | Out-Null
docker exec $name sh -c "chmod +x /usr/local/bin/one.sh /usr/local/bin/runtests.sh && /usr/local/bin/runtests.sh"
exit $LASTEXITCODE