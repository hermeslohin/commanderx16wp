; bigtest.p8 - long documents, headless (selftest/run_bigtest.sh runs it with 512 KB and with 2 MB):
; 864 lines (16 pages) on 512 KB, 3456 lines (64 pages) with 1 MB+ of RAM (line slots in banks 64..),
; full-document guards, RTF save -> load -> save of a full document, and pictures in the extra banks.
; Prints PASS/FAIL lines and DONE; leaves BIG1.RTF / BIG2.RTF.

%import syslib
%import textio
%import view
%import rtf
%import cloudx
%zeropage basicsafe

main {
    ubyte fails
    uword want
    str nb = iso:"0000"
    str lw = iso:"Line"

    ; never runs: makes sure every routine the bank libraries call is in this program
    sub keep() {
        void view.dialog_input(iso:"", view.nbuf, 1)
        view.redraw_everything()
        view.draw_box(0, 0, 1, 1)
        view.put(0, 0, iso:"", 0, 0)
        view.num(0, 0, 0, 0, 0)
        view.poll_mouse()
        view.set_status(iso:"")
        view.draw_status()
        doc.mark_from(0)
        doc.setmeta(0, 0, 0)
        vid.fill(0, 0, 1, 0, 0)
        doc.paste()
        doc.cut_selection()
        void cloudx.menu(0)
        diskio.delete(iso:"")
        doc.sel_l = 0
        doc.sel_c = 0
        doc.sel_active = true
        doc.delete_selection()
        doc.copy_selection()
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

    ; line l has s at column c
    sub has(uword l, ubyte c, str s) -> bool {
        doc.ld(l, doc.LB)
        ubyte i = 0
        while s[i] != 0 {
            if doc.LB[doc.O_CH + c + i] != s[i]
                return false
            i++
        }
        return true
    }

    ; "Line nnnn" for line n
    sub num4(uword n) {
        nb[0] = iso:'0' + lsb(n / 1000)
        nb[1] = iso:'0' + lsb(n / 100 % 10)
        nb[2] = iso:'0' + lsb(n / 10 % 10)
        nb[3] = iso:'0' + lsb(n % 10)
    }

    ; line l becomes "Line nnnn" for n
    sub put_line(uword l, uword n) {
        num4(n)
        sys.memset(doc.LB, 256, 0)
        ubyte i
        for i in 0 to 3 {
            doc.LB[doc.O_CH + i] = lw[i]
            doc.LB[doc.O_CH + 5 + i] = nb[i]
            doc.LB[doc.O_COL + i] = $10
            doc.LB[doc.O_COL + 5 + i] = $10
        }
        doc.LB[doc.O_CH + 4] = 32
        doc.LB[doc.O_COL + 4] = $10
        doc.LB[doc.O_LEN] = 9
        doc.st(l, doc.LB)
    }

    ; appends a line "Line nnnn" (straight into a new slot, fast); false when the document is full
    sub add(uword n) -> bool {
        if not doc.insert_blank(doc.nlines)
            return false
        put_line(doc.nlines - 1, n)
        return true
    }

    sub line_is(uword l) -> bool {
        num4(l)
        return has(l, 0, iso:"Line ") and has(l, 5, nb)
    }

    sub button(str name) {
        ubyte i = 0
        while name[i] != 0 {
            cx16.kbdbuf_put(name[i])
            i++
        }
        cx16.kbdbuf_put(13)
        pix.pl_button()
        if doc.need_repag
            doc.repaginate()
    }

    sub start() {
        txt.iso()
        if txt.width() == 1
            keep()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        theme.init()
        tblx.load()
        pix.load()
        bool big = cx16.numbanks() >= 145
        want = 864
        if big
            want = 3456
        doc.init_doc()
        txt.print(iso:"banks ")
        txt.print_uw(cx16.numbanks())
        txt.print(iso:" maxlines ")
        txt.print_uw(doc.maxlines)
        txt.nl()
        check(doc.maxlines == want, iso:"room for 864 lines (512 KB) / 3456 lines (2 MB)")

        ; fill it: line 0 exists, add lines 1.. until the document is full
        put_line(0, 0)
        uword n = 1
        while add(n)
            n++
        doc.full_error = false
        check(doc.nlines == want, iso:"filled to the limit")
        check(line_is(0) and line_is(500) and line_is(want - 1), iso:"first, middle and last line read back")
        if big
            check(line_is(863) and line_is(864) and line_is(2000) and line_is(3455), iso:"lines in banks 64.. read back")
        doc.repaginate()
        check(doc.npages == lsb(want / 54), iso:"16 / 64 pages")
        check(not doc.insert_blank(5) and doc.full_error, iso:"a full document refuses another line")
        doc.full_error = false
        ; a deleted line's slot is used again
        doc.delete_line(10)
        check(add(9999) and doc.nlines == want and has(want - 1, 5, iso:"9999") and line_is(9) and has(10, 5, iso:"0011"), iso:"delete + add reuses the slot")
        doc.delete_line(want - 1)
        check(doc.insert_blank(10), iso:"insert in the middle")
        put_line(10, 10)
        check(doc.nlines == want and line_is(10) and line_is(11) and line_is(want - 1), iso:"document restored")

        ; page break: refused on page 63+
        doc.repaginate()
        doc.curline = want - 2
        doc.curcol = 0
        doc.page_break()
        doc.repaginate()
        check(doc.nlines == want and doc.npages == lsb(want / 54), iso:"no page break in a full document")
        doc.full_error = false

        ; save, load, save
        check(rtf.export(iso:"BIG1.RTF"), iso:"export")
        doc.init_doc()
        check(rtf.import(iso:"BIG1.RTF"), iso:"import")
        doc.repaginate()
        check(doc.nlines == want and line_is(0) and line_is(want / 2) and line_is(want - 1), iso:"every line comes back")
        txt.print(iso:"after import: lines ")
        txt.print_uw(doc.nlines)
        txt.print(iso:" pages ")
        txt.print_ub(doc.npages)
        txt.print(iso:" page 15 starts at ")
        txt.print_uw(doc.pfirst[15])
        txt.nl()
        check(doc.npages == lsb(want / 54), iso:"pages come back")
        check(rtf.export(iso:"BIG2.RTF"), iso:"export again")

        ; pictures: 2 x PIC8 fit in banks 28..53; with 2 MB 11 more fit above the lines
        doc.init_doc()
        ubyte i
        ubyte got = 0
        for i in 0 to 14 {
            doc.curline = doc.nlines - 1
            n = doc.nlines
            button(iso:"PIC8.BMX")
            if doc.nlines > n
                got++
        }
        txt.print(iso:"PIC8 pictures that fit: ")
        txt.print_ub(got)
        txt.nl()
        if big
            check(got == 13, iso:"13 big pictures fit with 2 MB")
        else
            check(got == 2, iso:"2 big pictures fit with 512 KB")
        view.vtop = 0
        view.follow = false
        doc.curline = 0
        view.redraw_everything()
        sys.wait(5)
        @($9fb5) = 1
        sys.wait(10)
        doc.repaginate()
        check(rtf.export(iso:"BIGP.RTF"), iso:"export with pictures")
        doc.init_doc()
        check(rtf.import(iso:"BIGP.RTF"), iso:"import with pictures")
        ubyte back = 0
        uword l
        for l in 0 to doc.nlines - 1 {
            if doc.meta(l, doc.O_PIC) != 0 and doc.meta(l, doc.O_PROW) == 0
                back++
        }
        check(back == got, iso:"every picture comes back")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
    }
}
