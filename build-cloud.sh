#!/usr/bin/env bash
# Build X16 Write with ownCloud support. Works from a fresh clone of this repo:
#   build/x16wp.prg     main program (main RAM)
#   build/x16wpcl.bin   ownCloud UI bank library (needs wpsyms.p8 generated from the main build)
#   build/x16link.bin, build/x16docs.bin   X16Link libraries (sources vendored in lib/x16link)
# and (with an SD dir argument) copies them there as X16WP.PRG, X16WPCL.BIN, X16LINK.BIN, X16DOCS.BIN.
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
if [ $# -ge 1 ]; then
  SD="$1"; mkdir -p "$SD"
  cp "$B/x16wp.prg" "$SD/X16WP.PRG"; cp "$B/x16wpcl.bin" "$SD/X16WPCL.BIN"
  cp "$B/x16link.bin" "$SD/X16LINK.BIN"; cp "$B/x16docs.bin" "$SD/X16DOCS.BIN"
  echo "copied to $SD"
fi
