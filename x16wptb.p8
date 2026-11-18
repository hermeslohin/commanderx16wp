; x16wptb.p8 - tables for X16 Write as a bank library: X16WPTB.BIN, RAM bank 57 at $A000.
; Loaded at start by tblx.p8. It calls X16 Write's main-RAM routines through wpsyms.p8 (generated
; from the WP build by tools/gen_wpsyms.py for bank 57): JSRFAR maps this bank back before returning.
; Never hand a string that lives in this bank to a main routine that switches RAM banks (rtf.put_s):
; RTF text is written character by character with rtf.put_c.
;
; A table row is one document line: O_TBL = columns (1..8) | TB_HEAD on the first row of a table.
; With n columns every cell is cw = 63 / n cells wide: a border glyph at 0, cw, 2cw .. n*cw and
; cw - 1 characters of text between them (padded with spaces). Up to 8 columns and 20 rows.

%address  $A000
%memtop   $C000
%output   library

%import syslib
%import wpsyms

main {
    %jmptable (
        tb.setup,       ; $A003  r0 = &vid.text as the WP sees it -> A true if this library matches
        tb.key_entry,   ; $A006  r0L = key -> A true if handled (or refused) here
        tb.menu,        ; $A009  the Table button
        tb.delsel,      ; $A00C  -> A true if the selection touched a table (and was deleted here)
        tb.paste,       ; $A00F  -> A true if pasted into a cell here
        tb.export_row,  ; $A012  doc.LB holds a table row: write it as RTF
        tb.rtf_word,    ; $A015  RTF import: control word in rtf.wname
    )

    sub start() {
    }
}

