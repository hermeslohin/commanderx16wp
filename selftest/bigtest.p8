; bigtest.p8 - long documents, headless (selftest/run_bigtest.sh runs it with 512 KB and with 2 MB, on
; the host file system, and with 512 KB on a FAT32 SD card image).
; Part 1, without X16WPVM.BIN: the document is as long as the frame banks hold, 736 lines on 512 KB,
; 3328 lines with 2 MB (line slots in banks 64..).
; Part 2, with X16WPVM.BIN: 8192 lines, far more than the RAM holds, so sections go to swap files and
; come back: read-back across the line order banks, inserting / deleting (the line order moves across
; banks), a changed line that was swapped out, full-document guards, RTF save -> load -> save, and on
; the SD card (file SDTEST there) a change of the current folder while lines are swapped out.
; Then pictures in the extra banks. Prints PASS/FAIL lines and DONE; leaves BIG1.RTF / BIG2.RTF.

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

    ; fill the document: line 0 exists, add lines 1.. until it is full
    sub fill() {
        put_line(0, 0)
        uword n = 1
        while add(n)
            n++
        doc.full_error = false
        check(doc.nlines == want, iso:"filled to the limit")
    }

    ; pages, guards, delete / insert, RTF save -> load -> save of the full document
    sub guards() {
        uword pages = (want + 53) / 54
        doc.repaginate()
        check(doc.npages == lsb(pages), iso:"pages of a full document")
        check(not doc.insert_blank(5) and doc.full_error, iso:"a full document refuses another line")
        doc.full_error = false
        ; a deleted line's slot is used again
        doc.delete_line(10)
        check(add(9999) and doc.nlines == want and has(want - 1, 5, iso:"9999") and line_is(9) and has(10, 5, iso:"0011"), iso:"delete + add reuses the slot")
        check((has(2047, 5, iso:"2048") and has(2048, 5, iso:"2049")) or want < 2050, iso:"delete moved the lines across the order banks")
        doc.delete_line(want - 1)
        check(doc.insert_blank(10), iso:"insert in the middle")
        put_line(10, 10)
        check(doc.nlines == want and line_is(10) and line_is(11) and line_is(want - 1), iso:"document restored")
        check((line_is(2047) and line_is(2048)) or want < 2050, iso:"insert moved the lines back across the order banks")

        ; page break: refused when the document is full
        doc.repaginate()
        doc.curline = want - 2
        doc.curcol = 0
        doc.page_break()
        doc.repaginate()
        check(doc.nlines == want and doc.npages == lsb(pages), iso:"no page break in a full document")
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
        txt.print(iso:" page 13 starts at ")
        txt.print_uw(doc.pf(13))
        txt.nl()
        check(doc.npages == lsb(pages) and doc.pf(13) == 13 * 54, iso:"pages come back")
        check(rtf.export(iso:"BIG2.RTF"), iso:"export again")
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
        bool sd = diskio.exists(iso:"SDTEST")

        ; ---- part 1: no X16WPVM.BIN, the document lives in the frame banks ----
        want = 736
        if big
            want = 3328
        doc.init_doc()
        txt.print(iso:"banks ")
        txt.print_uw(cx16.numbanks())
        txt.print(iso:" maxlines ")
        txt.print_uw(doc.maxlines)
        txt.nl()
        check(not doc.vm_on and doc.maxlines == want, iso:"no swap: room for 736 lines (512 KB) / 3328 lines (2 MB)")
        fill()
        check(line_is(0) and line_is(500) and line_is(want - 1), iso:"first, middle and last line read back")
        if big
            check(line_is(735) and line_is(736) and line_is(2000) and line_is(3327), iso:"lines in banks 64.. read back")
        guards()

        ; ---- part 2: X16WPVM.BIN, swap files ----
        doc.vm_load()
        want = 8192
        doc.init_doc()
        check(doc.vm_on and doc.maxlines == want, iso:"X16WPVM.BIN: room for 8192 lines")
        fill()
        check(line_is(0) and line_is(2047) and line_is(2048) and line_is(4095) and line_is(4096) and line_is(6143) and line_is(6144) and line_is(want - 1), iso:"lines on both sides of the line order banks read back")
        check(line_is(1) and line_is(want - 2) and line_is(0) and line_is(want / 2) and line_is(700) and line_is(7000), iso:"swapped-out lines come back in any order")
        ; a changed line that then gets swapped out keeps the change
        put_line(100, 5555)
        check(line_is(want - 1) and line_is(4000) and has(100, 5, iso:"5555"), iso:"a changed line comes back from its swap file")
        put_line(100, 100)
        if sd {
            ; Save As into a folder changes the current folder: the swap files have an absolute path
            diskio.mkdir(iso:"SUB")
            diskio.chdir(iso:"SUB")
            check(line_is(3) and line_is(8000) and line_is(3000) and line_is(100), iso:"lines come back after a change of folder")
            diskio.chdir(iso:"..")
        }
        guards()
        doc.vm_end()

        ; pictures: 2 x PIC8 fit in banks 28..53; with 2 MB 11 more fit above the lines
        doc.vm_load()
        doc.init_doc()
        uword n
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
        doc.vm_end()

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
    }
}
