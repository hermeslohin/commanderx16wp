# X16 Write - a mouse-driven word processor for the Commander X16 (Prog8)

Build: `make PROG8C="<prog8c 12.3.x command>"` (needs Prog8 12.3.x + 64tass + Java 11+). Everything
lands in `build/`: **x16wp.prg**, **x16wpcl.bin** (ownCloud UI, RAM bank 62), **x16link.bin** and
**x16docs.bin** (X16Link libraries, banks 60/61, sources vendored in `lib/x16link/`, see
`lib/x16link/VENDORED.md`). `make sd SD=<dir>` also copies them as X16WP.PRG, X16WPCL.BIN,
X16LINK.BIN, X16DOCS.BIN. Run: `make run` (needs a mouse, 512 KB RAM). Without the .BIN files on the
SD card the program still works as a plain SD-card word processor. (`x16wp.prg`/`.asm` in the repo
root are the original pre-cloud build, kept for reference.)

## Screen
Row 0 title/quit - rows 1-2 icon toolbars - row 3 text colour + highlight swatches - row 4 ruler -
scrolling page view with page border, per-page title bars and a scroll bar - status bar (tool tips on hover).

Icons: New, Open, Save, Save As, Cut, Copy, Paste, Select All, Page Break | Bold, Italic, Underline,
Left/Center/Right, Bullets, Numbers, Outdent, Indent, Font menu | 16 text colours | 16 highlight colours.
Click = place cursor, drag = select, double click = select word, scroll bar / wheel = scroll.
Keyboard: typing, Enter, Backspace, Delete, arrows, Home, End, PgUp, PgDn, Tab (4 spaces).

## Pages and printing
A page is 64 columns x 54 lines. RTF export writes every screen line as its own exact-spacing
paragraph (12 pt monospace, 10 cpi, 6 lpi, 1" margins) with an explicit page break at every
page start, so the printed page matches the screen. Bold/italic/underline, 3 monospace font
families (Courier New / Lucida Console / Andale Mono), 16 text + highlight colours, alignment,
indent (4 columns per level) and bullet/number lists are all written as real RTF.
The RTF can be re-opened by this program (private `\*\xwp` paragraph tags keep soft wrapping).

## ownCloud: Open and Save As

Open and Save As each ask first: **1** = SD card (as before), **2** = ownCloud.

* **Open from ownCloud** shows the hub account's `Documents/` folder (subfolders included,
  sorted by name) with size, date and type. Use the arrow keys/PgUp/PgDn/mouse wheel to move,
  then Enter or double-click to open, or Esc to cancel. **RTF** files open as they are.
  **TXT** files are converted to RTF by the hub (UTF-8 → ISO-8859-15, characters with no
  equivalent become `?`, smart quotes/dashes become ASCII). **DOCX** (Word) files are converted to
  RTF by the hub too (bold/italic/underline, fonts, colours, alignment, indents, lists, page breaks;
  images and tables are approximated). Other types (spreadsheets are for X16 Sheets), and files
  over 1 MiB, are greyed out. The download goes to a temp file on the SD card and is checked with CRC-32
  before it replaces the document. A dropped link resumes where it stopped.
* **Save** of a document opened from ownCloud writes it back there, but only if nobody
  changed it in ownCloud meanwhile (the hub checks the etag).
* **Save As to ownCloud** asks for a name in `Documents/` (`.rtf` keeps the full format,
  `.txt` stores plain text as UTF-8, **`.docx` stores a Word document**: the hub converts the RTF,
  joining the screen lines back into paragraphs and turning the list markers into real Word lists).
  Save of a document opened from a `.docx` writes a `.docx` again. If the file already exists, or was changed since you
  opened it, a **Save conflict** dialog offers **Overwrite** (replaces exactly the version
  the hub just showed you), **New name** (asks again) or **Cancel**. Nothing is ever
  overwritten silently.
* The status bar shows progress (`Transferring nn%`) and the result (`Saved to ownCloud`,
  `Hub unreachable`, ...).

### Setup (once)

1. The sync hub (X16 Office hub, `python -m x16hub serve`) runs on a machine on your LAN and
   is set up for your ownCloud (`config set bind <LAN ip>`).
2. Create this X16's key and copy `X16LINK.KEY` to the SD card next to `X16WP.PRG`:
   `python -m x16hub link key new <devid> --sdcard <dir> --host <hub-ip>:6502`.
3. The TexElec serial card's ESP32 (Zimodem) is on the Wi-Fi at 115200 baud with RTS/CTS
   (hub README, "ESP32 / Zimodem setup").

Test (needs the X16 Office workspace with the hub and toolchain; `X16OFFICE=<dir>`):
`selftest/run_cloudtest.sh` drives the real cloud UI in the emulator
(`-uart1 ximodem`) against the hub and the real ownCloud. It seeds `Documents/LKTEST.*`,
opens RTF + TXT, saves, runs Save As with both conflict choices, byte-compares the results
in ownCloud, removes the test files and leaves screenshots in `$X16OFFICE/build/wp-cloudtest/shots.gif`.

## Notes / limits
* 16 pages max (864 lines), clipboard 2700 characters, file names are typed in a dialog.
* Opening RTF from other programs is best effort (colours map by index, one font family each).
* `selftest/selftest.p8` is a scripted headless test (builds a document, exports, re-imports).
