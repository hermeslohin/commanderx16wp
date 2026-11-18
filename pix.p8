; pix.p8 - main-RAM side of pictures in X16 Write. The picture code itself is two bank libraries:
; X16WPPI.BIN (RAM bank 54, source x16wppi.p8: the picture table, drawing pictures in the page,
; keeping the cursor and selections from breaking them, RTF export) and X16WPPL.BIN (RAM bank 56 at
; $A200, source x16wppl.p8: the Picture button, reading BMX files, RTF import of {\*\xwpbmx HEX},
; and the toolbar's tool tips). Without those files pictures (and tool tips) are unavailable.
;
; A picture is a run of lines (one screen row each, no text): doc.O_PIC = picture id (1..15),
; doc.O_PROW = row of the picture on this line, and byte 0 of every picture line = the number of
; lines of the picture (repaginate keeps a picture on one page). The BMX data lives in RAM banks
; 28..53 (see x16wppi.p8).

%import syslib
%import diskio

pix {
    %option ignore_unused

    const ubyte BANK = 54               ; X16WPPI.BIN at $A000
    const ubyte LBANK = 56              ; X16WPPL.BIN at $A200 (rtf.p8's file buffer is $A000-$A1FF)
    bool ready

    extsub @bank BANK $A000 = pi_init() clobbers(A, X, Y)
    extsub @bank BANK $A003 = pi_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank BANK $A006 = pi_key(ubyte k @R0) clobbers(X, Y) -> bool @A
    extsub @bank BANK $A009 = pi_delsel() clobbers(X, Y) -> bool @A
    extsub @bank BANK $A00C = pi_draw(ubyte sr @R0) clobbers(A, X, Y)
    extsub @bank BANK $A00F = pi_export() clobbers(A, X, Y)
    extsub @bank BANK $A012 = pi_paste() clobbers(A, X, Y)
    extsub @bank LBANK $A200 = pl_init() clobbers(A, X, Y)
    extsub @bank LBANK $A203 = pl_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank LBANK $A206 = pl_button() clobbers(A, X, Y)
    extsub @bank LBANK $A209 = pl_import() clobbers(A, X, Y)
    extsub @bank LBANK $A20C = pl_tip(ubyte id @R0) clobbers(A, X, Y)

    sub load() {
        ubyte b = cx16.getrambank()
        cx16.rambank(BANK)
        uword e = diskio.load_raw(iso:"X16WPPI.BIN", $a000)
        cx16.rambank(LBANK)
        if diskio.load_raw(iso:"X16WPPL.BIN", $a200) == 0
            e = 0
        cx16.rambank(b)
        if e != 0 {
            pi_init()
            pl_init()
            ready = pi_setup(&vid.text) and pl_setup(&vid.text)
        }
        cx16.r15 = &doc.bxfer               ; keeps the libraries' bank copy helper in the build
    }

    ; true: the key was handled (or refused) on or next to a picture
    sub key(ubyte k) -> bool {
        if not ready
            return false
        return pi_key(k)
    }

    ; true: the selection touched pictures and was deleted here
    sub delsel() -> bool {
        if not ready
            return false
        return pi_delsel()
    }

    sub paste() {
        if ready
            pi_paste()
    }

    sub tip(ubyte id) {
        if ready
            pl_tip(id)
    }
}
