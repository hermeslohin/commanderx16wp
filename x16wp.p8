; X16 WRITE - a mouse driven word processor for the Commander X16, written in Prog8.
; Saves/loads RTF. See README.md

%import syslib
%import view
%import rtf
%import cloudx
%zeropage basicsafe

main {
    ubyte prev_btn
    ubyte drag_mode             ; 0 none, 1 text selection, 2 scroll bar
    ubyte wantx
    ubyte blink
    ubyte last_tip
    ubyte last_click_time
    uword last_click_line
    ubyte last_click_col
    ubyte snap_sty
    ubyte snap_fg
    ubyte snap_bg
    ubyte snap_al
    ubyte snap_list
    bool snap_mod
    ubyte snap_page
    ubyte snap_npages
    bool running = true
    ubyte scroll_timer

    sub start() {
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        theme.init()             ; after the icons: Sunset glyphs into font slot 3, Quill on
        tblx.load()              ; tables (X16WPTB.BIN, bank 57; uploads the Table icon)
        doc.init_doc()
        view.set_filename(iso:"untitled.rtf")
        view.set_status(iso:"Welcome! Click icons, type to edit")
        view.redraw_everything()
        take_snapshot()
        while running {
            sys.waitvsync()
            theme.tick()
            handle_keys()
            handle_mouse()
            blink_cursor()
            if doc.rd_mode != 0 or doc.need_repag {
                view.refresh()
            }
            if toolbar_changed() {
                view.draw_toolbar()
                take_snapshot()
            }
        }
        theme.off()
        vid.gfx_off()
    }

    sub take_snapshot() {
        snap_sty = doc.tsty
        snap_fg = doc.tfg
        snap_bg = doc.tbg
        snap_al = doc.meta(doc.curline, doc.O_AL)
        snap_list = doc.meta(doc.curline, doc.O_LIST)
        snap_mod = doc.modified
        snap_page = view.page_cur()
        snap_npages = doc.npages
    }

    sub toolbar_changed() -> bool {
        if snap_sty != doc.tsty or snap_fg != doc.tfg or snap_bg != doc.tbg or snap_mod != doc.modified
            return true
        if snap_page != view.page_cur() or snap_npages != doc.npages
            return true
        if snap_al != doc.meta(doc.curline, doc.O_AL) or snap_list != doc.meta(doc.curline, doc.O_LIST)
            return true
        return false
    }

    sub blink_cursor() {
        blink++
        if blink >= 30 {
            blink = 0
            view.cursor_on = not view.cursor_on
            doc.mark_range(doc.curline, doc.curline)
        }
    }

    sub cursor_event() {
        view.cursor_on = true
        blink = 0
        view.follow = true
        doc.mark_range(doc.curline, doc.curline)
    }

    ; ---------------- keyboard ----------------
    sub handle_keys() {
        ubyte k
        repeat 8 {
            k = cbm.GETIN2()
            if k == 0
                return
            key(k)
        }
    }

    sub nav_start() {
        doc.mark_range(doc.curline, doc.curline)
        doc.clear_sel()
    }

    sub key(ubyte k) {
        if tblx.key(k) {
            ; typed into a table cell (or a key that would break a table was refused)
            cursor_event()
            wantx = doc.cur_x()
            return
        }
        when k {
            13 -> {
                doc.newline()
                cursor_event()
                doc.sync_typing()
                wantx = doc.cur_x()
            }
            8, 20 -> {
                doc.backspace()
                cursor_event()
                wantx = doc.cur_x()
            }
            127, 25 -> {
                doc.delete_fwd()
                cursor_event()
            }
            $9d -> {
                nav_start()
                doc.move_left()
                after_horiz()
            }
            $1d -> {
                nav_start()
                doc.move_right()
                after_horiz()
            }
            $91 -> {
                nav_start()
                doc.move_vert(-1, wantx)
                after_vert()
            }
            $11 -> {
                nav_start()
                doc.move_vert(1, wantx)
                after_vert()
            }
            $13 -> {
                nav_start()
                doc.curcol = 0
                after_horiz()
            }
            $04 -> {
                nav_start()
                doc.curcol = doc.maxcol(doc.curline)
                after_horiz()
            }
            $82 -> {
                nav_start()
                repeat 20
                    doc.move_vert(-1, wantx)
                after_vert()
            }
            $02 -> {
                nav_start()
                repeat 20
                    doc.move_vert(1, wantx)
                after_vert()
            }
            9 -> {
                repeat 4
                    doc.insert_char(32)
                cursor_event()
                wantx = doc.cur_x()
            }
            else -> {
                if (k >= 32 and k < 127) or k >= 161 {
                    doc.insert_char(k)
                    cursor_event()
                    wantx = doc.cur_x()
                }
            }
        }
    }

    sub after_horiz() {
        doc.sync_typing()
        wantx = doc.cur_x()
        cursor_event()
    }

    sub after_vert() {
        doc.sync_typing()
        cursor_event()
    }

    ; ---------------- mouse ----------------
    sub handle_mouse() {
        view.poll_mouse()
        ubyte left = view.mouse_btn & 1
        ubyte cx = view.mouse_cx
        ubyte cy = view.mouse_cy
        if view.mouse_wheel != 0 {
            if view.mouse_wheel < 0
                view.set_vtop(view.vtop - 3)
            else
                view.set_vtop(view.vtop + 3)
        }
        if left != 0 and prev_btn == 0 {
            press(cx, cy)
        } else if left != 0 {
            drag(cx, cy)
        } else {
            drag_mode = 0
            hover(cx, cy)
        }
        prev_btn = left
    }

    sub hover(ubyte cx, ubyte cy) {
        ubyte id = view.find_button(cx, cy)
        if id != last_tip {
            last_tip = id
            if id != 0
                view.set_status(view.tip(id))
            else
                view.set_status(iso:"")
            view.draw_status()
        }
    }

    sub press(ubyte cx, ubyte cy) {
        ubyte id = view.find_button(cx, cy)
        if id != 0 {
            do_button(id)
            return
        }
        if cx == 79 and cy >= view.ROW0 and cy < view.ROW0 + view.VIEWROWS {
            drag_mode = 2
            scroll_bar(cy - view.ROW0, true)
            return
        }
        if view.pos_at(cx, cy) {
            uword l = cx16.r0
            ubyte c = cx16.r1L
            doc.mark_range(doc.curline, doc.curline)
            doc.clear_sel()
            doc.curline = l
            doc.curcol = c
            doc.sel_l = l
            doc.sel_c = c
            doc.sync_typing()
            wantx = doc.cur_x()
            drag_mode = 1
            view.cursor_on = true
            blink = 0
            doc.mark_range(l, l)
            ; double click selects the word
            ubyte now = lsb(cbm.RDTIM16())
            if l == last_click_line and c == last_click_col and (now - last_click_time) < 25
                select_word()
            last_click_time = now
            last_click_line = l
            last_click_col = c
        }
    }

    sub select_word() {
        doc.ld(doc.curline, doc.LB)
        ubyte ln = doc.LB[doc.O_LEN]
        ubyte a = doc.curcol
        ubyte b = doc.curcol
        if ln == 0
            return
        if a >= ln
            a = ln - 1
        while a > 0 and doc.LB[doc.O_CH + a - 1] != 32
            a--
        b = a
        while b < ln and doc.LB[doc.O_CH + b] != 32
            b++
        doc.sel_l = doc.curline
        doc.sel_c = a
        doc.curcol = b
        doc.sel_active = true
        doc.mark_range(doc.curline, doc.curline)
    }

    sub scroll_bar(ubyte sr, bool click) {
        if sr == 0 {
            if click
                view.set_vtop(view.vtop - 3)
        } else if sr >= view.VIEWROWS - 1 {
            if click
                view.set_vtop(view.vtop + 3)
        } else {
            view.set_vtop((view.max_vtop() / 22) * (sr - 1))
        }
    }

    sub drag(ubyte cx, ubyte cy) {
        if drag_mode == 2 {
            if cy >= view.ROW0
                scroll_bar(cy - view.ROW0, false)
            return
        }
        if drag_mode != 1
            return
        ubyte qy = cy
        scroll_timer++
        if cy < view.ROW0 {
            qy = view.ROW0
            if scroll_timer & 3 == 0
                view.set_vtop(view.vtop - 1)
        } else if cy >= view.ROW0 + view.VIEWROWS {
            qy = view.ROW0 + view.VIEWROWS - 1
            if scroll_timer & 3 == 0
                view.set_vtop(view.vtop + 1)
        }
        if view.pos_at(cx, qy) {
            uword l = cx16.r0
            ubyte c = cx16.r1L
            if l != doc.curline or c != doc.curcol {
                uword o = doc.curline
                doc.curline = l
                doc.curcol = c
                doc.sel_active = (l != doc.sel_l or c != doc.sel_c)
                if o < l
                    doc.mark_range(o, l)
                else
                    doc.mark_range(l, o)
            }
        }
    }

    ; ---------------- actions ----------------
    sub do_button(ubyte id) {
        when id {
            view.B_NEW -> new_doc()
            view.B_OPEN -> {
                ubyte m = cloudx.menu(0)
                view.redraw_everything()
                if m == 0
                    open_doc()
                else if m == 1
                    open_cloud()
            }
            view.B_SAVE -> {
                if cloudx.is_cloud()
                    cloudx.save()
                else
                    save_doc(false)
            }
            view.B_SAVEAS -> {
                ubyte m2 = cloudx.menu(1)
                view.redraw_everything()
                if m2 == 0 {
                    if cloudx.ready
                        cloudx.cl_save(2)       ; SD card Save As with the folder browser
                    else
                        save_doc(true)
                } else if m2 == 1
                    cloudx.cl_save(1)
            }
            view.B_CUT -> {
                doc.cut_selection()
                cursor_event()
            }
            view.B_COPY -> {
                doc.copy_selection()
                view.set_status(iso:"Copied")
                view.draw_status()
            }
            view.B_PASTE -> {
                doc.paste()
                cursor_event()
            }
            view.B_ALL -> doc.select_all()
            view.B_PGBRK -> {
                doc.page_break()
                cursor_event()
            }
            view.B_BOLD -> doc.apply_attr(0, vid.S_BOLD)
            view.B_ITAL -> doc.apply_attr(0, vid.S_ITAL)
            view.B_UNDER -> doc.apply_attr(0, vid.S_UNDER)
            view.B_AL -> doc.para_op(0, 0)
            view.B_AC -> doc.para_op(0, 1)
            view.B_AR -> doc.para_op(0, 2)
            view.B_BUL -> doc.para_op(2, 1)
            view.B_NUM -> doc.para_op(2, 2)
            view.B_OUT -> doc.para_op(1, 255)
            view.B_IND -> doc.para_op(1, 1)
            view.B_TABLE -> {
                if tblx.ready
                    tblx.tb_menu()
                else
                    view.set_status(iso:"Tables need X16WPTB.BIN on the SD card")
                cursor_event()
            }
            view.B_FONT -> {
                ubyte f = view.font_menu()
                doc.mark_all()
                view.redraw_everything()
                if f < 3
                    doc.apply_attr(1, f)
                else if f != 255
                    doc.apply_attr(4, f - 3)
            }
            view.B_QUIT -> {
                if doc.modified {
                    if not view.dialog_yesno(iso:"Quit without saving?") {
                        view.redraw_everything()
                        return
                    }
                }
                running = false
            }
            else -> {
                if id >= view.B_HIL0 and id < view.B_HIL0 + 16
                    doc.apply_attr(3, id - view.B_HIL0)
                else if id >= view.B_TXT0 and id < view.B_TXT0 + 16
                    doc.apply_attr(2, id - view.B_TXT0)
            }
        }
        if doc.full_error {
            doc.full_error = false
            view.set_status(iso:"Document is full!")
        }
        view.follow = true
    }

    sub new_doc() {
        if doc.modified {
            if not view.dialog_yesno(iso:"Discard the current document?") {
                view.redraw_everything()
                return
            }
        }
        doc.init_doc()
        cloudx.forget()
        view.vtop = 0
        view.set_filename(iso:"untitled.rtf")
        view.set_status(iso:"New document")
        view.redraw_everything()
    }

    sub open_doc() {
        if doc.modified {
            if not view.dialog_yesno(iso:"Discard the current document?") {
                view.redraw_everything()
                return
            }
        }
        view.nbuf[0] = 0
        if not view.dialog_input(iso:"Open RTF document", view.nbuf, 20) {
            view.redraw_everything()
            return
        }
        view.ensure_ext()
        if rtf.import(view.nbuf) {
            cloudx.forget()
            view.set_filename(view.nbuf)
            doc.modified = false
            view.vtop = 0
            view.set_status(iso:"Loaded")
            theme.cheer()
        } else {
            view.set_status(iso:"Could not open that file")
        }
        view.redraw_everything()
    }

    sub open_cloud() {
        if doc.modified {
            if not view.dialog_yesno(iso:"Discard the current document?") {
                view.redraw_everything()
                return
            }
        }
        cloudx.cl_open()
    }

    sub save_doc(bool ask) {
        if ask or view.is_untitled() {
            view.nbuf[0] = 0
            if not ask
                view.copy_name_to_buf()
            if not view.dialog_input(iso:"Save RTF document", view.nbuf, 20) {
                view.redraw_everything()
                return
            }
            view.ensure_ext()
        } else
            view.copy_name_to_buf()
        if rtf.export(view.nbuf) {
            cloudx.forget()
            view.set_filename(view.nbuf)
            doc.modified = false
            view.set_status(iso:"Saved as RTF")
            theme.cheer()
        } else {
            view.set_status(iso:"SAVE FAILED")
        }
        view.redraw_everything()
    }
}
