#!/usr/bin/env bash
# Refresh the vendored X16Link sources from the X16 Office workspace (default ~/x16-office).
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${X16OFFICE:-$HOME/x16-office}/lib/x16link"
cp "$SRC"/*.p8 "$SRC"/README.md "$HERE/lib/x16link/"
echo "vendored $(ls "$SRC"/*.p8 | wc -l) files from $SRC"
