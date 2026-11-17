; view.p8 - screen layout: icon toolbars, ruler, scrolling page view with border, status bar, dialogs.

%import syslib
%import conv
%import vid
%import doc

view {
    %option ignore_unused

    const ubyte PAGE_X = 8              ; screen column of document column 0
    const ubyte ROW0 = 5                ; first screen row of the page view
    const ubyte VIEWROWS = 24
    const ubyte STATUS_ROW = 29

    ; button ids
    const ubyte B_NEW = 1
    const ubyte B_OPEN = 2
    const ubyte B_SAVE = 3
    const ubyte B_SAVEAS = 4
    const ubyte B_CUT = 5
    const ubyte B_COPY = 6
    const ubyte B_PASTE = 7
    const ubyte B_ALL = 8
    const ubyte B_PGBRK = 9
    const ubyte B_BOLD = 10
    const ubyte B_ITAL = 11
    const ubyte B_UNDER = 12
    const ubyte B_AL = 13
    const ubyte B_AC = 14
    const ubyte B_AR = 15
    const ubyte B_BUL = 16
    const ubyte B_NUM = 17
    const ubyte B_OUT = 18
    const ubyte B_IND = 19
    const ubyte B_QUIT = 20
    const ubyte B_FONT = 21
    const ubyte B_TXT0 = 100            ; text colour swatches 100..115
    const ubyte B_HIL0 = 120            ; highlight swatches 120..135
    const ubyte B_SCROLL = 200          ; returned for the scroll bar column
    const ubyte B_PAGE = 201            ; returned for the page area

    ; 16x8 pixel icons, two glyphs each (hi byte = left half, lo byte = right half)
    ubyte[160] ic_hi = [
        $1f,$10,$10,$10,$10,$10,$10,$1f,
        $00,$3c,$43,$40,$40,$40,$40,$3f,
        $3f,$2f,$2f,$20,$2f,$28,$28,$3f,
        $3f,$2f,$2f,$20,$2f,$28,$28,$3f,
        $20,$10,$08,$04,$02,$05,$09,$11,
        $1f,$10,$13,$12,$13,$1e,$02,$03,
        $07,$1f,$18,$17,$10,$17,$10,$1f,
        $ff,$80,$8c,$92,$9e,$92,$80,$ff,
        $1f,$10,$10,$00,$aa,$00,$10,$1f,
        $0f,$0c,$0c,$0f,$0c,$0c,$0c,$0f,
        $03,$00,$01,$01,$03,$03,$06,$0f,
        $0c,$0c,$0c,$0c,$0c,$0f,$00,$3f,
        $7f,$00,$7f,$00,$7f,$00,$7f,$00,
        $3f,$00,$0f,$00,$3f,$00,$0f,$00,
        $3f,$00,$0f,$00,$3f,$00,$0f,$00,
        $e3,$00,$e3,$00,$e3,$00,$e3,$00,
        $47,$00,$4b,$00,$53,$00,$67,$00,
        $7f,$00,$23,$67,$a3,$67,$23,$00,
        $7f,$00,$8b,$cd,$ff,$cd,$8b,$00,
        $c0,$60,$30,$18,$18,$30,$60,$c0 ]
    ubyte[160] ic_lo = [
        $f0,$18,$14,$1e,$02,$02,$02,$fe,
        $00,$00,$f0,$08,$08,$08,$08,$f0,
        $fc,$f4,$f4,$04,$f4,$14,$14,$fc,
        $fc,$f6,$fa,$04,$f4,$14,$14,$fc,
        $08,$10,$20,$40,$80,$40,$20,$10,
        $e0,$20,$fc,$04,$a4,$24,$04,$fc,
        $e0,$f8,$18,$e8,$08,$e8,$08,$f8,
        $fe,$02,$62,$92,$f2,$92,$02,$fe,
        $f8,$08,$08,$00,$aa,$00,$08,$f8,
        $f0,$18,$18,$f0,$18,$18,$18,$f0,
        $f0,$c0,$80,$80,$00,$00,$00,$c0,
        $30,$30,$30,$30,$30,$f0,$00,$fc,
        $f8,$00,$00,$00,$f8,$00,$00,$00,
        $fc,$00,$f0,$00,$fc,$00,$f0,$00,
        $fe,$00,$fe,$00,$fe,$00,$fe,$00,
        $fc,$00,$fc,$00,$fc,$00,$fc,$00,
        $fc,$00,$fc,$00,$fc,$00,$fc,$00,
        $fc,$00,$fc,$fc,$fc,$fc,$fc,$00,
        $fc,$00,$f8,$f8,$f8,$f8,$f8,$00,
        $03,$06,$0c,$18,$18,$0c,$06,$03 ]

    ubyte[64] bt_x
    ubyte[64] bt_y
    ubyte[64] bt_w
    ubyte[64] bt_id
    ubyte bt_n

    uword vtop
    bool cursor_on = true
    str status_msg = iso:"                                                  "
    str filename = iso:"untitled.rtf                "
    str nbuf = iso:"                              "
    bool follow = true
    str tmpnum = iso:"     "

    sub init() {
        ; upload the icon glyphs into font slot 3
        ubyte k
        ubyte r
        sys.set_irqd()
        cx16.vaddr(1, vid.FONT_VRAM + 3 * 2048, 0, 1)
        for k in 0 to 19 {
            ; left glyph (8 bytes) then right glyph (8 bytes)
            for r in 0 to 7
                cx16.VERA_DATA0 = ic_hi[k * 8 + r]
            for r in 0 to 7
                cx16.VERA_DATA0 = ic_lo[k * 8 + r]
        }
        sys.clear_irqd()
    }

    sub set_filename(str s) {
        ubyte i = 0
        while s[i] != 0 and i < 24 {
            filename[i] = s[i]
            i++
        }
        filename[i] = 0
    }

    sub copy_name_to_buf() {
        ubyte i = 0
        while filename[i] != 0 {
            nbuf[i] = filename[i]
            i++
        }
        nbuf[i] = 0
    }

    sub is_untitled() -> bool {
        return filename[0] == iso:'u' and filename[1] == iso:'n' and filename[2] == iso:'t'
    }

    sub ensure_ext() {
        ubyte i = 0
        bool dot = false
        while nbuf[i] != 0 {
            if nbuf[i] == iso:'.'
                dot = true
            i++
        }
        if not dot and i < 24 {
            nbuf[i] = iso:'.'
            nbuf[i + 1] = iso:'r'
            nbuf[i + 2] = iso:'t'
            nbuf[i + 3] = iso:'f'
            nbuf[i + 4] = 0
        }
    }

    sub tip(ubyte id) -> str {
        when id {
            B_NEW -> return iso:"New document"
            B_OPEN -> return iso:"Open from SD card or ownCloud"
            B_SAVE -> return iso:"Save (back to ownCloud if opened there)"
            B_SAVEAS -> return iso:"Save As on SD card or ownCloud"
            B_CUT -> return iso:"Cut"
            B_COPY -> return iso:"Copy"
            B_PASTE -> return iso:"Paste"
            B_ALL -> return iso:"Select all"
            B_PGBRK -> return iso:"Insert page break"
            B_BOLD -> return iso:"Bold"
            B_ITAL -> return iso:"Italic"
            B_UNDER -> return iso:"Underline"
            B_AL -> return iso:"Align left"
            B_AC -> return iso:"Center"
            B_AR -> return iso:"Align right"
            B_BUL -> return iso:"Bulleted list"
            B_NUM -> return iso:"Numbered list"
            B_OUT -> return iso:"Decrease indent"
            B_IND -> return iso:"Increase indent"
            B_QUIT -> return iso:"Quit"
            B_FONT -> return iso:"Change font"
        }
        if id >= B_TXT0 and id < B_TXT0 + 16
            return iso:"Text color"
        if id >= B_HIL0 and id < B_HIL0 + 16
            return iso:"Highlight color"
        return iso:""
    }

    sub add_btn(ubyte x, ubyte y, ubyte w, ubyte id) {
        if bt_n < 64 {
            bt_x[bt_n] = x
            bt_y[bt_n] = y
            bt_w[bt_n] = w
            bt_id[bt_n] = id
            bt_n++
        }
    }

    sub icon(ubyte col, ubyte row, ubyte k, ubyte id, bool active) {
        ubyte bg = vid.C_WHITE
        if active
            bg = vid.C_LBLUE
        vid.r_ch[0] = k * 2
        vid.r_ch[1] = k * 2 + 1
        vid.r_sty[0] = vid.S_RAW | $30
        vid.r_sty[1] = vid.S_RAW | $30
        vid.r_col[0] = (bg << 4)
        vid.r_col[1] = (bg << 4)
        vid.render_run(row, col, 2)
        add_btn(col, row, 2, id)
    }

    sub find_button(ubyte cx, ubyte cy) -> ubyte {
        ubyte i
        if bt_n == 0
            return 0
        for i in 0 to bt_n - 1 {
            if bt_y[i] == cy and cx >= bt_x[i] and cx < bt_x[i] + bt_w[i]
                return bt_id[i]
        }
        return 0
    }

    sub put(ubyte col, ubyte row, str s, ubyte fg, ubyte bg) {
        vid.text(col, row, s, 0, fg, bg)
    }

    sub num(ubyte col, ubyte row, uword n, ubyte fg, ubyte bg) {
        uword s = conv.str_uw(n)
        ubyte i = 0
        ubyte c
        while s[i] != 0 {
            tmpnum[i] = s[i]
            i++
        }
        tmpnum[i] = 0
        vid.text(col, row, tmpnum, 0, fg, bg)
    }

    ; ---------------- toolbar ----------------
    sub draw_toolbar() {
        bt_n = 0
        ; title bar
        vid.fill(0, 0, 80, vid.C_WHITE, vid.C_BLUE)
        put(1, 0, iso:"X16 WRITE", vid.C_YELLOW, vid.C_BLUE)
        put(11, 0, iso:"-", vid.C_WHITE, vid.C_BLUE)
        put(13, 0, filename, vid.C_WHITE, vid.C_BLUE)
        if doc.modified
            put(30, 0, iso:"(modified)", vid.C_LRED, vid.C_BLUE)
        put(60, 0, iso:"Page", vid.C_WHITE, vid.C_BLUE)
        num(65, 0, page_cur() + 1, vid.C_WHITE, vid.C_BLUE)
        put(68, 0, iso:"of", vid.C_WHITE, vid.C_BLUE)
        num(71, 0, doc.npages, vid.C_WHITE, vid.C_BLUE)
        icon(77, 0, 19, B_QUIT, false)

        vid.fill(0, 1, 80, 0, vid.C_LGRAY)
        vid.fill(0, 2, 80, 0, vid.C_LGRAY)
        vid.fill(0, 3, 80, 0, vid.C_LGRAY)
        ; row 1: file / edit / page
        icon(1, 1, 0, B_NEW, false)
        icon(4, 1, 1, B_OPEN, false)
        icon(7, 1, 2, B_SAVE, false)
        icon(10, 1, 3, B_SAVEAS, false)
        icon(15, 1, 4, B_CUT, false)
        icon(18, 1, 5, B_COPY, false)
        icon(21, 1, 6, B_PASTE, false)
        icon(24, 1, 7, B_ALL, false)
        icon(29, 1, 8, B_PGBRK, false)
        ; row 2: character + paragraph formatting
        icon(1, 2, 9, B_BOLD, (doc.tsty & 1) != 0)
        icon(4, 2, 10, B_ITAL, (doc.tsty & 2) != 0)
        icon(7, 2, 11, B_UNDER, (doc.tsty & 4) != 0)
        ubyte al = doc.meta(doc.curline, doc.O_AL)
        ubyte li = doc.meta(doc.curline, doc.O_LIST)
        icon(12, 2, 12, B_AL, al == 0)
        icon(15, 2, 13, B_AC, al == 1)
        icon(18, 2, 14, B_AR, al == 2)
        icon(23, 2, 15, B_BUL, li == 1)
        icon(26, 2, 16, B_NUM, li == 2)
        icon(31, 2, 17, B_OUT, false)
        icon(34, 2, 18, B_IND, false)
        ; font selector
        ubyte f = (doc.tsty >> 4) & 3
        vid.fill(39, 2, 22, 0, vid.C_WHITE)
        vid.text(40, 2, vid.font_name(f), (f << 4), 0, vid.C_WHITE)
        vid.text(60, 2, iso:"v", 0, 0, vid.C_WHITE)
        add_btn(39, 2, 22, B_FONT)
        ; row 3: colours
        ubyte i
        put(1, 3, iso:"Text", 0, vid.C_LGRAY)
        put(41, 3, iso:"Back", 0, vid.C_LGRAY)
        for i in 0 to 15 {
            swatch(6 + i * 2, i, B_TXT0 + i, doc.tfg == i)
            swatch(46 + i * 2, i, B_HIL0 + i, doc.tbg == i)
        }
        draw_ruler()
    }

    sub swatch(ubyte col, ubyte color, ubyte id, bool cur) {
        ubyte k = (color << 4) | color
        vid.r_ch[0] = 32
        vid.r_ch[1] = 32
        vid.r_sty[0] = 0
        vid.r_sty[1] = 0
        vid.r_col[0] = k
        vid.r_col[1] = k
        if cur {
            ; mark the current colour with a small box in contrasting colour
            ubyte contrast = vid.C_BLACK
            if color == 0 or color == 6 or color == 2 or color == 11 or color == 9
                contrast = vid.C_WHITE
            vid.r_ch[0] = iso:'x'
            vid.r_col[0] = (color << 4) | contrast
        }
        vid.render_run(3, col, 2)
        add_btn(col, 3, 2, id)
    }

    sub draw_ruler() {
        ubyte c
        vid.fill(0, 4, 80, 0, vid.C_LGRAY)
        for c in 0 to 63 {
            vid.r_ch[c] = iso:'.'
            if c % 8 == 0
                vid.r_ch[c] = iso:'0' + c / 8
            else if c % 4 == 0
                vid.r_ch[c] = iso:'+'
            vid.r_sty[c] = 0
            vid.r_col[c] = (vid.C_WHITE << 4) | vid.C_DGRAY
        }
        vid.render_run(4, PAGE_X, 64)
    }

    sub page_cur() -> ubyte {
        return doc.page_of(doc.curline)
    }

    ; ---------------- status bar ----------------
    sub set_status(str s) {
        ubyte i = 0
        while s[i] != 0 and i < 49 {
            status_msg[i] = s[i]
            i++
        }
        while i < 50 {
            status_msg[i] = 32
            i++
        }
        status_msg[50] = 0
    }

    sub draw_status() {
        vid.fill(0, STATUS_ROW, 80, 0, vid.C_LGRAY)
        put(1, STATUS_ROW, status_msg, 0, vid.C_LGRAY)
        put(56, STATUS_ROW, iso:"Ln", vid.C_DGRAY, vid.C_LGRAY)
        num(59, STATUS_ROW, (doc.curline - doc.pfirst[page_cur()]) + 1, 0, vid.C_LGRAY)
        put(65, STATUS_ROW, iso:"Col", vid.C_DGRAY, vid.C_LGRAY)
        num(69, STATUS_ROW, doc.curcol + 1, 0, vid.C_LGRAY)
    }

    ; ---------------- page view ----------------
    sub paper_row() {
        ubyte c
        ubyte desk = (vid.C_GRAY << 4) | vid.C_GRAY
        for c in 0 to 79 {
            vid.r_ch[c] = 32
            vid.r_sty[c] = 0
            vid.r_col[c] = desk
        }
        for c in PAGE_X to PAGE_X + 63
            vid.r_col[c] = (vid.C_WHITE << 4) | vid.C_BLACK
        vid.r_col[PAGE_X - 1] = 0
        vid.r_col[PAGE_X + 64] = 0
        vid.r_col[PAGE_X + 65] = (vid.C_DGRAY << 4) | vid.C_DGRAY
    }

    sub compose(uword l) {
        doc.ld(l, doc.LBV)
        uword b = doc.LBV
        ubyte ln = b[doc.O_LEN]
        ubyte ind = b[doc.O_IND]
        ubyte list = b[doc.O_LIST]
        ubyte flg = b[doc.O_FLG]
        paper_row()
        ubyte base = PAGE_X + doc.origin_buf()
        ubyte i
        ubyte c
        if ln != 0 {
            for i in 0 to ln - 1 {
                c = base + i
                if c < PAGE_X + 64 {
                    vid.r_ch[c] = b[doc.O_CH + i]
                    vid.r_sty[c] = b[doc.O_STY + i]
                    vid.r_col[c] = b[doc.O_COL + i]
                }
            }
        }
        if list != 0 and (flg & doc.F_SOFT) == 0 {
            c = PAGE_X + ind * 4
            if list == 1 {
                vid.r_sty[c] = vid.S_RAW | $20
                if ind == 0
                    vid.r_ch[c] = 81
                else if ind == 1
                    vid.r_ch[c] = 87
                else
                    vid.r_ch[c] = 90
            } else {
                ubyte n = doc.list_number(l)
                if n >= 10 {
                    vid.r_ch[c] = iso:'0' + n / 10
                    c++
                }
                vid.r_ch[c] = iso:'0' + n % 10
                vid.r_ch[c + 1] = iso:'.'
            }
        }
        if doc.sel_active {
            doc.sel_norm()
            if l >= doc.sn_l1 and l <= doc.sn_l2 {
                ubyte a = 0
                ubyte e = ln
                if l == doc.sn_l1
                    a = doc.sn_c1
                if l == doc.sn_l2
                    e = doc.sn_c2
                else
                    e = ln + 1
                i = a
                while i < e {
                    c = base + i
                    if c < PAGE_X + 64
                        vid.r_col[c] = (vid.C_BLUE << 4) | vid.C_WHITE
                    i++
                }
            }
        }
        if cursor_on and l == doc.curline {
            c = base + doc.curcol
            if c < PAGE_X + 66 {
                ubyte k = vid.r_col[c]
                vid.r_col[c] = (k << 4) | (k >> 4)
            }
        }
    }

    sub scroll_cell(ubyte sr) {
        ; scroll bar in column 79
        ubyte total = lsb(doc.npages)
        ubyte thumb = 1
        uword span = doc.npages * 55
        if span > VIEWROWS {
            thumb = 1 + lsb(((vtop / 4) * 21) / ((span - VIEWROWS) / 4 + 1))
            if thumb > 22
                thumb = 22
        }
        vid.r_sty[79] = 0
        vid.r_ch[79] = 32
        vid.r_col[79] = (vid.C_LGRAY << 4) | vid.C_BLACK
        if sr == 0 {
            vid.r_ch[79] = iso:'^'
            vid.r_col[79] = (vid.C_WHITE << 4) | vid.C_BLACK
        } else if sr == VIEWROWS - 1 {
            vid.r_ch[79] = iso:'v'
            vid.r_col[79] = (vid.C_WHITE << 4) | vid.C_BLACK
        } else if sr == thumb {
            vid.r_col[79] = (vid.C_DGRAY << 4) | vid.C_DGRAY
        }
    }

    sub draw_vrow(ubyte sr) {
        ubyte kind = doc.vrow_info(vtop + sr)
        uword ln = cx16.r0
        paper_row()
        if kind == 0 {
            compose(ln)
        } else if kind == 1 {
            ; blank paper, already prepared
        } else if kind == 2 {
            ubyte c
            ubyte desk = (vid.C_GRAY << 4) | vid.C_GRAY
            for c in 0 to 79
                vid.r_col[c] = desk
            ; page top edge: dark line with a label
            for c in PAGE_X - 1 to PAGE_X + 64
                vid.r_col[c] = (vid.C_BLACK << 4) | vid.C_BLACK
            vid.r_col[PAGE_X + 65] = (vid.C_DGRAY << 4) | vid.C_DGRAY
            ubyte pg = lsb(ln) + 1
            vid.r_ch[PAGE_X + 27] = iso:'P'
            vid.r_ch[PAGE_X + 28] = iso:'a'
            vid.r_ch[PAGE_X + 29] = iso:'g'
            vid.r_ch[PAGE_X + 30] = iso:'e'
            vid.r_ch[PAGE_X + 32] = iso:'0' + pg / 10
            if pg < 10
                vid.r_ch[PAGE_X + 32] = iso:' '
            vid.r_ch[PAGE_X + 33] = iso:'0' + pg % 10
            for c in PAGE_X + 27 to PAGE_X + 33
                vid.r_col[c] = (vid.C_BLACK << 4) | vid.C_YELLOW
        } else {
            ubyte c2
            for c2 in 0 to 79
                vid.r_col[c2] = (vid.C_GRAY << 4) | vid.C_GRAY
        }
        scroll_cell(sr)
        vid.render_run(ROW0 + sr, 0, 80)
    }

    sub redraw_all() {
        ubyte sr
        for sr in 0 to VIEWROWS - 1
            draw_vrow(sr)
    }

    sub redraw_from(uword l) {
        if l >= doc.nlines
            l = doc.nlines - 1
        uword vr = doc.vrow_of(l)
        ubyte sr = 0
        if vr > vtop + 1
            sr = lsb(vr - vtop - 1)
        while sr < VIEWROWS {
            draw_vrow(sr)
            sr++
        }
    }

    sub redraw_lines(uword l1, uword l2) {
        ubyte sr
        ubyte kind
        for sr in 0 to VIEWROWS - 1 {
            kind = doc.vrow_info(vtop + sr)
            if kind == 0 and cx16.r0 >= l1 and cx16.r0 <= l2
                draw_vrow(sr)
        }
    }

    sub max_vtop() -> uword {
        uword span = doc.npages * 55
        if span > VIEWROWS
            return span - VIEWROWS
        return 0
    }

    sub set_vtop(uword v) {
        if v > max_vtop()
            v = max_vtop()
        if v == vtop
            return
        uword old = vtop
        vtop = v
        if doc.rd_mode == 2
            return
        ubyte k
        ubyte sr
        if v > old and v - old <= 3 {
            k = lsb(v - old)
            sys.set_irqd()
            cx16.vaddr(0, 12800 + 2560 * (k as uword), 0, 1)
            cx16.vaddr(0, 12800, 1, 1)
            vid.vcopy_pages(240 - 10 * k)
            sys.clear_irqd()
            for sr in VIEWROWS - k to VIEWROWS - 1
                draw_vrow(sr)
            draw_scrollbar()
        } else if old > v and old - v <= 3 {
            k = lsb(old - v)
            sys.set_irqd()
            cx16.vaddr(1, 8703 - 2560 * (k as uword), 0, -1)
            cx16.vaddr(1, 8703, 1, -1)
            vid.vcopy_pages(240 - 10 * k)
            sys.clear_irqd()
            for sr in 0 to k - 1
                draw_vrow(sr)
            draw_scrollbar()
        } else
            doc.mark_all()
    }

    sub draw_scrollbar() {
        ubyte sr
        for sr in 0 to VIEWROWS - 1 {
            scroll_cell(sr)
            vid.r_ch[0] = vid.r_ch[79]
            vid.r_sty[0] = vid.r_sty[79]
            vid.r_col[0] = vid.r_col[79]
            vid.render_run(ROW0 + sr, 79, 1)
        }
    }

    sub ensure_visible() {
        uword vr = doc.vrow_of(doc.curline)
        if vr < vtop + 1 {
            if vr > 0
                set_vtop(vr - 1)
            else
                set_vtop(0)
            if vr > 1 {
                ; keep the page title visible when we hit the first line of a page
            }
        } else if vr >= vtop + VIEWROWS {
            set_vtop(vr - VIEWROWS + 1)
        }
    }

    ; redraw whatever the document says changed
    sub refresh() {
        if doc.need_repag
            doc.repaginate()
        if follow {
            follow = false
            ensure_visible()
        }
        if doc.rd_mode == 2 {
            redraw_all()
        } else if doc.rd_mode == 3 {
            redraw_from(doc.rd_l1)
        } else if doc.rd_mode == 1 {
            redraw_lines(doc.rd_l1, doc.rd_l2)
        }
        doc.rd_mode = 0
        draw_status()
    }

    sub redraw_everything() {
        doc.need_repag = true
        doc.rd_mode = 2
        refresh()
        draw_toolbar()
    }

    sub redraw_cursor_line() {
        redraw_lines(doc.curline, doc.curline)
    }

    ; map a screen cell to a document position; returns false if outside the text area
    ; result in cx16.r0 (line) and cx16.r1L (column)
    sub pos_at(ubyte cx, ubyte cy) -> bool {
        if cy < ROW0 or cy >= ROW0 + VIEWROWS
            return false
        ubyte kind = doc.vrow_info(vtop + (cy - ROW0))
        uword l
        if kind == 0 {
            l = cx16.r0
        } else if kind == 1 {
            l = doc.nlines - 1
        } else {
            return false
        }
        ubyte x
        if cx < PAGE_X
            x = 0
        else
            x = cx - PAGE_X
        ubyte c = doc.col_for_x(l, x)
        cx16.r0 = l
        cx16.r1L = c
        return true
    }

    ; ---------------- modal dialogs ----------------
    ubyte mouse_btn
    ubyte mouse_cx
    ubyte mouse_cy
    byte mouse_wheel

    sub poll_mouse() {
        ubyte b
        uword mx
        uword my
        byte wh
        b, mx, my, wh = cx16.mouse_pos()
        mouse_btn = b
        mouse_wheel = wh
        mouse_cx = lsb(mx >> 3)
        mouse_cy = lsb(my >> 3)
        if mx >= 640
            mouse_cx = 79
        if my >= 240
            mouse_cy = 29
    }

    sub draw_box(ubyte x, ubyte y, ubyte w, ubyte h) {
        ubyte r
        for r in y to y + h - 1
            vid.fill(x, r, w, 0, vid.C_LGRAY)
        vid.fill(x, y, w, 0, vid.C_BLACK)
        vid.fill(x, y + h - 1, w, 0, vid.C_BLACK)
    }

    ; text input dialog; returns true if OK was chosen. buf is a 0-terminated iso string buffer
    sub dialog_input(str title, uword buf, ubyte maxlen) -> bool {
        ubyte n = 0
        ubyte k
        bool prev = true
        while @(buf + n) != 0
            n++
        draw_box(16, 11, 48, 7)
        vid.fill(16, 11, 48, vid.C_WHITE, vid.C_BLUE)
        put(18, 11, title, vid.C_WHITE, vid.C_BLUE)
        put(18, 13, iso:"File name:", 0, vid.C_LGRAY)
        put(24, 17, iso:"[ OK ]", 0, vid.C_WHITE)
        put(40, 17, iso:"[ Cancel ]", 0, vid.C_WHITE)
        put(18, 15, iso:"Enter = OK    Esc = Cancel", vid.C_DGRAY, vid.C_LGRAY)
        repeat {
            ; input field
            vid.fill(29, 13, 32, 0, vid.C_WHITE)
            ubyte i
            for i in 0 to 31 {
                vid.r_ch[i] = 32
                vid.r_sty[i] = 0
                vid.r_col[i] = (vid.C_WHITE << 4)
            }
            for i in 0 to n {
                if i < 31 and i < n {
                    vid.r_ch[i] = @(buf + i)
                }
            }
            if n < 31
                vid.r_col[n] = (0 << 4) | vid.C_WHITE
            vid.render_run(13, 29, 32)
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == 13
                return true
            if k == 27 or k == 3
                return false
            if (k == 8 or k == 20) and n > 0 {
                n--
                @(buf + n) = 0
            } else if k >= 33 and k < 127 and n < maxlen {
                @(buf + n) = k
                n++
                @(buf + n) = 0
            }
            poll_mouse()
            if mouse_btn & 1 != 0 {
                if not prev {
                    if mouse_cy == 17 and mouse_cx >= 24 and mouse_cx < 30
                        return true
                    if mouse_cy == 17 and mouse_cx >= 40 and mouse_cx < 50
                        return false
                }
                prev = true
            } else
                prev = false
        }
    }

    sub dialog_yesno(str msg) -> bool {
        bool prev = true
        ubyte k
        draw_box(20, 12, 40, 5)
        vid.fill(20, 12, 40, vid.C_WHITE, vid.C_RED)
        put(22, 12, iso:"Please confirm", vid.C_WHITE, vid.C_RED)
        put(22, 14, msg, 0, vid.C_LGRAY)
        put(26, 16, iso:"[ Yes ]", 0, vid.C_WHITE)
        put(44, 16, iso:"[ No ]", 0, vid.C_WHITE)
        repeat {
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == iso:'y' or k == iso:'Y' or k == 13
                return true
            if k == iso:'n' or k == iso:'N' or k == 27 or k == 3
                return false
            poll_mouse()
            if mouse_btn & 1 != 0 {
                if not prev {
                    if mouse_cy == 16 and mouse_cx >= 26 and mouse_cx < 33
                        return true
                    if mouse_cy == 16 and mouse_cx >= 44 and mouse_cx < 50
                        return false
                }
                prev = true
            } else
                prev = false
        }
    }

    ; popup font list under the font button. returns font number or 255
    sub font_menu() -> ubyte {
        ubyte f
        bool prev = true
        draw_box(39, 3, 30, 5)
        for f in 0 to vid.NFONTS - 1 {
            vid.fill(40, 4 + f, 28, 0, vid.C_WHITE)
            vid.text(41, 4 + f, vid.font_name(f), f << 4, 0, vid.C_WHITE)
            vid.text(57, 4 + f, iso:"AaBb 123", f << 4, vid.C_BLUE, vid.C_WHITE)
        }
        repeat {
            sys.waitvsync()
            void cbm.GETIN2()
            poll_mouse()
            if mouse_btn & 1 != 0 {
                if not prev {
                    if mouse_cx >= 40 and mouse_cx < 68 and mouse_cy >= 4 and mouse_cy < 4 + vid.NFONTS
                        return mouse_cy - 4
                    return 255
                }
                prev = true
            } else
                prev = false
        }
    }
}
