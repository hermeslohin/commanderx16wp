; sizetest.p8 - font sizes 12, 18, 24 and 36 pt, headless (selftest/run_sizetest.sh): line heights,
; widths, wrapping, pages, mouse columns, RTF \fs and \sl, save -> load -> save. Prints PASS/FAIL and DONE.

%import syslib
%import textio
%import view
%import rtf
%zeropage basicsafe

main {
    ubyte fails

    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            doc.insert_char(s[i])
            i++
        }
    }

    sub size(ubyte n) {
        doc.apply_attr(4, doc.SZ_CODE[n])       ; 0 12 pt, 1 18 pt, 2 24 pt, 3 36 pt
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

    sub h(uword l) -> ubyte {
        return doc.line_h(doc.meta(l, doc.O_FLG))
    }

    sub start() {
        txt.iso()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        theme.init()
        doc.init_doc()

        size(3)
        typ(iso:"Big 36")
        doc.newline()
        size(2)
        typ(iso:"Large 24")
        doc.newline()
        size(1)
        typ(iso:"Medium 18 pt")
        doc.newline()
        size(0)
        typ(iso:"Normal 12 pt, then ")
        size(3)
        typ(iso:"36")
        size(0)
        typ(iso:" in one line")
        doc.newline()
        typ(iso:"Normal")
        check(h(0) == 3 and h(1) == 2 and h(2) == 2 and h(3) == 3 and h(4) == 1, iso:"line heights 3, 2, 2, 3 (mixed), 1")
        doc.ld(0, doc.LB)
        check(doc.LB[doc.O_STY] & doc.SZ_MASK == $c0 and doc.cells_of(doc.LB, 6) == 18, iso:"36 pt: 3 cells wide")
        doc.ld(2, doc.LB)
        check(doc.LB[doc.O_STY] & doc.SZ_MASK == $80 and doc.cells_of(doc.LB, 12) == 24, iso:"18 pt: 2 cells wide")
        uword nm = view.size_name[doc.tsty >> 6]
        uword nm36 = view.size_name[3]
        check(@(nm) == iso:'1' and @(nm + 1) == iso:'2' and @(nm36 + 1) == iso:'6', iso:"toolbar size names")

        ; 36 pt wraps at 21 characters (64 / 3)
        doc.curline = 0
        doc.curcol = 6
        doc.sync_typing()
        check(doc.tsty & doc.SZ_MASK == $c0, iso:"typing size follows the text")
        typ(iso:" ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        ; "Big 36 " / "ABCDEFGHIJKLMNOPQRSTU" / "VWXYZ": 7 + 21 + 5 characters on three 36 pt lines
        check(doc.nlines == 7 and doc.meta(0, doc.O_LEN) == 7 and doc.meta(1, doc.O_LEN) == 21 and doc.meta(2, doc.O_FLG) & doc.F_SOFT != 0 and h(2) == 3, iso:"36 pt text wraps at 21 characters")

        ; pages: rows add up (1 page = 54 rows)
        doc.repaginate()
        uword r = 0
        uword l
        for l in 0 to doc.nlines - 1
            r += h(l)
        check(doc.npages == 1 and r == 3 + 3 + 3 + 2 + 2 + 3 + 1, iso:"rows of the page")
        ; the page map: line 1 takes virtual rows 4..6 (row 0 is the page title)
        check(doc.vrow_of(1) == 4 and doc.vrow_info(6) == 0 and cx16.r0 == 1 and cx16.r1L == 2, iso:"page map with 3-row lines")
        check(doc.vrow_info(7) == 0 and cx16.r0 == 2 and cx16.r1L == 0, iso:"next line after a 3-row line")
        ; mouse: cell 4 of a 36 pt line is the 2nd character; cell 5 is its right part -> the 3rd
        check(doc.col_for_x(0, 4) == 1 and doc.col_for_x(0, 5) == 2, iso:"mouse columns in 36 pt")

        ; 18 pt -> 36 pt on a selection re-heights the line, and back
        doc.sel_l = 4
        doc.sel_c = 0
        doc.curline = 4
        doc.curcol = 6
        doc.sel_active = true
        doc.apply_attr(4, $c0)
        check(h(4) == 3, iso:"a selection made 36 pt: line is 3 rows")
        doc.apply_attr(4, $80)
        doc.sel_active = false
        check(h(4) == 2, iso:"and back to 18 pt: 2 rows")

        check(rtf.export(iso:"SIZES.RTF"), iso:"export")
        doc.init_doc()
        check(rtf.import(iso:"SIZES.RTF"), iso:"import")
        check(doc.nlines == 7 and h(0) == 3 and h(2) == 3 and h(3) == 2 and h(4) == 2 and h(5) == 3 and h(6) == 1, iso:"heights come back")
        doc.ld(4, doc.LB)
        check(doc.LB[doc.O_STY] & doc.SZ_MASK == $80, iso:"18 pt comes back")
        check(rtf.export(iso:"SIZES2.RTF"), iso:"export again")

        view.vtop = 0
        view.follow = false
        doc.curline = 0
        doc.curcol = 2
        view.redraw_everything()
        sys.wait(5)
        @($9fb5) = 1
        sys.wait(10)
        if fails == 0
            txt.print(iso:"ALL PASS\r")
        txt.print(iso:"DONE\r")
        repeat {
        }
    }
}
