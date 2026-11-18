#!/usr/bin/env bash
# Tables, headless: tabletest.prg + X16WPTB.BIN (built against tabletest's own symbols) in x16emu on the
# host file system. Checks the PASS lines, that save -> load -> save gives the same RTF, and that the RTF
# is a real table (\trowd .. \cell .. \row). Screenshot: build/tabletest/snap.png (macOS sips).
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/tabletest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
P8="$PROG8C -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
rm -rf "$B"; mkdir -p "$B/tb" "$B/run"
$P8 -out "$B" "$HERE/selftest/tabletest.p8" > "$B/tabletest.log" 2>&1 || { cat "$B/tabletest.log"; exit 1; }
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/tb/wpsyms.p8" tabletest 57 > /dev/null
$P8 -srcdirs "$B/tb" -out "$B" "$HERE/x16wptb.p8" > "$B/x16wptb.log" 2>&1 || { cat "$B/x16wptb.log"; exit 1; }
cp "$B/tabletest.prg" "$B/run/"
cp "$B/x16wptb.bin" "$B/run/X16WPTB.BIN"
cd "$B/run"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -fsroot . -gif snap.gif,wait \
  -prg tabletest.prg -run > out.txt 2>&1 &
P=$!
for _ in $(seq 300); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if cmp -s TBL.RTF TBL2.RTF; then echo "PASS save -> load -> save gives the same RTF"; else echo "FAIL TBL.RTF != TBL2.RTF"; ok=0; fi
rows=$(grep -o '\\row' TBL.RTF | wc -l | tr -d ' '); trowd=$(grep -o '\\trowd' TBL.RTF | wc -l | tr -d ' ')
cells=$(grep -o '\\cell[^x]' TBL.RTF | wc -l | tr -d ' ')
if [ "$rows" = 4 ] && [ "$trowd" = 4 ] && [ "$cells" = 16 ]; then echo "PASS RTF has 4 table rows of 4 cells"
else echo "FAIL RTF rows=$rows trowd=$trowd cells=$cells"; ok=0; fi
[ -f snap.gif ] && sips -s format png snap.gif --out snap.png > /dev/null 2>&1 && echo "screenshot: $B/run/snap.png"
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
