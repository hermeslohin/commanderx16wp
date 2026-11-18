; tblx.p8 - main-RAM side of tables in X16 Write. The table code itself is the bank library
; X16WPTB.BIN (RAM bank 57, source x16wptb.p8): typing in cells, the Table menu, deleting and pasting
; around tables, RTF export of table rows and RTF import of \trowd..\cell..\row. Without that file on
; the SD card tables are simply unavailable (the Table button says so).
;
; A table row is one document line with doc.O_TBL = number of columns (1..8), plus doc.TB_HEAD on the
; first row of a table. Columns are equal: cw = 63 / columns cells each; the line holds a border glyph
; at 0, cw, 2*cw, ... and the cell text between them (cw - 1 characters per cell), padded with spaces.

%import syslib
%import diskio

tblx {
    %option ignore_unused

    const ubyte BANK = 57
    bool ready

    extsub @bank BANK $A000 = tb_init() clobbers(A, X, Y)
    extsub @bank BANK $A003 = tb_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank BANK $A006 = tb_key(ubyte k @R0) clobbers(X, Y) -> bool @A
    extsub @bank BANK $A009 = tb_menu() clobbers(A, X, Y)
    extsub @bank BANK $A00C = tb_delsel() clobbers(X, Y) -> bool @A
    extsub @bank BANK $A00F = tb_paste() clobbers(X, Y) -> bool @A
    extsub @bank BANK $A012 = tb_export() clobbers(A, X, Y)
    extsub @bank BANK $A015 = tb_word() clobbers(A, X, Y)

    sub load() {
        ubyte b = cx16.getrambank()
        cx16.rambank(BANK)
        uword e = diskio.load_raw(iso:"X16WPTB.BIN", $a000)
        cx16.rambank(b)
        if e != 0 {
            tb_init()
            ready = tb_setup(&vid.text)
        }
    }

    sub key(ubyte k) -> bool {
        if not ready
            return false
        return tb_key(k)
    }

    sub delsel() -> bool {
        if not ready
            return false
        return tb_delsel()
    }

    sub paste() -> bool {
        if not ready
            return false
        return tb_paste()
    }
}
