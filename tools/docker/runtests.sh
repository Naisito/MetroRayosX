#!/bin/sh
# Compila MetroCore y pasa cada test por separado (ver CLAUDE.md).
cd /pkg || exit 2
swift build --build-tests > /tmp/build.log 2>&1
if [ $? -ne 0 ]; then grep -E 'error' /tmp/build.log | sort -u | cut -c1-400 | head -n 40; echo "BUILD FAILED"; exit 1; fi
rm -rf /tmp/r && mkdir -p /tmp/r
swift test list --skip-build 2>/dev/null | grep -E '^MetroCoreTests\.' > /tmp/tests.txt
xargs -P 4 -n 1 /usr/local/bin/one.sh < /tmp/tests.txt > /tmp/results.txt
grep -v '^ok ' /tmp/results.txt
echo "tests: $(wc -l < /tmp/tests.txt)  ok: $(grep -c '^ok ' /tmp/results.txt)  fallidos: $(grep -c '^FAIL' /tmp/results.txt)"
[ "$(grep -c '^FAIL' /tmp/results.txt)" -eq 0 ]
