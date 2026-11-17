# X16 Write - a mouse-driven word processor for the Commander X16 (Prog8)

Build: `make` (needs prog8c 12.x + 64tass). Run: `x16emu -prg x16wp.prg -run` (needs a mouse, 512 KB RAM).

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

## Notes / limits
* 16 pages max (864 lines), clipboard 2700 characters, file names are typed in a dialog.
* Opening RTF from other programs is best effort (colours map by index, one font family each).
* `selftest/selftest.p8` is a scripted headless test (builds a document, exports, re-imports).
