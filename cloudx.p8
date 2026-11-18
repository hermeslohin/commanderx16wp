; cloudx.p8 - main-RAM side of the ownCloud feature of X16 Write.
; The UI itself (picker, Save As, conflict dialog) is the bank library X16WPCL.BIN (RAM bank 62,
; source x16wpcl.p8) so that it costs almost no main RAM; it uses X16LINK.BIN (bank 60) and
; X16DOCS.BIN (bank 61). All four files (plus X16LINK.KEY) go next to X16WP.PRG on the SD card.

%import x16link_api
%import view

cloudx {
    const ubyte BANK = 62
    str TMP = iso:"X16WP.TMP"
    str pct = iso:"Transferring    %  "
    bool ready

    extsub @bank BANK $A000 = cl_init() clobbers(A, X, Y)
    extsub @bank BANK $A003 = cl_setup(uword check @R0, uword tmpname @R1) clobbers(X, Y) -> bool @A
    extsub @bank BANK $A006 = cl_open() clobbers(A, X, Y)
    extsub @bank BANK $A009 = cl_save(ubyte ask @R0) clobbers(A, X, Y)
    extsub @bank BANK $A00C = cl_menu(ubyte which @R0) clobbers(X, Y) -> ubyte @A
    extsub @bank BANK $A00F = cl_is_cloud() clobbers(X, Y) -> bool @A
    extsub @bank BANK $A012 = cl_forget() clobbers(A, X, Y)

    sub load() -> bool {
        if ready
            return true
        if lkload.load() {
            ubyte b = cx16.getrambank()
            cx16.rambank(BANK)
            uword e = diskio.load_raw(iso:"X16WPCL.BIN", $a000)
            cx16.rambank(b)
            if e != 0 {
                cl_init()
                if cl_setup(&vid.text, TMP) {
                    lkapi.set_progress(&progress)
                    ready = true
                    return true
                }
            }
        }
        view.set_status(iso:"ownCloud files missing")
        return false
    }

    ; which: 0 = Open menu, 1 = Save As menu. Returns 0 = SD card, 1 = ownCloud (handled), 255 = cancel
    sub menu(ubyte which) -> ubyte {
        if not load()
            return 0                    ; no cloud support: plain SD card behaviour
        return cl_menu(which)
    }

    sub is_cloud() -> bool {
        return ready and cl_is_cloud()
    }

    sub save() {
        cl_save(0)
    }

    sub forget() {
        if ready
            cl_forget()
    }

    ; transfer progress from X16DOCS.BIN: r0 = done >> 8, r1 = total >> 8.
    ; Runs with RAM bank 61 mapped: only draws (VERA), never touches banked RAM.
    sub progress() {
        uword d = cx16.r0
        uword t = cx16.r1
        while t >= 600 {
            t >>= 1
            d >>= 1
        }
        ubyte p = 100
        if t != 0 and d < t
            p = lsb((d * 100) / t)
        pct[13] = iso:' '
        pct[14] = iso:' '
        if p >= 100 {
            pct[13] = iso:'1'
            pct[14] = iso:'0'
            p = 0
        } else if p >= 10
            pct[14] = iso:'0' + p / 10
        pct[15] = iso:'0' + p % 10
        vid.text(3, view.STATUS_ROW, pct, vid.S_BOLD, vid.C_YELLOW, vid.C_BLACK)
    }
}
