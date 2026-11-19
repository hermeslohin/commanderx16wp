; view.p8 - screen layout: icon toolbars, ruler, scrolling page view with border, status bar, dialogs.

%import syslib
%import conv
%import vid
%import theme
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
    const ubyte B_TABLE = 22            ; icon 20 (glyphs 40/41, uploaded by X16WPTB.BIN)
    const ubyte B_PIC = 23              ; icon 21 (glyphs 42/43, uploaded by X16WPPI.BIN); tool tips: x16wppi.p8
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

    ; by style bits 6-7 (doc.SZ_MASK)
    str[4] size_name = [iso:"12pt", iso:"24pt", iso:"18pt", iso:"36pt"]

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
        repeat 2048 - 20 * 16
            cx16.VERA_DATA0 = 0                 ; the rest blank: the theme's glyphs until a theme file is read
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

    sub add_btn(ubyte x, ubyte y, ubyte w, ubyte id) {
        if bt_n < 64 {
            bt_x[bt_n] = x
            bt_y[bt_n] = y
            bt_w[bt_n] = w
            bt_id[bt_n] = id
            bt_n++
        }
    }

    ; icon faces from the theme: New (and Quit), Open and Save have accent faces (Sunset: pink, orange,
    ; teal), the rest the normal face; an "on" toggle has its own
    sub icon(ubyte col, ubyte row, ubyte k, ubyte id, bool active) {
        ubyte kc = theme.rl[theme.R_BTN]
        when id {
            B_NEW, B_QUIT -> kc = theme.rl[theme.R_BTN_1]
            B_OPEN -> kc = theme.rl[theme.R_BTN_2]
            B_SAVE -> kc = theme.rl[theme.R_BTN_3]
        }
        if active
            kc = theme.rl[theme.R_BTN_ON]
        vid.r_ch[0] = k * 2
        vid.r_ch[1] = k * 2 + 1
        vid.r_sty[0] = theme.S_THEME
        vid.r_sty[1] = theme.S_THEME
        vid.r_col[0] = kc
        vid.r_col[1] = kc
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
    ubyte[21] tb_id = [B_NEW, B_OPEN, B_SAVE, B_SAVEAS, B_CUT, B_COPY, B_PASTE, B_ALL, B_PGBRK, B_TABLE, B_PIC,
                       B_BOLD, B_ITAL, B_UNDER, B_AL, B_AC, B_AR, B_BUL, B_NUM, B_OUT, B_IND]
    ubyte[21] tb_col = [1, 4, 7, 10, 15, 18, 21, 24, 29, 34, 37, 1, 4, 7, 12, 15, 18, 23, 26, 31, 34]

    sub draw_toolbar() {
        vid.compose_begin()     ; drawn row by row in one pass each: no flash
        bt_n = 0
        ; title bar: the theme's fill with chips for the name, file name and page count
        theme.stripes(0, 0, 80)
        ubyte k = theme.rl[theme.R_TTL_NAME]
        vid.text(1, 0, iso:" X16 WRITE ", vid.S_BOLD, k & 15, k >> 4)
        k = theme.rl[theme.R_TTL_TXT]
        ubyte tf = k & 15
        ubyte tb = k >> 4
        ubyte x = 14
        while filename[x - 14] != 0
            x++
        vid.fill(13, 0, x - 12, 0, tb)
        put(14, 0, filename, tf, tb)
        if doc.modified
            put(x, 0, iso:" (modified) ", theme.rl[theme.R_TTL_WARN], tb)
        vid.fill(59, 0, 15, 0, tb)
        put(60, 0, iso:"Page", tf, tb)
        num(65, 0, page_cur() + 1, tf, tb)
        put(68, 0, iso:"of", tf, tb)
        num(71, 0, doc.npages, tf, tb)
        vid.fill(76, 0, 4, 0, tb)
        icon(77, 0, 19, B_QUIT, false)

        tb = theme.rl[theme.R_TOOL]
        vid.fill(0, 1, 80, 0, tb)
        vid.fill(0, 2, 80, 0, tb)
        vid.fill(0, 3, 80, 0, theme.rl[theme.R_STRIP] >> 4)
        ; rows 1 and 2: the icons (tb_id / tb_col; icon glyph pair = id - 1, Table and Picture id - 2)
        ubyte al = doc.meta(doc.curline, doc.O_AL)
        ubyte li = doc.meta(doc.curline, doc.O_LIST)
        ubyte j
        for j in 0 to 20 {
            ubyte id = tb_id[j]
            bool on = false
            if id >= B_BOLD and id <= B_UNDER
                on = (doc.tsty & (1 << (id - B_BOLD))) != 0
            else if id >= B_AL and id <= B_AR
                on = al == id - B_AL
            else if id == B_BUL or id == B_NUM
                on = li == id - (B_BUL - 1)
            ubyte g = id - 1
            if id >= B_TABLE
                g--
            ubyte r = 1
            if j >= 11
                r = 2
            icon(tb_col[j], r, g, id, on)
        }
        ; font selector
        ubyte f = (doc.tsty >> 4) & 3
        k = theme.rl[theme.R_FIELD]
        tf = k & 15
        k >>= 4
        theme.cap(38, 2, theme.G_LCAP, k, tb)
        theme.cap(61, 2, theme.G_RCAP, k, tb)
        vid.fill(39, 2, 22, 0, k)
        vid.text(40, 2, vid.font_name(f), (f << 4), tf, k)
        vid.text(60, 2, iso:"v", 0, tf, k)
        add_btn(39, 2, 22, B_FONT)
        vid.text(55, 2, size_name[doc.tsty >> 6], 0, theme.rl[theme.R_FIELD_HI], k)
        ; row 3: colours
        ubyte i
        k = theme.rl[theme.R_STRIP]
        put(1, 3, iso:"Text", k & 15, k >> 4)
        put(41, 3, iso:"Back", k & 15, k >> 4)
        for i in 0 to 15 {
            swatch(6 + i * 2, i, B_TXT0 + i, doc.tfg == i)
            swatch(46 + i * 2, i, B_HIL0 + i, doc.tbg == i)
        }
        draw_ruler()
        vid.compose_end()
    }

    ; a swatch: two cells drawn as the theme says (theme.R_SW_T0..R_SW_B1)
    sub swatch(ubyte col, ubyte color, ubyte id, bool cur) {
        ubyte r = theme.R_SW_T0
        if id >= B_HIL0
            r = theme.R_SW_B0
        swcell(0, theme.rl[r], color)
        swcell(1, theme.rl[r + 1], color)
        if cur {
            ; mark the current colour with a small box in contrasting colour
            ubyte contrast = vid.C_BLACK
            if color == 0 or color == 6 or color == 2 or color == 11 or color == 9
                contrast = vid.C_WHITE
            vid.r_ch[0] = iso:'x'
            vid.r_sty[0] = 0
            vid.r_col[0] = (color << 4) | contrast
        }
        vid.render_run(3, col, 2)
        add_btn(col, 3, 2, id)
    }

    ; code 0: a block of the colour; else that char (32 or a theme glyph) in the colour on the strip
    ; (in theme.R_SW_INK if the colour is the strip's own)
    sub swcell(ubyte i, ubyte code, ubyte color) {
        ubyte sb = theme.rl[theme.R_STRIP] & $f0
        if code == 0 {
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            vid.r_col[i] = (color << 4) | color
            return
        }
        mcell(i, code)
        if color << 4 == sb
            color = theme.rl[theme.R_SW_INK]
        vid.r_col[i] = sb | color
    }

    sub draw_ruler() {
        ubyte c
        theme.desk(0, 4, 80)
        ; yellow tape with red margin markers at both ends
        ubyte k = theme.rl[theme.R_TAPE_CAP]
        theme.cap(PAGE_X - 1, 4, theme.G_LCAP, k, theme.rl[theme.R_DESK])
        theme.cap(PAGE_X + 64, 4, theme.G_RCAP, k, theme.rl[theme.R_DESK])
        k = theme.rl[theme.R_TAPE]
        for c in 0 to 63 {
            vid.r_ch[c] = iso:'.'
            if c % 8 == 0
                vid.r_ch[c] = iso:'0' + c / 8
            else if c % 4 == 0
                vid.r_ch[c] = iso:'+'
            vid.r_sty[c] = 0
            vid.r_col[c] = k
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
        ; Compose the whole row in vid's r_ buffers and render it in one pass: blanking the row first and
        ; then drawing each piece on top made the status bar flash on every refresh.
        ; Quill (theme sprite) sits in columns 0-1
        ubyte i
        for i in 0 to 79 {
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            vid.r_col[i] = theme.rl[theme.R_STAT]
        }
        ubyte fg = theme.rl[theme.R_STAT] & 15
        ubyte lb = theme.rl[theme.R_STAT_LBL]
        st_put(3, status_msg, fg)
        st_put(56, iso:"Ln", lb)
        st_put(59, conv.str_uw((doc.curline - doc.pfirst[page_cur()]) + 1), fg)
        st_put(65, iso:"Col", lb)
        st_put(69, conv.str_uw(doc.curcol + 1), fg)
        vid.render_run(STATUS_ROW, 0, 80)
    }

    sub st_put(ubyte col, uword s, ubyte fg) {
        ubyte n = 0
        while @(s + n) != 0 and col < 80 {
            vid.r_ch[col] = @(s + n)
            vid.r_col[col] = (theme.rl[theme.R_STAT] & $f0) | fg
            col++
            n++
        }
    }

    ; ---------------- page view ----------------
    ubyte deskrow           ; virtual row (vtop + screen row) being drawn: the desk stars scroll with the page

    ; the theme's desk, its pattern by column and virtual row
    sub desk_row() {
        theme.desk_fill(0, deskrow, 80)
    }

    sub paper_row() {
        ubyte c
        desk_row()
        for c in PAGE_X - 1 to PAGE_X + 64 {
            vid.r_ch[c] = 32
            vid.r_sty[c] = 0
        }
        for c in PAGE_X to PAGE_X + 63
            vid.r_col[c] = theme.rl[theme.R_PAPER]
        c = theme.rl[theme.R_MARG]
        vid.r_col[PAGE_X - 1] = c
        vid.r_col[PAGE_X + 64] = c
        mcell(PAGE_X - 1, theme.rl[theme.R_MARG_L])
        mcell(PAGE_X + 64, theme.rl[theme.R_MARG_R])
        c = theme.rl[theme.R_SHADOW]
        vid.r_col[PAGE_X + 65] = (c << 4) | c
        vid.r_ch[PAGE_X + 65] = 32
        vid.r_sty[PAGE_X + 65] = 0
    }

    ; a theme char (32 or a glyph 240..255) into cell c
    sub mcell(ubyte c, ubyte ch) {
        vid.r_ch[c] = ch
        vid.r_sty[c] = 0
        if ch >= 240
            vid.r_sty[c] = theme.S_THEME
    }

    ; builds the cells of line l for draw_vrow. half = which screen row of the line (0 = top): a line
    ; with 18/24 pt characters is 2 rows high, with 36 pt 3; smaller characters stand on the bottom row
    sub compose(uword l, ubyte half) {
        doc.ld(l, doc.LBV)
        uword b = doc.LBV
        ubyte ln = b[doc.O_LEN]
        ubyte ind = b[doc.O_IND]
        ubyte list = b[doc.O_LIST]
        ubyte flg = b[doc.O_FLG]
        ubyte lh = doc.line_h(flg)
        ubyte tb = b[doc.O_TBL]
        paper_row()
        ubyte x = PAGE_X + doc.origin_buf()
        ubyte xend = PAGE_X + 64
        ubyte i
        ubyte c
        ubyte s
        ubyte w
        ubyte k
        ubyte ch
        ubyte a = 0
        ubyte e = 0
        ubyte e2
        bool selhere = false
        bool iscur = cursor_on and l == doc.curline
        ubyte curx = 255
        ubyte curw = 1
        if doc.sel_active {
            doc.sel_norm()
            if l >= doc.sn_l1 and l <= doc.sn_l2 {
                selhere = true
                if l == doc.sn_l1
                    a = doc.sn_c1
                if l == doc.sn_l2
                    e = doc.sn_c2
                else
                    e = ln + 1
            }
        }
        if ln != 0 {
            for i in 0 to ln - 1 {
                s = b[doc.O_STY + i]
                ch = b[doc.O_CH + i]
                k = b[doc.O_COL + i]
                w = doc.sz_w(s)
                if tb != 0 {
                    s |= vid.S_UNDER                    ; table grid
                    if tb & doc.TB_HEAD != 0 and k >> 4 == vid.C_WHITE
                        k = (k & 15) | (vid.C_LGRAY << 4)
                }
                if selhere and i >= a and i < e
                    k = theme.rl[theme.R_SEL]
                if iscur and i == doc.curcol {
                    curx = x
                    curw = w
                }
                if x + w <= xend {
                    ; the character's row on this screen row (it stands on the line's bottom row)
                    c = 255
                    if half + w >= lh
                        c = half + w - lh
                    for e2 in 0 to w - 1 {
                        vid.r_ch[x + e2] = ch
                        vid.r_sty[x + e2] = s & $3f
                        vid.r_col[x + e2] = k
                        if c == 255 {
                            vid.r_ch[x + e2] = 32
                            vid.r_sty[x + e2] = 0
                        } else if w > 1
                            vid.r_big[x + e2] = (s >> 6) << 4 | e2 << 2 | c
                    }
                }
                x += w
            }
        }
        if selhere and a <= ln and e > ln and x < xend
            vid.r_col[x] = theme.rl[theme.R_SEL]
        if iscur and doc.curcol >= ln {
            curx = x
            curw = doc.sz_w(doc.tsty)
        }
        if list != 0 and (flg & doc.F_SOFT) == 0 and half == lh - 1 {
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
        if curx != 255 {
            for c in curx to curx + curw - 1 {
                if c < PAGE_X + 66 {
                    k = vid.r_col[c]
                    vid.r_col[c] = (k << 4) | (k >> 4)
                }
            }
        }
    }

    sub scroll_cell(ubyte sr) {
        ; scroll bar in column 79
        ubyte thumb = 1
        uword span = max_vtop()
        if span != 0 {
            thumb = 1 + lsb(((vtop / 4) * 21) / (span / 4 + 1))
            if thumb > 22
                thumb = 22
        }
        vid.r_sty[79] = 0
        vid.r_ch[79] = 32
        vid.r_col[79] = theme.rl[theme.R_SCROLL]
        if sr == 0 {
            vid.r_ch[79] = iso:'^'
        } else if sr == VIEWROWS - 1 {
            vid.r_ch[79] = iso:'v'
        } else if sr == thumb {
            vid.r_col[79] = theme.rl[theme.R_THUMB] * $11
        }
    }

    sub draw_vrow(ubyte sr) {
        ubyte kind = doc.vrow_info(vtop + sr)
        uword ln = cx16.r0
        ubyte sb = cx16.r1L
        deskrow = lsb(vtop) + sr
        paper_row()
        if kind == 0 {
            compose(ln, sb)
        } else if kind == 1 {
            ; blank paper, already prepared
        } else if kind == 2 {
            ubyte c
            ; page top edge: the theme's char (where col & mask == 0) with a label chip
            ubyte m = theme.rl[theme.R_PTOP_MASK]
            for c in PAGE_X - 1 to PAGE_X + 64 {
                mcell(c, 32)
                if c & m == 0
                    mcell(c, theme.rl[theme.R_PTOP_CH])
                vid.r_col[c] = theme.rl[theme.R_PTOP]
            }
            for c in PAGE_X + 26 to PAGE_X + 34 {
                vid.r_ch[c] = 32
                vid.r_sty[c] = 0
            }
            ubyte pg = lsb(ln) + 1
            vid.r_ch[PAGE_X + 27] = iso:'P'
            vid.r_ch[PAGE_X + 28] = iso:'a'
            vid.r_ch[PAGE_X + 29] = iso:'g'
            vid.r_ch[PAGE_X + 30] = iso:'e'
            vid.r_ch[PAGE_X + 32] = iso:'0' + pg / 10
            if pg < 10
                vid.r_ch[PAGE_X + 32] = iso:' '
            vid.r_ch[PAGE_X + 33] = iso:'0' + pg % 10
            for c in PAGE_X + 26 to PAGE_X + 34
                vid.r_col[c] = theme.rl[theme.R_PTOP_LBL]
        } else {
            desk_row()
        }
        scroll_cell(sr)
        vid.render_run(ROW0 + sr, 0, 80)
        if pix.ready
            pix.pi_draw(sr, kind)           ; every row (256-colour pictures); compose() left the line in doc.LBV
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
        uword span = (doc.npages as uword) * 55
        if span > VIEWROWS
            return span - VIEWROWS
        return 0
    }

    sub set_vtop(uword v) {
        if v >= $f000           ; scrolled up past the top (vtop - 3 wrapped)
            v = 0
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
        uword vrb = vr + doc.line_h(doc.meta(doc.curline, doc.O_FLG)) - 1
        if vr < vtop + 1 {
            if vr > 0
                set_vtop(vr - 1)
            else
                set_vtop(0)
            if vr > 1 {
                ; keep the page title visible when we hit the first line of a page
            }
        } else if vrb >= vtop + VIEWROWS {
            set_vtop(vrb - VIEWROWS + 1)
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
        cx16.VERA_DC_VIDEO &= %11011111     ; pictures' layer 1 off (X16WPHC.BIN turns it on again)
        ubyte r
        for r in y to y + h - 1
            vid.fill(x, r, w, 0, vid.C_LGRAY)
        vid.fill(x, y, w, 0, vid.C_BLACK)
        vid.fill(x, y + h - 1, w, 0, vid.C_BLACK)
    }

    ; Sunset dialog button: a yellow pill, slen(label) + 2 cells wide
    sub button(ubyte x, ubyte y, str label) {
        theme.pill(x, y, label, vid.C_BLACK, vid.C_YELLOW, vid.C_LGRAY)
    }

    ; text input dialog; returns true if OK was chosen. buf is a 0-terminated iso string buffer
    sub dialog_input(str title, uword buf, ubyte maxlen) -> bool {
        ubyte n = 0
        ubyte k
        bool prev = true
        while @(buf + n) != 0
            n++
        draw_box(16, 11, 48, 8)            ; buttons on row 17, black edge below
        vid.fill(16, 11, 48, 0, vid.C_PURPLE)
        vid.text(18, 11, title, vid.S_BOLD, vid.C_BLACK, vid.C_PURPLE)
        put(18, 13, iso:"File name:", 0, vid.C_LGRAY)
        button(24, 17, iso:" OK ")
        button(40, 17, iso:" Cancel ")
        put(18, 15, iso:"Enter = OK    Esc = Cancel", vid.C_DGRAY, vid.C_LGRAY)
        bool dirty = true
        repeat {
            ; input field: redraw only when the text changed (redrawing every frame flickers)
            if dirty {
                dirty = false
                ubyte i
                for i in 0 to 31 {
                    vid.r_ch[i] = 32
                    vid.r_sty[i] = 0
                    vid.r_col[i] = (vid.C_WHITE << 4)
                }
                for i in 0 to 30 {
                    if i >= n
                        break
                    vid.r_ch[i] = @(buf + i)
                }
                if n < 31
                    vid.r_col[n] = (0 << 4) | vid.C_WHITE
                vid.render_run(13, 29, 32)
            }
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == 13
                return true
            if k == 27 or k == 3
                return false
            if (k == 8 or k == 20) and n > 0 {
                n--
                @(buf + n) = 0
                dirty = true
            } else if k >= 32 and k < 127 and n < maxlen {
                @(buf + n) = k
                n++
                @(buf + n) = 0
                dirty = true
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
        draw_box(20, 12, 40, 6)            ; buttons on row 16, black edge below
        vid.fill(20, 12, 40, 0, vid.C_RED)
        vid.text(22, 12, iso:"Please confirm", vid.S_BOLD, vid.C_WHITE, vid.C_RED)
        put(22, 14, msg, 0, vid.C_LGRAY)
        button(26, 16, iso:" Yes ")
        button(44, 16, iso:" No ")
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

    ; popup under the font button: the fonts, then the sizes. returns 0-2 (font), 3-6 (12, 18, 24, 36 pt:
    ; doc.SZ_CODE[n - 3]) or 255
    sub font_menu() -> ubyte {
        ubyte f
        bool prev = true
        draw_box(39, 3, 30, 9)
        for f in 7 to 10
            vid.fill(40, f, 28, 0, vid.C_WHITE)
        vid.text(41, 7, iso:"12 pt normal", 0, 0, vid.C_WHITE)
        vid.text(41, 8, iso:"18 pt", 0, 0, vid.C_WHITE)
        vid.text(41, 9, iso:"24 pt large", 0, 0, vid.C_WHITE)
        vid.text(41, 10, iso:"36 pt headline", 0, 0, vid.C_WHITE)
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
                    if mouse_cx >= 40 and mouse_cx < 68 and mouse_cy >= 4 and mouse_cy < 11
                        return mouse_cy - 4
                    return 255
                }
                prev = true
            } else
                prev = false
        }
    }
}
