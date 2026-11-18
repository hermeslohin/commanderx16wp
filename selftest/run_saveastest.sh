#!/usr/bin/env bash
# Save As folder browser, end to end (macOS): saveas.prg + X16WPCL.BIN + X16WPSA.BIN (built against
# saveas' own symbols) + X16Link libraries on a FAT32 SD card image (real CMDR-DOS), x16emu -uart1
# ximodem, the hub link server with an in-memory ownCloud (selftest/fakehub.py). Needs
# ../x16-office-hub (HUB=...) with its venv (HUBPY=...), Prog8 12.3 (PROG8C=...), hdiutil + diskutil.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HUB="${HUB:-$HERE/../x16-office-hub/hub}"
HUBPY="${HUBPY:-$HUB/.venv/bin/python}"
B="${BUILD:-$HERE/build/saveastest}"
EMU="${EMU:-/usr/local/x16emu/x16emu}"
export PROG8C="${PROG8C:-java -jar $HOME/prog8c.jar}"
P8="$PROG8C -target cx16 -srcdirs $HERE/lib/x16link -srcdirs $HERE"
rm -rf "$B"; mkdir -p "$B/out" "$B/key" "$B/mnt" "$B/ximodem" "$B/sa"
$P8 -out "$B" "$HERE/selftest/saveas.p8" > "$B/saveas.log" 2>&1 || { cat "$B/saveas.log"; exit 1; }
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/wpsyms.p8" saveas > /dev/null
python3 "$HERE/tools/gen_wpsyms.py" "$B" "$B/sa/wpsyms.p8" saveas 59 > /dev/null
$P8 -srcdirs "$B" -out "$B" "$HERE/x16wpcl.p8" > "$B/x16wpcl.log" 2>&1 || { cat "$B/x16wpcl.log"; exit 1; }
$P8 -srcdirs "$B/sa" -out "$B" "$HERE/x16wpsa.p8" > "$B/x16wpsa.log" 2>&1 || { cat "$B/x16wpsa.log"; exit 1; }
$P8 -out "$B" "$HERE/lib/x16link/x16link.p8" > /dev/null 2>&1
$P8 -out "$B" "$HERE/lib/x16link/x16docs.p8" > /dev/null 2>&1

"$HUBPY" "$HERE/selftest/fakehub.py" "$HUB" "$B/key" "$B/out" 6502 > "$B/hub.log" 2>&1 &
HUBPID=$!
for _ in $(seq 50); do grep -q "hub up" "$B/hub.log" 2>/dev/null && break; sleep 0.2; done

IMG="$B/sd.img"
dd if=/dev/zero of="$IMG" bs=1m count=40 2> /dev/null
DEV=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$IMG" | head -1 | awk '{print $1}')
diskutil partitionDisk "$DEV" MBR "MS-DOS FAT32" X16WPTEST 100% > /dev/null
hdiutil detach "$DEV" > /dev/null
mount_img() { hdiutil attach -imagekey diskimage-class=CRawDiskImage -mountpoint "$B/mnt" "$IMG" > /dev/null; }
mount_img
for f in x16wpcl x16wpsa x16link x16docs; do cp "$B/$f.bin" "$B/mnt/$(echo $f | tr a-z A-Z).BIN"; done
cp "$B/key/X16LINK.KEY" "$B/mnt/"
rm -rf "$B/mnt/.fseventsd" "$B/mnt/.Spotlight-V100" "$B/mnt/.Trashes" "$B/mnt"/._* 2> /dev/null || true
hdiutil detach "$B/mnt" > /dev/null

cd "$B"
# SHOT=1: real speed (warp skips frames) and GIF frames of the dialogs in shots.gif
EXTRA="-warp"; [ -n "${SHOT:-}" ] && EXTRA="-gif $B/shots.gif,wait"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$EMU" -sound none $EXTRA -sdcard "$IMG" \
  -uart1 "ximodem:$B/ximodem" -prg saveas.prg -run > saveas.out 2>&1 &
EMUPID=$!
for _ in $(seq 2000); do grep -aq "SAVEAS done" saveas.out 2>/dev/null && break; kill -0 $EMUPID 2>/dev/null || break; sleep 0.2; done
sleep 0.5; kill $EMUPID 2>/dev/null; wait $EMUPID 2>/dev/null || true
touch "$B/out/STOP"; wait $HUBPID || cat "$B/hub.log"
tr '\r' '\n' < saveas.out | grep -a -E "^(SD_|OC_|LOAD|SAVEAS)"
mount_img
set +e
python3 - "$B/out/Documents" "$B/mnt" "$B/saveas.out" <<'PY'
import sys
from pathlib import Path
oc, sd, log = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]).read_bytes().decode("latin-1").replace("\r", "\n")
bad = 0
def chk(c, what):
    global bad
    print(("PASS " if c else "FAIL ") + what); bad += 0 if c else 1
def line(tag):
    return next((l for l in log.splitlines() if l.startswith(tag)), "")
mom = sd / "LETTERS" / "mom.rtf"
chk(mom.is_file() and mom.read_bytes().startswith(b"{\\rtf1"), "SD: new folder LETTERS made, mom.rtf saved in it")
chk(b"AB" in mom.read_bytes() if mom.is_file() else False, "SD: Replace overwrote mom.rtf with the newer text")
chk("status=[Saved as RTF" in line("SD_NEWFOLDER_SAVE") and "file=[mom.rtf]" in line("SD_NEWFOLDER_SAVE"), "SD: status and file name")
chk("cwd=[/LETTERS]" in line("SD_NEWFOLDER_SAVE") and "cwd=[/LETTERS]" in line("SD_CANCEL"), "SD: the document's folder is the current directory; Cancel goes back")
q3 = oc / "Reports" / "q3.rtf"
chk(q3.is_file() and q3.read_bytes().startswith(b"{\\rtf1"), "ownCloud: new folder Reports made, q3.rtf saved in it (key read from / while in /LETTERS)")
chk(b"ABCD" in q3.read_bytes() if q3.is_file() else False, "ownCloud: Save As in place overwrote its own version")
chk("Saved to ownCloud" in line("OC_SAVEAS_SAME") and "file=[q3.rtf]" in line("OC_SAVEAS_SAME"), "ownCloud: status and file name")
chk("BMX 180x240 bpp 8" in line("OC_PICTURE"), "ownCloud picture picker: the hub turned aaa.jpg (640 x 480, EXIF rotated) into an upright 180 x 240 BMX")
chk(not (sd / "LETTERS" / "X16WP.TMP").exists() and not (sd / "X16WP.TMP").exists(), "no temp file left")
print("RESULT " + ("PASS" if bad == 0 else f"{bad} FAILED"))
sys.exit(1 if bad else 0)
PY
R=$?
hdiutil detach "$B/mnt" > /dev/null
exit $R
