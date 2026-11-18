#!/usr/bin/env bash
# Pictures, headless: pictest.prg + X16WPPI.BIN / X16WPPL.BIN / X16WPTB.BIN (built against pictest's own
# symbols) in x16emu on the host file system, with test BMX files from selftest/mkbmx.py. Checks the PASS
# lines, that save -> load -> save gives the same RTF, and that the RTF carries the BMX files byte for byte.
# Screenshot: build/pictest/run/snap.png (macOS sips).
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/pictest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
P8="$PROG8C -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
rm -rf "$B"; mkdir -p "$B/tb" "$B/pi" "$B/pl" "$B/run"
$P8 -out "$B" "$HERE/selftest/pictest.p8" > "$B/pictest.log" 2>&1 || { cat "$B/pictest.log"; exit 1; }
for lib in tb:57:x16wptb pi:54:x16wppi pl:56:x16wppl; do
  IFS=: read -r d bank src <<< "$lib"
  python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/$d/wpsyms.p8" pictest "$bank" > /dev/null
  $P8 -srcdirs "$B/$d" -out "$B" "$HERE/$src.p8" > "$B/$src.log" 2>&1 || { cat "$B/$src.log"; exit 1; }
  cp "$B/$src.bin" "$B/run/$(echo "$src" | tr a-z A-Z).BIN"
done
cp "$B/pictest.prg" "$B/run/"
python3 "$HERE/selftest/mkbmx.py" "$B/run"
cd "$B/run"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -warp -fsroot . -gif snap.gif,wait \
  -prg pictest.prg -run > out.txt 2>&1 &
P=$!
for _ in $(seq 900); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if cmp -s PIC1.RTF PIC2.RTF; then echo "PASS save -> load -> save gives the same RTF"; else echo "FAIL PIC1.RTF != PIC2.RTF"; ok=0; fi
python3 - <<'EOF' || ok=0
import re, sys
rtf = open("PIC1.RTF", "rb").read()
groups = [bytes.fromhex(re.sub(rb"\s", b"", g).decode()) for g in re.findall(rb"\{\\\*\\xwpbmx ([0-9a-f\s]*)\}", rtf)]
want = [open("PIC8.BMX", "rb").read(), open("PIC4.BMX", "rb").read()]
if groups == want:
    print("PASS the RTF carries PIC8.BMX and PIC4.BMX byte for byte")
else:
    print("FAIL pictures in the RTF:", [len(g) for g in groups], "want", [len(w) for w in want]); sys.exit(1)
EOF
[ -f snap.gif ] && sips -s format png snap.gif --out snap.png > /dev/null 2>&1 && echo "screenshot: $B/run/snap.png"
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
