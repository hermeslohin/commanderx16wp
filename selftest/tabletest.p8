; tabletest.p8 - tables, headless (selftest/run_tabletest.sh): the real document model, view and RTF code
; with the real X16WPTB.BIN (built against this program's symbols). Prints PASS/FAIL lines and DONE.

%import syslib
%import textio
%import view
%import rtf
%zeropage basicsafe

main {
    ubyte fails

    ; never runs: makes sure every routine the bank library calls is in this program
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
    }

    ; a key as X16 Write's main loop handles it: the tables library first
    sub k(ubyte c) {
        if tblx.key(c)
            return
        when c {
            13 -> doc.newline()
            20 -> doc.backspace()
            9 -> {
                repeat 4
                    doc.insert_char(32)
            }
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

    sub start() {
        txt.iso()
        if txt.width() == 1
            keep()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        theme.init()
        tblx.load()
        check(tblx.ready, iso:"tables library loaded")
        doc.init_doc()
        typ(iso:"Before the table")
        k(13)

        ; Table button: change the suggested 3x3 to 4x3
        cx16.kbdbuf_put(20)
        cx16.kbdbuf_put(20)
        cx16.kbdbuf_put(20)
        cx16.kbdbuf_put(iso:'4')
        cx16.kbdbuf_put(iso:'x')
        cx16.kbdbuf_put(iso:'3')
        cx16.kbdbuf_put(13)
        tblx.tb_menu()
        check(doc.nlines == 5, iso:"4x3 table inserted on the empty line, a normal line after it")
        check(doc.meta(1, doc.O_TBL) == 4 | doc.TB_HEAD and doc.meta(2, doc.O_TBL) == 4 and doc.meta(3, doc.O_TBL) == 4 and doc.meta(4, doc.O_TBL) == 0, iso:"rows: header + 2, 4 columns")
        check(doc.meta(1, doc.O_LEN) == 61, iso:"row is 61 cells (4 x 15 + border)")
        check(doc.curline == 1 and doc.curcol == 1, iso:"cursor in the first cell")

        typ(iso:"Item")
        k(9)
        typ(iso:"Qty")
        k(9)
        typ(iso:"Price")
        k(9)
        typ(iso:"Note")
        k(9)
        typ(iso:"Pie")
        k(9)
        typ(iso:"2")
        k(9)
        typ(iso:"8.50")
        k(9)
        typ(iso:"apple")
        k(9)
        typ(iso:"Lemonade")
        k(9)
        typ(iso:"6")
        check(has(1, 1, iso:"Item") and has(1, 16, iso:"Qty") and has(1, 31, iso:"Price") and has(1, 46, iso:"Note"), iso:"Tab moves cell by cell")
        check(has(2, 1, iso:"Pie") and has(3, 1, iso:"Lemonade") and has(3, 16, iso:"6"), iso:"Tab wraps to the next row")
        k(9)
        k(9)
        k(9)
        check(doc.nlines == 6 and doc.meta(4, doc.O_TBL) == 4 and doc.curline == 4, iso:"Tab after the last cell adds a row")
        typ(iso:"Extra")
        k(20)
        k(20)
        check(has(4, 1, iso:"Ext ") and doc.curcol == 4, iso:"Backspace inside a cell")
        ; a full cell: 14 characters, the 15th is refused
        k(9)
        typ(iso:"ABCDEFGHIJKLMNOPQ")
        check(has(4, 16, iso:"ABCDEFGHIJKLMN") and has(4, 31, iso:" "), iso:"a full cell keeps its 14 characters")

        ; Enter in the last row leaves the table
        k(13)
        check(doc.curline == 5 and doc.meta(5, doc.O_TBL) == 0, iso:"Enter below the table")
        typ(iso:"After the table")
        doc.curcol = 0
        k(20)
        check(doc.nlines == 6 and has(5, 0, iso:"After") and doc.meta(4, doc.O_TBL) == 4, iso:"Backspace never merges text into a table")

        ; paragraph / page operations leave table rows alone
        doc.curline = 2
        doc.curcol = 3
        doc.para_op(0, 1)
        doc.para_op(1, 1)
        doc.page_break()
        check(doc.nlines == 6 and doc.meta(2, doc.O_TBL) == 4 and doc.meta(2, doc.O_LEN) == 61 and doc.meta(2, doc.O_IND) == 0, iso:"align / indent / page break keep the row")
        ; bold + another font on a selection across a row keeps the border glyphs
        doc.sel_l = 2
        doc.sel_c = 0
        doc.curcol = 61
        doc.sel_active = true
        doc.apply_attr(0, 1)
        doc.apply_attr(1, 1)
        doc.ld(2, doc.LB)
        check(doc.LB[doc.O_STY + 15] == $28 and doc.LB[doc.O_STY + 1] & 1 != 0, iso:"bold/font keep the borders")
        doc.apply_attr(1, 0)
        doc.apply_attr(0, 1)
        doc.sel_active = false

        ; save, load, save: the same file
        check(rtf.export(iso:"TBL.RTF"), iso:"export")
        doc.init_doc()
        check(rtf.import(iso:"TBL.RTF"), iso:"import")
        check(doc.nlines == 6 and doc.meta(1, doc.O_TBL) == 4 | doc.TB_HEAD and doc.meta(4, doc.O_TBL) == 4 and doc.meta(5, doc.O_TBL) == 0, iso:"rows come back")
        check(has(0, 0, iso:"Before") and has(1, 1, iso:"Item") and has(3, 1, iso:"Lemonade") and has(4, 16, iso:"ABCDEFGHIJKLMN") and has(5, 0, iso:"After"), iso:"cell text comes back")
        check(rtf.export(iso:"TBL2.RTF"), iso:"export again")

        view.vtop = 0
        view.follow = false
        doc.curline = 2
        doc.curcol = 5
        view.redraw_everything()
        sys.wait(5)
        @($9fb5) = 1
        sys.wait(10)

        ; a selection from text into a table: the header row goes, row 2 loses its first 2 characters
        doc.sel_l = 0
        doc.sel_c = 6
        doc.curline = 2
        doc.curcol = 3
        doc.sel_active = true
        doc.delete_selection()
        check(doc.nlines == 5 and has(0, 0, iso:"Before") and doc.meta(0, doc.O_LEN) == 6, iso:"selection: text part deleted")
        check(doc.meta(1, doc.O_TBL) == 4 | doc.TB_HEAD and has(1, 1, iso:"  e"), iso:"selection: header row removed, next row is the header")

        ; Delete table from the menu
        doc.curline = 2
        doc.curcol = 1
        cx16.kbdbuf_put(iso:'t')
        tblx.tb_menu()
        check(doc.nlines == 2 and doc.meta(1, doc.O_TBL) == 0 and has(1, 0, iso:"After"), iso:"Delete table")

        if fails == 0
            txt.print(iso:"ALL PASS\r")
        txt.print(iso:"DONE\r")
        repeat {
        }
    }
}
