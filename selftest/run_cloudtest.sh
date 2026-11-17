#!/usr/bin/env bash
# End-to-end test of X16 Write's ownCloud UI: cloudtest.prg + X16WPCL.BIN (built against cloudtest's
# own symbols) + X16Link libraries, in x16emu with -uart1 ximodem, against the hub on 127.0.0.1:6502
# and the real ownCloud. Seeds Documents/LKTEST.RTF + LKTEST.TXT, checks results by byte compare,
# grabs GIF frames (picker, loaded docs, Save As prompt, conflict dialog) and removes the test files.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "${X16OFFICE:-$HERE/../..}" && pwd)"   # the x16-office workspace (hub, toolchain, run/)
B="$ROOT/build/wp-cloudtest"
L="$ROOT/build/wp"
SD="$ROOT/run/sd-wp"
HUBPY="$ROOT/hub/.venv/bin/python"
mkdir -p "$B" "$SD" "$ROOT/run/ximodem-data"
export PROG8C="${PROG8C:-$ROOT/tools/prog8c}"
P8="$PROG8C -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
BUILD="$ROOT/build/wp" "$HERE/build-cloud.sh" > "$B/build-cloud.log" 2>&1 || { cat "$B/build-cloud.log"; exit 1; }
$P8 -out "$B" "$HERE/selftest/cloudtest.p8" > "$B/cloudtest.log" 2>&1 || { cat "$B/cloudtest.log"; exit 1; }
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/wpsyms.p8" cloudtest
$P8 -srcdirs "$B" -out "$B" "$HERE/x16wpcl.p8" > "$B/x16wpcl.log" 2>&1 || { cat "$B/x16wpcl.log"; exit 1; }
cp "$B/x16wpcl.bin" "$SD/X16WPCL.BIN"; cp "$L/x16link.bin" "$SD/X16LINK.BIN"; cp "$L/x16docs.bin" "$SD/X16DOCS.BIN"
cp "$B/cloudtest.prg" "$SD/CLOUDTEST.PRG"; cp "$ROOT/run/sd/X16LINK.KEY" "$SD/X16LINK.KEY"
rm -f "$SD"/WPEXP*.RTF "$SD"/LOCAL.RTF "$SD"/X16WP.TMP "$B/shots.gif"
(cd "$ROOT/hub" && $HUBPY -m x16hub.e2e_files clean >/dev/null && $HUBPY -m x16hub.e2e_files seed "$ROOT/build/wp/run/demo.rtf")
cd "$SD"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$ROOT/tools/x16emu.sh" -sound none -gif "$B/shots.gif,wait" \
  -uart1 "ximodem:$ROOT/run/ximodem-data" -prg CLOUDTEST.PRG -run > "$B/cloudtest.out" 2>&1 &
EMU=$!
for _ in $(seq "${TIMEOUT:-300}"); do grep -q "CLOUDTEST done" "$B/cloudtest.out" 2>/dev/null && break; sleep 1; done
sleep 1; kill $EMU 2>/dev/null; wait $EMU 2>/dev/null
tr '\r' '\n' < "$B/cloudtest.out" | grep -a -E "^(MENU|OPEN|SAVE|EXPORT|LOCAL|CLOUDTEST)"
cd "$ROOT/hub"
fail=0
cmpr() { $HUBPY -m x16hub.e2e_files compare "$@" || fail=1; }
cmp -s "$SD/WPEXP1.RTF" "$ROOT/build/wp/run/demo.rtf" && echo "PASS opened LKTEST.RTF re-exports byte-identical" || { echo "FAIL re-export differs"; fail=1; }
cmpr LKTEST-WP.rtf "$SD/WPEXP3.RTF"
cmpr LKTEST-NEW.rtf "$SD/WPEXP3.RTF"
cmpr LKTEST.TXT "$SD/WPEXP3.RTF" --txt-from-rtf
[ "${KEEP:-0}" = 1 ] || $HUBPY -m x16hub.e2e_files clean
echo "RESULT $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
