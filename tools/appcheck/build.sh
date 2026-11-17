#!/bin/sh
# Se ejecuta dentro del contenedor `appcheck` (lo lanza tools/check-app.ps1).
# Lo único que se cambia en las copias: Linux no tiene Objective-C (@objc,
# #selector) ni punto de entrada de app (@main).
cd /w/chk || exit 2
sed -i "/testTarget/d" /w/MetroCore/Package.swift
sed -i "s/@objc //; s/#selector(handlePan(_:))/nil/; s/#selector(handleRotation(_:))/nil/" AppSrc/Rendering/ARExperience.swift
sed -i "s/^@main\$//" AppSrc/MetroRayosXApp.swift
echo "fuentes de la app: $(find AppSrc -name '*.swift' | wc -l), líneas: $(cat $(find AppSrc -name '*.swift') | wc -l)"
swift build --target AppCheck > /tmp/appcheck.log 2>&1
code=$?
grep -E "error|warning" /tmp/appcheck.log | sed "s|/w/chk/AppSrc/|App/|" | sort -u | head -n 60
if [ "$code" -eq 0 ]; then echo "COMPILA (contra los frameworks de pega)"; else echo "NO COMPILA"; fi
exit $code