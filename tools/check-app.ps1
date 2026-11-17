# Comprueba en Linux que los fuentes de la app (App/**/*.swift) compilan.
#
# No hay Mac, así que no se puede compilar la app de verdad. Este script la
# compila contra módulos de pega con los nombres de los frameworks de Apple
# (tools/appcheck/Stubs) más el MetroCore real, en un contenedor swift:6.0 y
# en modo Swift 5. Caza errores de lenguaje, de llamadas a MetroCore, de
# acceso, de aislamiento de actores y de tipos.
#
# NO garantiza que la app compile en Xcode: las firmas de Apple de los módulos
# de pega están escritas a mano a partir de la documentación. Si usas una API
# de Apple nueva, añádela a Stubs con su firma real.
#
# Uso:  powershell -ExecutionPolicy Bypass -File tools\check-app.ps1

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$here = Join-Path $PSScriptRoot "appcheck"
$name = "appcheck"

$daemon = docker info --format "{{.ServerVersion}}" 2>$null
if (-not $daemon) { Write-Host "Docker no está arrancado. Abre Docker Desktop y vuelve a intentarlo."; exit 2 }

$running = docker ps -q --filter "name=^$name$"
if (-not $running) {
    if (docker ps -aq --filter "name=^$name$") { docker rm -f $name | Out-Null }
    docker run -d --name $name -w /w/chk swift:6.0 sleep infinity | Out-Null
}

docker exec $name sh -c "rm -rf /w/chk/Stubs /w/chk/AppSrc /w/chk/Package.swift /w/chk/build.sh /w/MetroCore && mkdir -p /w/chk/AppSrc /w/MetroCore"
docker cp "$here\Package.swift" "${name}:/w/chk/Package.swift" | Out-Null
docker cp "$here\Stubs" "${name}:/w/chk/Stubs" | Out-Null
docker cp "$here\build.sh" "${name}:/w/chk/build.sh" | Out-Null
docker cp "$repo\MetroCore\Package.swift" "${name}:/w/MetroCore/Package.swift" | Out-Null
docker cp "$repo\MetroCore\Sources" "${name}:/w/MetroCore/Sources" | Out-Null
docker cp "$repo\App\Services" "${name}:/w/chk/AppSrc/Services" | Out-Null
docker cp "$repo\App\Rendering" "${name}:/w/chk/AppSrc/Rendering" | Out-Null
docker cp "$repo\App\Views" "${name}:/w/chk/AppSrc/Views" | Out-Null
docker cp "$repo\App\MetroRayosXApp.swift" "${name}:/w/chk/AppSrc/MetroRayosXApp.swift" | Out-Null
docker exec $name sh /w/chk/build.sh
exit $LASTEXITCODE