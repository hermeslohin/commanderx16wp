#!/usr/bin/env bash
# Long documents, headless, with 512 KB and with 2 MB of RAM: bigtest.prg + X16WPPI.BIN / X16WPPL.BIN /
# X16WPTB.BIN (built against bigtest's own symbols) + X16WPVM.BIN in x16emu on the host file system, and
# with 512 KB on a FAT32 SD card image (real CMDR-DOS: swap files in //X16WPSWP/; macOS, hdiutil).
# Checks the PASS lines, that save -> load -> save of a full document gives the same RTF and (SD card) that
# no swap files are left. Screenshots: build/bigtest/run-*/snap.png.
# Env: PROG8C (default java -jar ~/prog8c.jar), EMU (default /usr/local/x16emu/x16emu), RAMS (host file
# system runs, default "512 2048"), NOSD=1 skips the SD card image run.
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
$P8 -out "$B" "$HERE/x16wpvm.p8" > "$B/x16wpvm.log" 2>&1 || { cat "$B/x16wpvm.log"; exit 1; }
cp "$B/x16wpvm.bin" "$B/run/X16WPVM.BIN"
cp "$B/bigtest.prg" "$B/run/"
python3 "$HERE/selftest/mkbmx.py" "$B/run"
ok=1
for RAM in ${RAMS:-512 2048}; do
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
  # the host file system can't delete files by pattern in a folder: leftovers are only reported here
  # (they are never read again; the SD card run below checks that CMDR-DOS deletes them)
  echo "note: swap files left on the host file system: $(ls X16WPSWP 2> /dev/null | wc -l | tr -d ' ')"
  [ -f snap.gif ] && sips -s format png snap.gif --out snap.png > /dev/null 2>&1 && echo "screenshot: $R/snap.png"
done

# the same with 512 KB on a FAT32 SD card image: absolute swap file paths, a change of folder mid-test
if [ "${NOSD:-}" = "" ] && command -v hdiutil > /dev/null; then
  R="$B/run-sd"; rm -rf "$R"; mkdir -p "$R/mnt"; cd "$R"
  echo "== 512 KB, SD card image"
  dd if=/dev/zero of=sd.img bs=1m count=64 2> /dev/null
  DEV=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage sd.img | head -1 | awk '{print $1}')
  diskutil partitionDisk "$DEV" MBR "MS-DOS FAT32" X16WPBIG 100% > /dev/null
  hdiutil detach "$DEV" > /dev/null
  hdiutil attach -imagekey diskimage-class=CRawDiskImage -mountpoint "$R/mnt" sd.img > /dev/null
  cp "$B"/run/* "$R/mnt/"; echo sd > "$R/mnt/SDTEST"
  rm -rf "$R/mnt/.fseventsd" "$R/mnt/.Spotlight-V100" "$R/mnt/.Trashes" "$R/mnt"/._* 2> /dev/null || true
  hdiutil detach "$R/mnt" > /dev/null
  SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none -echo iso -warp -ram 512 -sdcard sd.img \
    -prg "$B/run/bigtest.prg" -run > out.txt 2>&1 &
  P=$!
  for _ in $(seq 6000); do grep -aq "DONE" out.txt 2>/dev/null && break; sleep 0.2; done
  sleep 0.5; kill $P 2>/dev/null; wait $P 2>/dev/null || true
  tr '\r' '\n' < out.txt | tr -d '\000' | grep -a -E "PASS|FAIL|DONE|banks|fit" || tail -20 out.txt
  grep -aq "ALL PASS" out.txt || ok=0
  hdiutil attach -imagekey diskimage-class=CRawDiskImage -mountpoint "$R/mnt" sd.img > /dev/null
  if cmp -s mnt/BIG1.RTF mnt/BIG2.RTF; then echo "PASS save -> load -> save gives the same RTF ($(wc -c < mnt/BIG1.RTF) bytes)"; else echo "FAIL BIG1.RTF != BIG2.RTF"; ok=0; fi
  if [ -d mnt/X16WPSWP ] && [ -z "$(ls mnt/X16WPSWP)" ]; then echo "PASS swap folder //X16WPSWP/ used and left empty"; else echo "FAIL swap folder: $(ls -d mnt/X16WPSWP 2>&1) $(ls mnt/X16WPSWP 2>/dev/null | wc -l) files"; ok=0; fi
  hdiutil detach "$R/mnt" > /dev/null
fi
[ $ok = 1 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; exit 1; }
