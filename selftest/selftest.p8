%import syslib
%import view
%import rtf
%zeropage basicsafe

main {
    sub typ(str s) {
        ubyte i = 0
        while s[i] != 0 {
            doc.insert_char(s[i])
            i++
        }
    }
    sub start() {
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        doc.init_doc()
        view.set_filename(iso:"demo.rtf")
        doc.para_op(0, 1)
        doc.apply_attr(0, 1)
        typ(iso:"X16 WRITE DEMO")
        doc.newline()
        doc.para_op(0, 0)
        doc.apply_attr(0, 1)
        doc.apply_attr(0, 2)
        typ(iso:"Plain, ")
        doc.apply_attr(0, 2)
        doc.apply_attr(0, 1)
        doc.apply_attr(0, 2)
        typ(iso:"italic ")
        doc.apply_attr(0, 2)
        doc.apply_attr(0, 4)
        typ(iso:"underline ")
        doc.apply_attr(0, 4)
        doc.apply_attr(2, 2)
        typ(iso:"red text ")
        doc.apply_attr(2, 0)
        doc.apply_attr(3, 7)
        typ(iso:"highlighted ")
        doc.apply_attr(3, 1)
        doc.apply_attr(1, 1)
        typ(iso:"PETSCII font ")
        doc.apply_attr(1, 0)
        typ(iso:"and a long run of text that must wrap around the right margin of the page nicely when it reaches it.")
        doc.newline()
        doc.para_op(2, 1)
        typ(iso:"First bullet item with enough words to wrap onto a second line in the list")
        doc.newline()
        typ(iso:"Second bullet")
        doc.newline()
        doc.para_op(2, 2)
        typ(iso:"Numbered one")
        doc.newline()
        typ(iso:"Numbered two")
        doc.newline()
        doc.para_op(2, 2)
        doc.para_op(1, 1)
        typ(iso:"Indented para")
        doc.newline()
        doc.para_op(0, 2)
        doc.para_op(1, 255)
        typ(iso:"Right aligned")
        doc.newline()
        doc.para_op(0, 1)
        typ(iso:"Centered")
        doc.newline()
        doc.page_break()
        doc.para_op(0, 0)
        typ(iso:"Second page")
        ; copy/paste test: select "Second" via anchor
        doc.sel_l = doc.curline
        doc.sel_c = 0
        doc.curcol = 6
        doc.sel_active = true
        doc.copy_selection()
        doc.clear_sel()
        doc.curcol = 11
        doc.newline()
        doc.paste()
        view.vtop = 0
        view.follow = false
        view.redraw_everything()
        view.draw_ruler()
        vid.text(60, 4, iso:"RULER TEST", 0, 0, 1)
        sys.wait(10)
        pokew($9fb5, 1)
        poke($9fb5, 1)
        sys.wait(20)
        if rtf.export(iso:"demo.rtf")
            txt.print("export ok\n")
        else
            txt.print("export FAILED\n")
        doc.init_doc()
        if rtf.import(iso:"demo.rtf")
            txt.print("import ok\n")
        else
            txt.print("import FAILED\n")
        txt.print_uw(doc.nlines)
        txt.print(" lines\n")
        view.redraw_everything()
        sys.wait(10)
        poke($9fb5, 1)
        sys.wait(20)
        if rtf.export(iso:"demo2.rtf")
            txt.print("export2 ok\n")
        repeat {
        }
    }
}
