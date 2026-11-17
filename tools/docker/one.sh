#!/bin/sh
# Ejecuta un test en su propio proceso, con reintentos si XCTest se queda colgado.
t="$1"
log="/tmp/r/$(echo "$t" | tr '/.' '__').log"
for attempt in 1 2 3 4; do
  timeout 40 /pkg/.build/debug/MetroCorePackageTests.xctest "$t" > "$log" 2>&1
  code=$?
  [ "$code" -ne 124 ] && break
done
if [ "$code" -eq 0 ]; then echo "ok $t"; else echo "FAIL($code) $t"; grep -E 'error:' "$log" | cut -c1-400; fi