tb {
    const ubyte O_CH = 0
    const ubyte O_STY = 80
    const ubyte O_COL = 160
    const ubyte O_LEN = 240
    const ubyte O_FLG = 241
    const ubyte O_TBL = 245
    const ubyte TB_HEAD = 16
    const ubyte F_SOFT = 1
    const ubyte SEP_CH = 93             ; PETSCII vertical line in font slot 2 (upper case / graphics)
    const ubyte SEP_STY = $28           ; raw glyph, font 2
    const ubyte PAPER = $10             ; black on white (cream)
    const ubyte MAXC = 8
    const ubyte MAXR = 20

    const ubyte C_BLACK = 0
    const ubyte C_WHITE = 1
    const ubyte C_RED = 2
    const ubyte C_PURPLE = 4
    const ubyte C_YELLOW = 7
    const ubyte C_LGRAY = 15

    ubyte n                             ; columns of the current table
    ubyte cw                            ; cell width (with its left border)
    uword lb                            ; doc.LB

    ; Table icon (icon 20 = glyphs 40/41 of font slot 3): a little grid with a header row
    ubyte[16] icon = [$7f,$7f,$42,$7f,$42,$7f,$42,$7f, $fe,$fe,$12,$fe,$12,$fe,$12,$fe]

    sub setup() -> bool {
        if cx16.r0 != wp.CHECK
            return false
        ubyte i
        sys.set_irqd()
        cx16.vaddr(1, $7800 + 40 * 8, 0, 1)            ; font slot 3 = VRAM $17800
        for i in 0 to 15
            cx16.VERA_DATA0 = icon[i]
        sys.clear_irqd()
        return true
    }

    sub geom(ubyte t) {
        n = t & 15
        if n == 0
            n = 1
        cw = 63 / n
    }

    ; O_TBL of line l (0 = not a table row, or beyond the end)
    sub row(uword l) -> ubyte {
        if l >= wp.nlines
            return 0
        return wp.meta(l, O_TBL)
    }

    ; first / last row of the table that contains row l
    sub first_row(uword l) -> uword {
        while l > 0 and row(l) & TB_HEAD == 0 and row(l - 1) != 0
            l--
        return l
    }

    sub last_row(uword l) -> uword {
        ubyte t
        repeat {
            t = row(l + 1)
            if t == 0 or t & TB_HEAD != 0
                return l
            l++
        }
    }

    sub status(uword s) {
        wp.set_status(s)
        wp.draw_status()
    }

    sub changed(uword l) {
        wp.need_repag = true
        wp.mark_from(l)
        wp.modified = true
    }

    ; an empty table row with t = O_TBL in doc.LB
    sub make_row(ubyte t) {
        lb = wp.LB
        geom(t)
        sys.memset(lb, 256, 0)
        ubyte ln = n * cw + 1
        ubyte i
        for i in 0 to ln - 1 {
            @(lb + O_CH + i) = 32
            @(lb + O_STY + i) = 0
            @(lb + O_COL + i) = PAPER
            if i % cw == 0 {
                @(lb + O_CH + i) = SEP_CH
                @(lb + O_STY + i) = SEP_STY
            }
        }
        @(lb + O_LEN) = ln
        @(lb + O_TBL) = t
    }

    ; insert an empty row at line l (the row of a table with t's columns); false if the document is full
    sub insert_row(uword l, ubyte t) -> bool {
        if not wp.insert_blank(l) {
            wp.full_error = true
            return false
        }
        make_row(t)
        wp.st(l, wp.LB)
        return true
    }

    ; copy cell character src to dst inside doc.LB
    sub mv(ubyte dst, ubyte src) {
        @(lb + O_CH + dst) = @(lb + O_CH + src)
        @(lb + O_STY + dst) = @(lb + O_STY + src)
        @(lb + O_COL + dst) = @(lb + O_COL + src)
    }

    sub blank(ubyte i) {
        @(lb + O_CH + i) = 32
        @(lb + O_STY + i) = 0
        @(lb + O_COL + i) = PAPER
    }

    ; ---------------- typing ----------------
    ubyte ca                ; current cell: first text column
    ubyte ce                ; its right border column
    ubyte cell              ; its number

    ; load the cursor's row into doc.LB and put the cursor inside a cell
    sub enter_cell(ubyte t) {
        lb = wp.LB
        geom(t)
        wp.ld(wp.curline, lb)
        ubyte c = wp.curcol
        ubyte last = n * cw
        ; a cursor on a border is at the end of the cell to its left (on the left border: the first cell)
        if c > last
            c = last
        if c == 0
            c = 1
        cell = (c - 1) / cw
        ca = cell * cw + 1
        ce = ca + cw - 1
        wp.curcol = c
    }

    ; insert one character at the cursor; false if the cell is full
    sub put_char(ubyte ch, ubyte sty, ubyte col) -> bool {
        ubyte c = wp.curcol
        if c >= ce or @(lb + O_CH + ce - 1) != 32
            return false
        ubyte i = ce - 1
        while i > c {
            mv(i, i - 1)
            i--
        }
        if ch < 32
            ch = 32
        @(lb + O_CH + c) = ch
        @(lb + O_STY + c) = sty & $37           ; no 24 pt, no raw glyph
        @(lb + O_COL + c) = col
        wp.curcol = c + 1
        return true
    }

    sub store() {
        wp.st(wp.curline, lb)
        wp.mark_range(wp.curline, wp.curline)
        wp.modified = true
    }

    sub key_entry() -> bool {
        return key(cx16.r0L)
    }

    sub key(ubyte k) -> bool {
        bool del = k == 8 or k == 20 or k == 127 or k == 25
        if not (del or k == 13 or k == 9 or (k >= 32 and k < 127) or k >= 161)
            return false
        if wp.sel_active {
            if not touches()
                return false
            remove_sel()
            if del
                return true
        }
        uword cur = wp.curline
        ubyte t = row(cur)
        if t == 0
            return guard(k, cur)
        enter_cell(t)
        ubyte c = wp.curcol
        ubyte i
        when k {
            13 -> {
                ; Enter: the same cell one row down, or out of the table below its last row
                if row(cur + 1) != 0 and row(cur + 1) & TB_HEAD == 0 {
                    wp.curline = cur + 1
                    wp.curcol = ca
                } else {
                    if row(cur + 1) != 0 or cur + 1 >= wp.nlines {
                        if not wp.insert_blank(cur + 1) {
                            wp.full_error = true
                            return true
                        }
                        changed(cur)
                    }
                    wp.curline = cur + 1
                    wp.curcol = 0
                }
            }
            9 -> {
                ; Tab: next cell; after the last cell of the last row a new row (up to 20)
                if cell + 1 < n {
                    wp.curcol = ca + cw
                } else if row(cur + 1) != 0 and row(cur + 1) & TB_HEAD == 0 {
                    wp.curline = cur + 1
                    wp.curcol = 1
                } else if cur - first_row(cur) + 1 >= MAXR {
                    status(iso:"A table has at most 20 rows")
                } else if insert_row(cur + 1, t & 15) {
                    changed(cur)
                    wp.curline = cur + 1
                    wp.curcol = 1
                }
            }
            8, 20 -> {
                if c > ca {
                    i = c - 1
                    while i < ce - 1 {
                        mv(i, i + 1)
                        i++
                    }
                    blank(ce - 1)
                    wp.curcol = c - 1
                    store()
                }
            }
            127, 25 -> {
                if c < ce {
                    i = c
                    while i < ce - 1 {
                        mv(i, i + 1)
                        i++
                    }
                    blank(ce - 1)
                    store()
                }
            }
            else -> {
                if put_char(k, wp.tsty, (wp.tbg << 4) | wp.tfg)
                    store()
                else
                    status(iso:"This cell is full")
            }
        }
        return true
    }

    ; keys on a normal line that would merge it into a table row: refused (an empty line is removed)
    sub guard(ubyte k, uword cur) -> bool {
        ubyte ln = wp.meta(cur, O_LEN)
        if (k == 8 or k == 20) and wp.curcol == 0 and cur > 0 and row(cur - 1) != 0 {
            if wp.meta(cur, O_FLG) & F_SOFT != 0
                return false
            if ln == 0 and cur + 1 < wp.nlines {
                wp.delete_line(cur)
                changed(cur - 1)
                wp.curline = cur - 1
                wp.curcol = 1
            }
            return true
        }
        if (k == 127 or k == 25) and row(cur + 1) != 0 and wp.curcol >= ln and wp.para_last(cur) == cur {
            if ln == 0 {
                wp.delete_line(cur)
                changed(cur)
                wp.curcol = 1
            }
            return true
        }
        return false
    }

    ; ---------------- selections ----------------
    sub touches() -> bool {
        wp.sel_norm()
        uword l
        for l in wp.sn_l1 to wp.sn_l2 {
            if row(l) != 0
                return true
        }
        return false
    }

    sub delsel() -> bool {
        if not touches()
            return false
        remove_sel()
        return true
    }

    ; delete a selection that touches tables: whole rows go, partly selected rows lose the selected
    ; characters, the text between tables is deleted normally (never merged into a table row)
    sub remove_sel() {
        wp.sel_norm()
        uword l1 = wp.sn_l1
        ubyte c1 = wp.sn_c1
        uword l2 = wp.sn_l2
        ubyte c2 = wp.sn_c2
        uword l = l2
        uword a
        ubyte t
        ubyte x
        ubyte y
        ubyte i
        ubyte ln
        repeat {
            t = row(l)
            ln = wp.meta(l, O_LEN)
            x = 0
            if l == l1
                x = c1
            y = ln
            if l == l2
                y = c2
            if t != 0 {
                if x <= 1 and y >= ln - 1 and y > x {
                    wp.delete_line(l)
                    if t & TB_HEAD != 0 and row(l) != 0 and row(l) & TB_HEAD == 0
                        wp.setmeta(l, O_TBL, row(l) | TB_HEAD)
                } else if y > x {
                    lb = wp.LB
                    geom(t)
                    wp.ld(l, lb)
                    i = x
                    while i < y {
                        if i % cw != 0
                            blank(i)
                        i++
                    }
                    wp.st(l, lb)
                }
                if l == l1
                    break
                l--
            } else {
                a = l
                while a > l1 and row(a - 1) == 0
                    a--
                wp.sel_l = a
                wp.sel_c = 0
                if a == l1
                    wp.sel_c = c1
                wp.curline = l
                wp.curcol = y
                wp.sel_active = true
                wp.delsel_plain()
                if a == l1
                    break
                l = a - 1
            }
        }
        if wp.nlines == 0
            void wp.insert_blank(0)
        if l1 >= wp.nlines
            l1 = wp.nlines - 1
        wp.curline = l1
        ln = wp.meta(l1, O_LEN)
        if c1 > ln
            c1 = ln
        wp.curcol = c1
        wp.sel_active = false
        wp.need_repag = true
        wp.rd_mode = 2
        wp.modified = true
    }

    sub paste() -> bool {
        if wp.sel_active {
            if not touches()
                return false
            remove_sel()
        }
        ubyte t = row(wp.curline)
        if t == 0
            return wp.clip_n == 0
        enter_cell(t)
        uword k = 0
        while k < wp.clip_n {
            wp.clip_get(k)
            if wp.cg_ch == 13 or not put_char(wp.cg_ch, wp.cg_sty, wp.cg_col)
                break
            k++
        }
        store()
        if k < wp.clip_n
            status(iso:"Pasted what fits in the cell")
        return true
    }

    ; ---------------- the Table button ----------------
    ubyte[4] bx = [22, 33, 47, 63]
    ubyte[4] bw = [9, 12, 14, 8]

    sub button(ubyte x, ubyte y, uword label) {
        ubyte[2] cap
        cap[1] = 0
        cap[0] = 243
        wp.vid_text(x, y, &cap, $38, C_YELLOW, C_LGRAY)
        wp.vid_text(x + 1, y, label, 0, C_BLACK, C_YELLOW)
        ubyte w = 0
        while @(label + w) != 0
            w++
        cap[0] = 244
        wp.vid_text(x + 1 + w, y, &cap, $38, C_YELLOW, C_LGRAY)
    }

    sub menu() {
        uword cur = wp.curline
        ubyte t = row(cur)
        if t == 0 {
            insert_table()
            wp.redraw_everything()
            return
        }
        geom(t)
        uword first = first_row(cur)
        uword last = last_row(cur)
        wp.draw_box(20, 11, 52, 6)
        wp.vid_fill(20, 11, 52, C_BLACK, C_PURPLE)
        wp.vid_text(22, 11, iso:"Table", 1, C_BLACK, C_PURPLE)
        wp.put(22, 13, iso:"Rows:", C_BLACK, C_LGRAY)
        wp.num(28, 13, last - first + 1, C_BLACK, C_LGRAY)
        wp.put(32, 13, iso:"Columns:", C_BLACK, C_LGRAY)
        wp.num(41, 13, n, C_BLACK, C_LGRAY)
        button(bx[0], 15, iso:"Add row")
        button(bx[1], 15, iso:"Delete row")
        button(bx[2], 15, iso:"Delete table")
        button(bx[3], 15, iso:"Cancel")
        ubyte choice = 255
        bool prev = true
        ubyte k
        ubyte i
        while choice == 255 {
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == iso:'a' or k == iso:'A'
                choice = 0
            else if k == iso:'d' or k == iso:'D'
                choice = 1
            else if k == iso:'t' or k == iso:'T'
                choice = 2
            else if k == 27 or k == 3
                choice = 3
            wp.poll_mouse()
            if wp.mouse_btn & 1 != 0 {
                if not prev and wp.mouse_cy == 15 {
                    for i in 0 to 3 {
                        if wp.mouse_cx >= bx[i] and wp.mouse_cx < bx[i] + bw[i]
                            choice = i
                    }
                }
                prev = true
            } else
                prev = false
        }
        when choice {
            0 -> {
                if last - first + 1 >= MAXR
                    wp.set_status(iso:"A table has at most 20 rows")
                else if insert_row(cur + 1, t & 15) {
                    changed(cur)
                    wp.curline = cur + 1
                    wp.curcol = 1
                }
            }
            1 -> {
                if first == last
                    delete_table(first, last)
                else {
                    wp.delete_line(cur)
                    if t & TB_HEAD != 0
                        wp.setmeta(cur, O_TBL, row(cur) | TB_HEAD)
                    if cur > last - 1
                        wp.curline = cur - 1
                    wp.curcol = 1
                    changed(first)
                }
            }
            2 -> delete_table(first, last)
        }
        wp.rd_mode = 2
        wp.redraw_everything()
    }

    sub delete_table(uword first, uword last) {
        uword l
        for l in first to last
            wp.delete_line(first)
        if wp.nlines == 0
            void wp.insert_blank(0)
        if first >= wp.nlines
            first = wp.nlines - 1
        wp.curline = first
        wp.curcol = 0
        changed(first)
    }

    ; "CxR" (also "C R", "C*R") -> columns, rows
    ubyte ask_c
    ubyte ask_r
    sub parse(uword s) -> bool {
        ubyte i = 0
        ask_c = 0
        ask_r = 0
        while @(s + i) == 32
            i++
        while @(s + i) >= iso:'0' and @(s + i) <= iso:'9' {
            ask_c = ask_c * 10 + @(s + i) - iso:'0'
            i++
        }
        while @(s + i) != 0 and (@(s + i) < iso:'0' or @(s + i) > iso:'9')
            i++
        while @(s + i) >= iso:'0' and @(s + i) <= iso:'9' {
            ask_r = ask_r * 10 + @(s + i) - iso:'0'
            i++
        }
        return ask_c >= 1 and ask_c <= MAXC and ask_r >= 1 and ask_r <= MAXR
    }

    sub insert_table() {
        uword buf = wp.nbuf
        @(buf) = iso:'3'
        @(buf + 1) = iso:'x'
        @(buf + 2) = iso:'3'
        @(buf + 3) = 0
        if not wp.dialog_input(iso:"Insert table: columns x rows (up to 8x20)", buf, 5)
            return
        if not parse(buf) {
            wp.set_status(iso:"Tables have 1-8 columns and 1-20 rows")
            return
        }
        uword cur = wp.curline
        uword at
        if row(cur) == 0 and wp.meta(cur, O_LEN) == 0 and wp.para_last(cur) == cur {
            at = cur                                ; on an empty line: the table goes here
        } else {
            at = wp.para_last(cur) + 1              ; after the paragraph
            if row(cur) != 0
                at = last_row(cur) + 1
        }
        ubyte r
        for r in 0 to ask_r - 1 {
            ubyte t = ask_c
            if r == 0
                t |= TB_HEAD
            if not insert_row(at + r, t)
                break
        }
        ; always a normal line after the table to go on writing
        uword after = at + ask_r
        if after >= wp.nlines or row(after) != 0
            void wp.insert_blank(after)
        wp.sel_active = false
        wp.curline = at
        wp.curcol = 1
        changed(at)
        wp.rd_mode = 2
    }

    ; ---------------- RTF export ----------------
    sub pc(ubyte c) {
        wp.put_c(c)
    }

    sub ps(uword s) {
        while @(s) != 0 {
            wp.put_c(@(s))
            s++
        }
    }

    sub export_row() {
        lb = wp.LB
        ubyte t = @(lb + O_TBL)
        geom(t)
        ubyte k
        ps(iso:"\\trowd\\trgaph72\\trleft0")
        if t & TB_HEAD != 0
            ps(iso:"\\trhdr")
        for k in 0 to n - 1 {
            ps(iso:"\\clbrdrt\\brdrs\\brdrw10\\clbrdrl\\brdrs\\brdrw10\\clbrdrb\\brdrs\\brdrw10\\clbrdrr\\brdrs\\brdrw10\\cellx")
            wp.put_n(((k + 1) * cw) as uword * 144)
        }
        ps(iso:"\r\n")
        for k in 0 to n - 1 {
            ps(iso:"\\pard\\plain\\intbl\\sb0\\sa0\\sl-240\\slmult0\\ql\\fs24 ")
            runs(k * cw + 1, k * cw + cw)
            ps(iso:"\\cell\r\n")
        }
        ps(iso:"\\row\r\n")
    }

    ; the characters a..e-1 of doc.LB with their formatting (trailing spaces left out)
    sub runs(ubyte a, ubyte e) {
        while e > a and @(lb + O_CH + e - 1) == 32
            e--
        wp.put_runs(lb, a, e)
    }

    ; ---------------- RTF import ----------------
    ubyte ncell
    uword[MAXC] cend                    ; end of each cell's text in rtf's paragraph stream
    ubyte nrows                         ; rows of the table being imported

    sub is(uword w) -> bool {
        uword a = wp.wname
        ubyte i = 0
        repeat {
            if @(a + i) != @(w + i)
                return false
            if @(w + i) == 0
                return true
            i++
        }
    }

    sub rtf_word() {
        if is(iso:"trowd") or is(iso:"intbl") {
            if not wp.in_row {
                wp.flush_para()
                wp.para_open = false
                wp.pn = 0
                ncell = 0
                wp.in_row = true
            }
        } else if is(iso:"cell") {
            if wp.in_row {
                if ncell < MAXC {
                    cend[ncell] = wp.pn
                    ncell++
                } else
                    cend[MAXC - 1] = wp.pn
            }
        } else if is(iso:"row") {
            if wp.in_row {
                build_row()
                wp.in_row = false
                wp.para_open = false
                wp.pn = 0
            }
        }
    }

    sub build_row() {
        if ncell == 0 {
            cend[0] = wp.pn
            ncell = 1
        }
        uword idx = 0
        if wp.first_flush
            wp.first_flush = false
        else {
            idx = wp.nlines
            if not wp.insert_blank(idx)
                return
        }
        ubyte t = ncell
        ubyte p = 0
        if idx > 0
            p = row(idx - 1)
        if p == 0 or p & 15 != ncell or nrows >= MAXR {
            t |= TB_HEAD
            nrows = 0
        }
        nrows++
        make_row(t)
        ubyte k
        uword s
        uword e
        ubyte c
        for k in 0 to ncell - 1 {
            s = 0
            if k > 0
                s = cend[k - 1]
            e = cend[k]
            while s < e and @(wp.sbch + s) == 32
                s++
            c = k * cw + 1
            while s < e and c < k * cw + cw {
                @(lb + O_CH + c) = @(wp.sbch + s)
                if @(lb + O_CH + c) < 32
                    @(lb + O_CH + c) = 32
                @(lb + O_STY + c) = @(wp.sbsty + s) & $37
                @(lb + O_COL + c) = @(wp.sbcol + s)
                c++
                s++
            }
        }
        wp.st(idx, lb)
    }
}
