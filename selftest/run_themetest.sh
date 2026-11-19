#!/usr/bin/env bash
# Themes, headless: themetest.prg + X16WPTH.BIN + X16THEME1..6.BIN in x16emu on the host file system.
# Checks the PASS lines; one screenshot per theme: build/themetest/snap-1.png .. snap-6.png.
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu), PY (a python3
# with Pillow to split the screenshots; without it only the first one).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
B="${BUILD:-$HERE/build/themetest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
rm -rf "$B"; mkdir -p "$B"
$PROG8C -target cx16 -srcdirs "$HERE/lib/x16link" -srcdirs "$HERE" -out "$B" "$HERE/selftest/themetest.p8" \
  > "$B/themetest.log" 2>&1 || { cat "$B/themetest.log"; exit 1; }
mkdir -p "$B/th"
$PROG8C -target cx16 -srcdirs "$HERE" -out "$B/th" "$HERE/x16wpth.p8" > "$B/th/x16wpth.log" 2>&1 || { cat "$B/th/x16wpth.log"; exit 1; }
cp "$B/th/x16wpth.bin" "$B/X16WPTH.BIN"
python3 "$HERE/tools/mkthemes.py" "$B" > /dev/null
cd "$B"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -fsroot . -gif snap.gif,wait \
  -prg themetest.prg -run > out.txt 2>&1 &
P=$!
for _ in $(seq 400); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE" || tail -20 out.txt
ok=1
grep -aq "ALL PASS" out.txt || ok=0
if [ -f snap.gif ]; then
  # one PNG per frame (sips only converts the first)
  "${PY:-python3}" - <<'PY' 2>/dev/null || sips -s format png snap.gif --out snap-1.png > /dev/null 2>&1
from PIL import Image
im = Image.open("snap.gif")
i = 0
while True:
    i += 1
    im.convert("RGB").save(f"snap-{i}.png")
    try:
        im.seek(im.tell() + 1)
    except EOFError:
        break
PY
  echo "screenshots: $B/snap-*.png"
fi
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
