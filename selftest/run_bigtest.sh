#!/usr/bin/env bash
# Long documents, headless, with 512 KB and with 2 MB of RAM: bigtest.prg + X16WPPI.BIN / X16WPPL.BIN /
# X16WPTB.BIN (built against bigtest's own symbols) in x16emu on the host file system. Checks the PASS lines
# and that save -> load -> save of a full document gives the same RTF. Screenshots: build/bigtest/run-*/snap.png.
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/bigtest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
P8="$PROG8C -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
rm -rf "$B"; mkdir -p "$B/tb" "$B/pi" "$B/pl" "$B/run"
$P8 -out "$B" "$HERE/selftest/bigtest.p8" > "$B/bigtest.log" 2>&1 || { cat "$B/bigtest.log"; exit 1; }
for lib in tb:57:x16wptb pi:54:x16wppi pl:56:x16wppl; do
  IFS=: read -r d bank src <<< "$lib"
  python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/$d/wpsyms.p8" bigtest "$bank" > /dev/null
  $P8 -srcdirs "$B/$d" -out "$B" "$HERE/$src.p8" > "$B/$src.log" 2>&1 || { cat "$B/$src.log"; exit 1; }
  cp "$B/$src.bin" "$B/run/$(echo "$src" | tr a-z A-Z).BIN"
done
cp "$B/bigtest.prg" "$B/run/"
python3 "$HERE/selftest/mkbmx.py" "$B/run"
ok=1
for RAM in 512 2048; do
  R="$B/run-$RAM"; rm -rf "$R"; cp -R "$B/run" "$R"; cd "$R"
  echo "== $RAM KB"
  SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -warp -ram $RAM -fsroot . \
    -gif snap.gif,wait -prg bigtest.prg -run > out.txt 2>&1 &
  P=$!
  for _ in $(seq 3000); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
  sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
  tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE|banks|fit" || tail -20 out.txt
  grep -aq "ALL PASS" out.txt || ok=0
  if cmp -s BIG1.RTF BIG2.RTF; then echo "PASS save -> load -> save gives the same RTF ($(wc -c < BIG1.RTF) bytes)"; else echo "FAIL BIG1.RTF != BIG2.RTF"; ok=0; fi
  [ -f snap.gif ] && sips -s format png snap.gif --out snap.png > /dev/null 2>&1 && echo "screenshot: $R/snap.png"
done
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
