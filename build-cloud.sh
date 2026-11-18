#!/usr/bin/env bash
# Build X16 Write with ownCloud support. Works from a fresh clone of this repo:
#   build/x16wp.prg     main program (main RAM)
#   build/x16wpcl.bin   ownCloud UI bank library (needs wpsyms.p8 generated from the main build)
#   build/x16wpsa.bin   Save As folder browser bank library (bank 59, its own wpsyms.p8 in build/sa)
#   build/x16wptb.bin   tables bank library (bank 57, its own wpsyms.p8 in build/tb)
#   build/x16wppi.bin   pictures bank library (bank 54, its own wpsyms.p8 in build/pi)
#   build/x16wppl.bin   picture loading + tool tips bank library (bank 56 at $A200, build/pl)
#   build/x16wphc.bin   256-colour pictures bank library (bank 55 at $AE00, build/hc)
#   build/x16link.bin, build/x16docs.bin   X16Link libraries (sources vendored in lib/x16link)
# and (with an SD dir argument) copies them there as X16WP.PRG, X16WPCL.BIN, X16WPSA.BIN, X16WPTB.BIN,
# X16WPPI.BIN, X16WPPL.BIN, X16WPHC.BIN, X16LINK.BIN, X16DOCS.BIN.
# Env: PROG8C = Prog8 12.3.x compiler command (default: prog8c on PATH; e.g. "java -jar prog8c.jar"),
#      X16LINK_LIB = library sources (default: the vendored lib/x16link), BUILD = output dir.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${X16LINK_LIB:-$HERE/lib/x16link}"
B="${BUILD:-$HERE/build}"
mkdir -p "$B"
P8="${PROG8C:-prog8c} -target cx16 -srcdirs $LIB"
run() { local log="$1"; shift; "$@" > "$log" 2>&1 || { cat "$log"; exit 1; }; grep -E "^Data:|BSS_SLABS" "$log" | sed "s|^|  $(basename "$log" .log): |" || true; }
run "$B/x16link.log" $P8 -out "$B" "$LIB/x16link.p8"
run "$B/x16docs.log" $P8 -out "$B" "$LIB/x16docs.p8"
run "$B/x16wp.log" $P8 -srcdirs "$HERE" -out "$B" "$HERE/x16wp.p8"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/wpsyms.p8"
run "$B/x16wpcl.log" $P8 -srcdirs "$HERE" -srcdirs "$B" -out "$B" "$HERE/x16wpcl.p8"
mkdir -p "$B/sa"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/sa/wpsyms.p8" x16wp 59
run "$B/x16wpsa.log" $P8 -srcdirs "$HERE" -srcdirs "$B/sa" -out "$B" "$HERE/x16wpsa.p8"
mkdir -p "$B/tb"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/tb/wpsyms.p8" x16wp 57
run "$B/x16wptb.log" $P8 -srcdirs "$HERE" -srcdirs "$B/tb" -out "$B" "$HERE/x16wptb.p8"
mkdir -p "$B/pi"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/pi/wpsyms.p8" x16wp 54
run "$B/x16wppi.log" $P8 -srcdirs "$HERE" -srcdirs "$B/pi" -out "$B" "$HERE/x16wppi.p8"
mkdir -p "$B/pl"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/pl/wpsyms.p8" x16wp 56
run "$B/x16wppl.log" $P8 -srcdirs "$HERE" -srcdirs "$B/pl" -out "$B" "$HERE/x16wppl.p8"
mkdir -p "$B/hc"
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/hc/wpsyms.p8" x16wp 55
run "$B/x16wphc.log" $P8 -srcdirs "$HERE" -srcdirs "$B/hc" -out "$B" "$HERE/x16wphc.p8"
if [ $# -ge 1 ]; then
  SD="$1"; mkdir -p "$SD"
  cp "$B/x16wp.prg" "$SD/X16WP.PRG"; cp "$B/x16wpcl.bin" "$SD/X16WPCL.BIN"; cp "$B/x16wpsa.bin" "$SD/X16WPSA.BIN"
  cp "$B/x16wptb.bin" "$SD/X16WPTB.BIN"; cp "$B/x16wppi.bin" "$SD/X16WPPI.BIN"; cp "$B/x16wppl.bin" "$SD/X16WPPL.BIN"
  cp "$B/x16wphc.bin" "$SD/X16WPHC.BIN"
  cp "$B/x16link.bin" "$SD/X16LINK.BIN"; cp "$B/x16docs.bin" "$SD/X16DOCS.BIN"
  echo "copied to $SD"
fi
