; pictest.p8 - pictures, headless (selftest/run_pictest.sh): the real document model, view and RTF code
; with the real X16WPPI.BIN / X16WPPL.BIN (and X16WPTB.BIN), built against this program's symbols.
; The Picture button is driven through the keyboard buffer (no ownCloud files: the SD card is used).
; Prints PASS/FAIL lines and DONE; leaves PIC1.RTF / PIC2.RTF (save -> load -> save) and PIC3.RTF.

%import syslib
%import textio
%import view
%import rtf
%import cloudx
%zeropage basicsafe

main {
    ubyte fails

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
    }

    ; a key as X16 Write's main loop handles it: the picture and table libraries first
    sub k(ubyte c) {
        if pix.key(c)
            return
        if tblx.key(c)
            return
        when c {
            13 -> doc.newline()
            20 -> doc.backspace()
            127 -> doc.delete_fwd()
            else -> doc.insert_char(c)
        }
    }

    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            k(s[i])
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

    sub pic(uword l) -> ubyte {
        return doc.meta(l, doc.O_PIC)
    }

    ; the Picture button with this file name typed into its dialog
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
        check(pix.ready, iso:"picture libraries loaded")
        doc.init_doc()
        typ(iso:"Before")
        k(13)

        ; PIC8 (320 x 240): 15 lines, on the empty line 1 (before it)
        button(iso:"PIC8.BMX")
        check(doc.nlines == 17 and pic(1) != 0 and pic(15) == pic(1) and pic(16) == 0, iso:"PIC8 inserted as 15 lines before the empty line")
        check(doc.meta(1, doc.O_PROW) == 0 and doc.meta(15, doc.O_PROW) == 14 and doc.meta(8, 0) == 15, iso:"rows numbered, line count on every line")
        check(doc.curline == 1 and has(0, 0, iso:"Before"), iso:"cursor on the picture")

        ; typing on a picture goes to a new line after it
        typ(iso:"x")
        check(doc.nlines == 18 and has(16, 0, iso:"x") and doc.curline == 16 and pic(16) == 0, iso:"typing on a picture: new line after it")
        ; Backspace at the start of the next line: onto the picture, nothing merged
        doc.curcol = 0
        k(20)
        check(doc.nlines == 18 and doc.curline == 15 and has(16, 0, iso:"x"), iso:"Backspace after a picture moves onto it")
        ; paragraph operations and page break leave it alone
        doc.para_op(0, 1)
        doc.para_op(2, 1)
        doc.page_break()
        check(doc.nlines == 18 and pic(15) != 0 and doc.meta(15, doc.O_AL) == 0 and doc.meta(15, doc.O_LIST) == 0, iso:"align / list / page break keep the picture")

        ; a 4 bpp picture at the end, a bad file, a missing file
        doc.curline = 17
        doc.curcol = 0
        button(iso:"PIC4.BMX")
        check(doc.nlines == 21 and pic(17) != 0 and pic(17) != pic(1) and doc.meta(17, 0) == 3 and pic(20) == 0, iso:"PIC4 inserted (3 lines)")
        doc.curline = 20
        button(iso:"BAD.BMX")
        check(doc.nlines == 21, iso:"a file that isn't a BMX is refused")
        button(iso:"NOPE.BMX")
        check(doc.nlines == 21, iso:"a missing file is refused")

        ; save, load, save
        check(rtf.export(iso:"PIC1.RTF"), iso:"export")
        doc.init_doc()
        check(rtf.import(iso:"PIC1.RTF"), iso:"import")
        doc.repaginate()
        check(doc.nlines == 21 and has(0, 0, iso:"Before") and pic(1) != 0 and doc.meta(1, 0) == 15 and has(16, 0, iso:"x") and pic(17) != 0 and doc.meta(17, 0) == 3, iso:"pictures come back")
        check(rtf.export(iso:"PIC2.RTF"), iso:"export again")

        view.vtop = 0
        view.follow = false
        doc.curline = 16
        doc.curcol = 1
        view.redraw_everything()
        bool hc_on = cx16.VERA_L1_CONFIG == $13 and (cx16.VERA_DC_VIDEO & $20) != 0
        sys.wait(60)                ; -warp skips frames: let a whole one show before the snapshot
        @($9fb5) = 1
        sys.wait(10)
        ; (printing after the snapshot: the KERNAL writes text into VRAM that layer 1 now uses)
        check(hc_on, iso:"pictures in 256 colours on layer 1")

        ; a selection from text through PIC8 into the next line: the picture goes, the text joins
        doc.sel_l = 0
        doc.sel_c = 3
        doc.curline = 16
        doc.curcol = 1
        doc.sel_active = true
        doc.delete_selection()
        check(doc.nlines == 5 and has(0, 0, iso:"Bef") and doc.meta(0, doc.O_LEN) == 3 and pic(1) != 0 and doc.meta(1, 0) == 3, iso:"selection through a picture")
        ; paste on a picture: on a new line after it
        doc.curline = 2
        doc.curcol = 0
        doc.sel_l = 0
        doc.sel_c = 0
        doc.curline = 0
        doc.curcol = 3
        doc.sel_active = true
        doc.copy_selection()
        doc.sel_active = false
        doc.curline = 2
        doc.curcol = 0
        doc.paste()
        check(doc.nlines == 6 and pic(3) != 0 and has(4, 0, iso:"Bef"), iso:"paste on a picture goes after it")
        ; Delete on a picture removes it
        doc.curline = 2
        k(127)
        check(doc.nlines == 3 and pic(0) == 0 and pic(1) == 0 and pic(2) == 0 and has(1, 0, iso:"Bef"), iso:"Delete on a picture removes it")

        ; memory: two PIC8 fit (10 banks each of 26), a third doesn't; freed pictures are reused
        doc.init_doc()
        button(iso:"PIC8.BMX")
        doc.curline = doc.nlines - 1
        button(iso:"PIC8.BMX")
        check(doc.nlines == 31, iso:"two PIC8")
        doc.curline = doc.nlines - 1
        button(iso:"PIC8.BMX")
        check(doc.nlines == 31, iso:"no room for a third")
        doc.curline = 0
        k(8)
        doc.curline = doc.nlines - 1
        button(iso:"PIC8.BMX")
        check(doc.nlines == 31, iso:"a deleted picture's memory is reused")

        ; a document that starts with a picture; and a picture is kept on one page
        doc.init_doc()
        button(iso:"PIC1.BMX")
        check(doc.nlines == 5 and pic(0) != 0 and doc.meta(0, 0) == 4, iso:"PIC1 (1 bpp) at the start")
        doc.curline = 4
        ubyte i
        for i in 0 to 47
            k(13)
        button(iso:"PIC8.BMX")
        doc.repaginate()
        check(doc.page_of(52) == 1 and pic(52) != 0 and doc.meta(52, doc.O_PROW) == 0, iso:"a picture that doesn't fit starts a new page")
        check(rtf.export(iso:"PIC3.RTF"), iso:"export 3")
        doc.init_doc()
        check(rtf.import(iso:"PIC3.RTF"), iso:"import 3")
        check(pic(0) != 0 and doc.meta(0, 0) == 4 and pic(52) != 0 and doc.meta(52, 0) == 15, iso:"a picture first in the file comes back first")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        else
            txt.print(iso:"SOME FAILED\r")
        txt.print(iso:"DONE\r")
    }
}
