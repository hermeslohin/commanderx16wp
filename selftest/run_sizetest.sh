#!/usr/bin/env bash
# Font sizes, headless: sizetest.prg in x16emu on the host file system. Checks the PASS lines, that
# save -> load -> save gives the same RTF and the \fs / \sl values in it. Screenshot: build/sizetest/snap.png.
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/sizetest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
rm -rf "$B"; mkdir -p "$B"
$PROG8C -target cx16 -srcdirs "$HERE/lib/x16link" -srcdirs "$HERE" -out "$B" "$HERE/selftest/sizetest.p8" \
  > "$B/sizetest.log" 2>&1 || { cat "$B/sizetest.log"; exit 1; }
cd "$B"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -fsroot . -gif snap.gif,wait \
  -prg sizetest.prg -run > out.txt 2>&1 &
P=$!
for _ in $(seq 300); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if cmp -s SIZES.RTF SIZES2.RTF; then echo "PASS save -> load -> save gives the same RTF"; else echo "FAIL SIZES.RTF != SIZES2.RTF"; ok=0; fi
for w in '\fs72' '\fs48' '\fs36' '\fs24' '\sl-720' '\sl-480' '\sl-240'; do
  grep -qF "$w" SIZES.RTF || { echo "FAIL no $w in the RTF"; ok=0; }
done
[ $ok = 1 ] && echo "PASS RTF has \\fs24/36/48/72 and 1-, 2-, 3-row line spacing"
[ -f snap.gif ] && sips -s format png snap.gif --out snap.png > /dev/null 2>&1 && echo "screenshot: $B/snap.png"
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
