; themetest.p8 - themes, headless (selftest/run_themetest.sh): X16WPTH.BIN reads X16THEME.CFG and the
; theme files the way X16 Write does (main.themes() below is a copy of x16wp.p8's), then Quill's
; next() goes through all six themes and back to the first. A screenshot of every theme goes into
; snap.gif (one frame each). Prints PASS/FAIL lines and DONE.

%import syslib
%import textio
%import view
%import rtf
%zeropage basicsafe

main {
    ubyte fails

    extsub @bank 55 $A400 = th_init() clobbers(A, X, Y)
    extsub @bank 55 $A403 = th_run(uword rl @R0, uword dk @R1, uword msg @R2, uword cur @R3, ubyte what @R4) clobbers(X, Y) -> bool @A

    sub themes(ubyte what) -> bool {
        ubyte b = cx16.getrambank()
        cx16.rambank(55)
        uword e = diskio.load_raw(iso:"X16WPTH.BIN", $a400)
        cx16.rambank(b)
        if e == 0
            return false
        th_init()
        return th_run(&theme.rl, &theme.dk, &theme.msg, &theme.cur, what)
    }

    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            doc.insert_char(s[i])
            i++
        }
    }

    sub check(bool ok, str what) {
        if ok
            txt.print(iso:"PASS ")
        else {
            txt.print(iso:"FAIL ")
            fails++
        }
        txt.print(what)
        txt.nl()
    }

    sub snap() {
        view.set_status(theme.msg)
        view.redraw_everything()
        repeat 40 {
            sys.waitvsync()
            theme.tick()
        }
        @($9fb5) = 1                    ; x16emu: one frame into snap.gif
        sys.wait(4)
    }

    ubyte[6] seen

    sub start() {
        txt.iso()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        doc.init_doc()
        void diskio.delete(iso:"X16THEME.CFG")

        doc.apply_attr(4, doc.SZ_CODE[2])
        doc.apply_attr(2, vid.C_RED)
        typ(iso:"Picnic Day!")
        doc.newline()
        doc.apply_attr(4, doc.SZ_CODE[0])
        doc.apply_attr(2, vid.C_BLACK)
        doc.newline()
        typ(iso:"Dear Ruth and the whole gang,")
        doc.newline()
        doc.newline()
        typ(iso:"You are invited to our ")
        doc.apply_attr(3, vid.C_YELLOW)
        typ(iso:"summer picnic")
        doc.apply_attr(3, vid.C_WHITE)
        typ(iso:" at the lake on ")
        doc.apply_attr(0, 1)
        typ(iso:"Saturday at noon")
        doc.apply_attr(0, 1)
        typ(iso:".")
        doc.newline()
        doc.newline()
        doc.apply_attr(2, vid.C_GREEN)
        typ(iso:"Kayaks: we have two, first come")
        doc.newline()
        doc.apply_attr(2, vid.C_BLUE)
        typ(iso:"Music: Dave's ukulele (sorry)")
        doc.newline()
        doc.apply_attr(2, vid.C_PURPLE)
        typ(iso:"Rain plan: the pavilion")
        doc.apply_attr(2, vid.C_BLACK)
        doc.newline()
        doc.newline()
        typ(iso:"See you there, Margo")
        ; a selection on "the pavilion"
        doc.sel_l = 8
        doc.sel_c = 11
        doc.curline = 8
        doc.curcol = 23
        doc.sel_active = true
        doc.repaginate()

        check(themes(0) and theme.cur == 1, iso:"no X16THEME.CFG: theme 1")
        check(theme.rl[theme.R_TTL_CH] == 240 and theme.rl[theme.R_DESK_A] == 7, iso:"theme 1 is Sunset Arcade")
        seen[0] = theme.rl[theme.R_DESK]
        snap()
        ubyte i
        for i in 2 to 6 {
            bool ok = themes(1)
            check(ok and theme.cur == i, iso:"Quill: next theme")
            seen[i - 1] = theme.rl[theme.R_DESK]
            snap()
        }
        check(theme.dk[26] == $15 and theme.dk[0] == $91, iso:"the desk pattern (Winter Cabin)")
        check(seen[1] == vid.C_ORANGE and seen[2] == vid.C_LGRAY and seen[4] == vid.C_DGRAY, iso:"each theme's desk colour")
        check(themes(1) and theme.cur == 1, iso:"after the last theme the first again")
        ; restart: the saved choice
        void themes(1)
        void themes(1)
        theme.cur = 0
        theme.rl[theme.R_DESK] = 99
        check(themes(0) and theme.cur == 3 and theme.rl[theme.R_DESK] == vid.C_LGRAY, iso:"X16THEME.CFG brings back theme 3 (Comic Book)")
        check(theme.msg[7] == iso:'C' and theme.msg[13] == iso:'B', iso:"its name for the status bar")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
    }
}
