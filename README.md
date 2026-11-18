# X16 Write - a mouse-driven word processor for the Commander X16 (Prog8)

Build: `make PROG8C="<prog8c 12.3.x command>"` (needs Prog8 12.3.x + 64tass + Java 11+). Everything
lands in `build/`: **x16wp.prg**, **x16wpcl.bin** (ownCloud UI, RAM bank 62), **x16wpsa.bin** (Save As
folder browser, RAM bank 59, loaded by x16wpcl.bin), **x16wptb.bin** (tables, RAM bank 57; the line-order
table is in bank 58, the RTF file buffer in bank 56, the renderer's buffers in bank 55), **x16wppi.bin** and
**x16wppl.bin** (pictures, RAM bank 54 and bank 56 from $A200, and the tool tips; picture data in banks
28-53), **x16link.bin** and
**x16docs.bin** (X16Link libraries, banks 60/61, sources vendored in `lib/x16link/`, see
`lib/x16link/VENDORED.md`). `make sd SD=<dir>` also copies them as X16WP.PRG, X16WPCL.BIN,
X16WPSA.BIN, X16WPTB.BIN, X16WPPI.BIN, X16WPPL.BIN, X16LINK.BIN, X16DOCS.BIN. Run: `make run` (needs a mouse, 512 KB RAM). Without the .BIN files on the
SD card the program still works as a plain SD-card word processor. (`x16wp.prg`/`.asm` in the repo
root are the original pre-cloud build, kept for reference.)

## Screen
Row 0 title/quit - rows 1-2 icon toolbars - row 3 text colour + highlight swatches - row 4 ruler -
scrolling page view with page border, per-page title bars and a scroll bar - status bar (tool tips on hover).
Colours: the "Sunset Arcade" theme shared by the X16 Office apps (`theme.p8`): striped title bar, cream
page on a starry desk, yellow ruler tape, and Quill the pencil mascot in the status bar, who hops after a
successful open or save. Saved documents keep the original colours (RTF export uses `theme.doc_lo/doc_hi`).

Icons: New, Open, Save, Save As, Cut, Copy, Paste, Select All, Page Break | Bold, Italic, Underline,
Left/Center/Right, Bullets, Numbers, Outdent, Indent, Font menu | 16 text colours | 16 highlight colours.
Click = place cursor, drag = select, double click = select word, scroll bar / wheel = scroll.
Keyboard: typing, Enter, Backspace, Delete, arrows, Home, End, PgUp, PgDn, Tab (4 spaces).

## Pages and printing
A page is 64 columns x 54 lines. RTF export writes every screen line as its own exact-spacing
paragraph (12 pt monospace, 10 cpi, 6 lpi, 1" margins) with an explicit page break at every
page start, so the printed page matches the screen. Bold/italic/underline, 4 font sizes (12, 18, 24
and 36 pt, see below), 3 monospace font
families (Courier New / Lucida Console / Andale Mono), 16 text + highlight colours, alignment,
indent (4 columns per level) and bullet/number lists are all written as real RTF.
## Font sizes
The Font menu (click the font box in the toolbar) lists the fonts and four sizes: **12 pt** (normal),
**18 pt**, **24 pt** (large) and **36 pt** (headline). With text selected the size applies to the
selection, otherwise to what you type next; the toolbar shows the current size next to the font name.
Characters stay on the 8x8 cell grid: 12 pt is 1 cell, 24 pt 2x2 cells, 36 pt 3x3 cells, and 18 pt
takes 2x2 cells with the glyph drawn 1.5 times as big (12x12 pixels, on the baseline). A line is as
high as its biggest character (1, 2 or 3 rows; smaller text on the line stands on the bottom row) and
wraps at the right margin by cell width (36 pt: 21 characters a line). In the RTF the sizes are
`\fs24`, `\fs36`, `\fs48`, `\fs72` and the paragraph gets exact line spacing of 12, 24 or 36 pt;
printed, 18 pt text is a little narrower than its 2 cells on screen (the line breaks stay the same).
On import every size becomes the nearest of the four. A paragraph can hold up to 640 characters (longer
ones from imported files are split into several paragraphs).

Memory: the size code is style bits 6-7 of a character (`$40` 24 pt as before, `$80` 18 pt, `$C0`
36 pt); `vid.big_glyph` draws each cell of a big character from small row/column maps, and
`render_run`'s glyph and colour buffers live in RAM bank 55 (it maps the bank and puts the caller's
back). `selftest/run_sizetest.sh` tests the sizes headless (heights, widths, wrapping, pages, mouse
columns, RTF save -> load -> save).

The RTF can be re-opened by this program (private `\*\xwp` paragraph tags keep soft wrapping).

## Tables

The **Table** button (toolbar 1, after Page Break) inserts a table: type `columns x rows`, up to
**8 x 20** (e.g. `4x3`). It goes on the current line if that is empty, otherwise after the paragraph,
and a normal line always follows it. Columns are equal: 63 / columns screen cells each (8 columns =
6 characters per cell, 1 column = 62). The first row has a lavender band; rows are separated by lines.

* Type in a cell; **Tab** goes to the next cell, after the last cell of the last row it adds a row
  (up to 20). **Enter** goes to the same cell one row down, and from the last row out of the table.
  Backspace / Delete work inside the cell; a full cell takes no more characters ("This cell is
  full"). Bold, italic, underline, fonts and colours work on cell text; the bigger sizes do not.
* Click the **Table** button while the cursor is in a table: **Add row** (below the current one),
  **Delete row**, **Delete table**, Cancel.
* A selection that reaches into a table deletes whole rows it covers completely and clears the
  selected characters of the rows it covers partly; text is never merged into a table row. Paste
  into a cell inserts what fits (up to the first line break). Copy turns the cell borders into spaces.
* RTF: each row is `\trowd`..`\cellx`..`\intbl`..`\cell`..`\row` (the first row `\trhdr`), so Word,
  LibreOffice and ownCloud show a real table; tables in other programs' RTF are read back the same
  way (cells cut to the column width). As `.docx` on ownCloud the hub makes a Word table of it.
* The code is the bank library **X16WPTB.BIN** (RAM bank 57, `x16wptb.p8`; `tblx.p8` is its main-RAM
  side). Without it on the SD card the Table button says so and tables in RTF files open as text.

## Pictures

The **Picture** button (toolbar 1, after Table) inserts a **BMX** picture (the Commander X16 bitmap
format: version 1, uncompressed, 1/2/4/8 bits per pixel, up to 640 x 1024): **1** from the SD card
(type its file name) or **2** from ownCloud (the `Documents/` picker, showing only `.bmx` files; the
file is downloaded as it is). On an empty line the picture goes there, otherwise after the paragraph
(or after the table / picture the cursor is in), and there is always a line after it to go on writing.

* On screen it is centred and drawn in the 16 Sunset colours, scaled like this: f = min(1, 496 / w,
  640 / h); w*f pixels wide, h*f/2 rows high (the screen's pixels are twice as tall as wide). A
  320 x 240 picture is 320 x 120, 15 lines. A picture is never split across pages.
* It is a run of lines with no text: the cursor can sit on it; **Backspace / Delete** on it delete
  the picture; **Enter**, typing or **Paste** on it go to a new line after it; Backspace at the start
  of the next line moves onto it (text is never merged into a picture). A selection that touches a
  picture deletes the whole picture. Align / lists / indent / page break leave pictures alone.
* Up to 15 pictures, as much as fits in 26 x 8 KB of RAM (two 320 x 240 x 8 bpp pictures, many
  small ones); a deleted picture's memory is reused.
* **RTF**: the BMX file is kept whole, as hex, in a `{\*\xwpbmx ...}` group between paragraphs:
  X16 Write gets it back exactly; other programs skip it. Through ownCloud the hub makes a real
  picture of it: in `.docx` (PNG, the same size as on the X16) and in `.rtf` (an extra PNG paragraph
  Word shows, removed again when the X16 opens the file). Pictures in Word documents (PNG / JPEG /
  GIF / BMP) arrive as BMX pictures (at most 320 x 240, 256 colours, about 160 KB per document).
* The code is two bank libraries: **X16WPPI.BIN** (RAM bank 54, `x16wppi.p8`: the picture table,
  drawing, keys / selections / paste, RTF export) and **X16WPPL.BIN** (RAM bank 56 at $A200,
  `x16wppl.p8`: the Picture button, reading BMX files, the palette map, RTF import, and the toolbar's
  tool tips); `pix.p8` is the main-RAM side. Without them there are no pictures and no tool tips.
* `selftest/run_bigtest.sh` runs long-document tests with 512 KB and with 2 MB: filling to 864 / 3456
  lines, lines in banks 64.., 16 / 64 pages, the full-document guards, slot reuse, RTF save -> load ->
  save of a full document, and 2 / 13 big pictures.
* `selftest/run_pictest.sh` tests pictures headless with the real libraries (test BMX files from
  `selftest/mkbmx.py`): insert, the key / selection / paste guards, paragraph operations, full memory,
  page breaks, and RTF save -> load -> save identical with the BMX files byte for byte.

## Save As: folders

**Save As** (SD card and ownCloud) shows a folder browser: the current folder's path, `..`, its
folders (blue, `/`) and files, and a name field. Double-click a folder (or select it with the arrow
keys and press Enter) to open it, `..` or **[ Up ]** to go up, **[New folder]** or **F7** to make a
folder, click a file to take its name; type a name and press Enter or **[ Save ]**. Esc / [Cancel]
leaves everything as it was.

* **SD card**: opening a folder changes the DOS current directory, so the document then lives there:
  plain Save and Open (by name) work in that folder. An existing file is only replaced after
  "Replace the existing file?". The SD listing is in directory order (folders first).
* **ownCloud**: the browser shows one folder of `Documents/` at a time; the document's full name
  (`Letters/2026/mom.rtf`, at most 63 bytes) is what Save writes back to later.
* `X16LINK.KEY` is always read from X16 Write's own folder, whatever the current directory is.
* The browser lives in `X16WPSA.BIN` (it needs the other ownCloud files too; without them Save As is
  the plain name prompt, as before).

## ownCloud: Open and Save As

Open and Save As each ask first: **1** = SD card (as before), **2** = ownCloud.

* **Open from ownCloud** shows the hub account's `Documents/` folder (subfolders included,
  sorted by name) with size, date and type. Use the arrow keys/PgUp/PgDn/mouse wheel to move,
  then Enter or double-click to open, or Esc to cancel. **RTF** files open as they are.
  **TXT** files are converted to RTF by the hub (UTF-8 → ISO-8859-15, characters with no
  equivalent become `?`, smart quotes/dashes become ASCII). **DOCX** (Word) files are converted to
  RTF by the hub too (bold/italic/underline, fonts, colours, alignment, indents, lists, page breaks,
  tables up to 8 columns; pictures become BMX pictures, see Pictures). Other types (spreadsheets are for X16 Sheets), and files
  over 1 MiB, are greyed out. The download goes to a temp file on the SD card and is checked with CRC-32
  before it replaces the document. A dropped link resumes where it stopped.
* **Save** of a document opened from ownCloud writes it back there, but only if nobody
  changed it in ownCloud meanwhile (the hub checks the etag).
* **Save As to ownCloud** asks for a folder and name in `Documents/` (`.rtf` keeps the full format,
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

Save As test (macOS, no ownCloud needed): `selftest/run_saveastest.sh` runs `selftest/saveas.p8` with
the real bank libraries on a FAT32 SD card image against the hub link server with an in-memory
ownCloud (`selftest/fakehub.py`, needs `../x16-office-hub` and its venv): new folders on both sides,
saving into them, Replace, Cancel going back, saving back to the same ownCloud file. `SHOT=1` records
`build/saveastest/shots.gif`.

## Notes / limits
* Document length depends on the X16's RAM: **16 pages** (864 lines) with the standard 512 KB, up to
  **64 pages** (3456 lines) with 1.5 MB or 2 MB (1 MB: about 53 pages). The extra lines go in RAM banks
  64..144 (`doc.p8`: line slots 864.. ; the map of used slots is in bank 58 next to the line order), and
  pictures also use the banks above them. A document that needs more pages than that (large fonts, page
  breaks) refuses new lines ("Document is full!"); opening a longer file keeps its beginning.
* Clipboard 2700 characters, file names are typed in a dialog.
* Opening RTF from other programs is best effort (colours map by index, one font family each).
* `selftest/selftest.p8` is a scripted headless test (builds a document, exports, re-imports).
* `selftest/run_tabletest.sh` tests tables headless with the real X16WPTB.BIN: insert, typing, Tab /
  Enter / Backspace, full cells, guards, selections, Delete table, RTF save -> load -> save identical.
