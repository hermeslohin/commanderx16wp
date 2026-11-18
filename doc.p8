; doc.p8 - document model: lines in banked RAM, paragraphs with soft word wrap, pages, editing, clipboard.

%import syslib

doc {
    %option ignore_unused

    const ubyte COLS = 64
    const ubyte PLINES = 54
    const uword MAXLINES = 864
    const ubyte MAXIND = 6
    const uword SBMAX = 640
    const ubyte CLIPBANK = 63
    const uword CLIPMAX = 2700

    ; line slot layout (256 bytes, banked RAM, 32 slots per bank)
    const ubyte O_CH = 0
    const ubyte O_STY = 80
    const ubyte O_COL = 160
    const ubyte O_LEN = 240
    const ubyte O_FLG = 241
    const ubyte O_AL = 242
    const ubyte O_IND = 243
    const ubyte O_LIST = 244
    const ubyte F_SOFT = 1
    const ubyte F_HARD = 2
    const ubyte F_TALL = 4          ; the line holds large (2x2 cell) characters: it is 2 screen rows high
    const ubyte SZ_LARGE = $40      ; style bit: character is large (24 pt, 2 cells wide)

    ; line order: slot number of every line (MAXLINES words). It lives in banked RAM (bank ORDERBANK at
    ; $A000) to leave main RAM for the program; oslot() maps that bank, slot_ptr() then maps the line's.
    const ubyte ORDERBANK = 58
    const uword order = $a000
    uword slotmap = memory("slotmap", 112, 0)
    uword LB = memory("lb", 256, 0)
    uword LBV = memory("lbv", 256, 0)
    uword sbch = memory("sbch", 640, 0)
    uword sbsty = memory("sbsty", 640, 0)
    uword sbcol = memory("sbcol", 640, 0)
    ubyte[48] stg_ch
    ubyte[48] stg_sty
    ubyte[48] stg_col

    uword nlines
    uword curline
    ubyte curcol
    bool sel_active
    uword sel_l
    ubyte sel_c
    ubyte tsty
    ubyte tfg
    ubyte tbg
    uword[64] pfirst
    ubyte npages
    bool modified
    bool full_error
    ubyte pa_al
    ubyte pa_ind
    ubyte pa_list
    ubyte pa_flags
    ubyte rd_mode           ; 0 none, 1 line range, 2 everything
    uword rd_l1
    uword rd_l2
    bool need_repag
    uword clip_n
    ubyte cg_ch
    ubyte cg_sty
    ubyte cg_col

    ; row map of one page (a large-size line takes 2 rows): which line / sub-row is on each page row
    ubyte[54] pc_row                ; (line - first line of the page) * 2 + sub-row, 255 = empty
    ubyte pc_page = 255

    ; ---------------- slots ----------------
    sub slot_ptr(uword slot) -> uword {
        cx16.rambank(lsb(slot >> 5) + 1)
        return $a000 + ((slot & 31) << 8)
    }

    sub alloc_slot() -> uword {
        ubyte b
        ubyte bit
        ubyte v
        for b in 0 to 107 {
            v = @(slotmap + b)
            if v != 255 {
                for bit in 0 to 7 {
                    if (v & (1 << bit)) == 0 {
                        @(slotmap + b) = v | (1 << bit)
                        return (b as uword) * 8 + bit
                    }
                }
            }
        }
        return $ffff
    }

    sub free_slot(uword s) {
        ubyte b = lsb(s >> 3)
        @(slotmap + b) = @(slotmap + b) & ~(1 << (lsb(s) & 7))
    }

    sub oslot(uword idx) -> uword {
        cx16.rambank(ORDERBANK)
        return peekw(order + idx * 2)
    }

    sub ld(uword idx, uword dst) {
        uword src = slot_ptr(oslot(idx))
        sys.memcopy(src, dst, 248)
    }

    sub st(uword idx, uword src) {
        uword dst = slot_ptr(oslot(idx))
        sys.memcopy(src, dst, 248)
    }

    sub meta(uword idx, ubyte off) -> ubyte {
        uword p = slot_ptr(oslot(idx))
        return @(p + off)
    }

    sub setmeta(uword idx, ubyte off, ubyte v) {
        uword p = slot_ptr(oslot(idx))
        @(p + off) = v
    }

    sub insert_blank(uword idx) -> bool {
        if nlines >= MAXLINES {
            full_error = true
            return false
        }
        uword s = alloc_slot()
        if s == $ffff {
            full_error = true
            return false
        }
        uword i = nlines
        cx16.rambank(ORDERBANK)
        while i > idx {
            pokew(order + i * 2, peekw(order + (i - 1) * 2))
            i--
        }
        pokew(order + idx * 2, s)
        nlines++
        sys.memset(LBV, 256, 0)
        uword p = slot_ptr(s)
        sys.memcopy(LBV, p, 248)
        return true
    }

    sub delete_line(uword idx) {
        ubyte ob = cx16.getrambank()
        free_slot(oslot(idx))
        uword i = idx
        while i + 1 < nlines {
            pokew(order + i * 2, peekw(order + (i + 1) * 2))
            i++
        }
        cx16.rambank(ob)
        nlines--
    }

    sub init_doc() {
        sys.memset(slotmap, 112, 0)
        nlines = 0
        void insert_blank(0)
        curline = 0
        curcol = 0
        sel_active = false
        tsty = 0
        tfg = 0
        tbg = 1
        full_error = false
        modified = false
        rd_mode = 2
        need_repag = true
        repaginate()
    }

    ; ---------------- helpers ----------------
    sub width_of(ubyte ind, ubyte list) -> ubyte {
        ubyte w = COLS - ind * 4
        if list != 0
            w -= 4
        return w
    }

    sub left_of(ubyte ind, ubyte list) -> ubyte {
        ubyte l = ind * 4
        if list != 0
            l += 4
        return l
    }

    ; screen cells taken by the first n characters of a line buffer (large characters take 2)
    sub cells_of(uword b, ubyte n) -> ubyte {
        ubyte w = n
        ubyte i
        if n == 0
            return 0
        for i in 0 to n - 1 {
            if (@(b + O_STY + i) & SZ_LARGE) != 0
                w++
        }
        return w
    }

    sub mark_range(uword l1, uword l2) {
        if rd_mode == 0 {
            rd_mode = 1
            rd_l1 = l1
            rd_l2 = l2
        } else if rd_mode == 1 {
            if l1 < rd_l1
                rd_l1 = l1
            if l2 > rd_l2
                rd_l2 = l2
        }
    }

    sub mark_all() {
        rd_mode = 2
    }

    ; redraw from line l down to the bottom of the view
    sub mark_from(uword l) {
        if rd_mode == 0 {
            rd_mode = 3
            rd_l1 = l
        } else if rd_mode == 1 {
            rd_mode = 3
            if l < rd_l1
                rd_l1 = l
        } else if rd_mode == 3 {
            if l < rd_l1
                rd_l1 = l
        }
    }

    sub repaginate() {
        uword l
        ubyte rows = 0
        ubyte p = 0
        ubyte h
        ubyte f
        pfirst[0] = 0
        for l in 0 to nlines - 1 {
            f = meta(l, O_FLG)
            h = 1
            if (f & F_TALL) != 0
                h = 2
            if l > 0 {
                if (f & F_HARD) != 0 or rows + h > PLINES {
                    if p < 63 {
                        p++
                        pfirst[p] = l
                        rows = 0
                    }
                }
            }
            rows += h
        }
        npages = p + 1
        need_repag = false
        pc_page = 255
    }

    sub page_of(uword l) -> ubyte {
        ubyte p = npages - 1
        while p > 0 and pfirst[p] > l
            p--
        return p
    }

    sub build_pagemap(ubyte p) {
        if pc_page == p
            return
        uword endl = nlines
        if p + 1 < npages and pfirst[p + 1] < endl
            endl = pfirst[p + 1]
        ubyte r = 0
        ubyte n = 0
        uword l = pfirst[p]
        while l < endl and r < PLINES {
            pc_row[r] = n << 1
            r++
            if r < PLINES and (meta(l, O_FLG) & F_TALL) != 0 {
                pc_row[r] = (n << 1) | 1
                r++
            }
            n++
            l++
        }
        while r < PLINES {
            pc_row[r] = 255
            r++
        }
        pc_page = p
    }

    ; first page row (as a virtual screen row) of line l
    sub vrow_of(uword l) -> uword {
        ubyte p = page_of(l)
        build_pagemap(p)
        ubyte n = lsb(l - pfirst[p]) << 1
        ubyte r = 0
        while r < PLINES - 1 and pc_row[r] != n
            r++
        return (p as uword) * 55 + 1 + r
    }

    ; returns 0=line (cx16.r0=line, cx16.r1L=sub-row 0/1), 1=blank paper, 2=page top separator (r0=page), 3=beyond
    sub vrow_info(uword vr) -> ubyte {
        uword p = vr / 55
        ubyte rip = lsb(vr % 55)
        if p >= npages
            return 3
        ubyte pp = lsb(p)
        if rip == 0 {
            cx16.r0 = p
            return 2
        }
        build_pagemap(pp)
        ubyte e = pc_row[rip - 1]
        if e == 255
            return 1
        cx16.r0 = pfirst[pp] + (e >> 1)
        cx16.r1L = e & 1
        return 0
    }

    sub para_first(uword l) -> uword {
        while l > 0 {
            if (meta(l, O_FLG) & F_SOFT) == 0
                break
            l--
        }
        return l
    }

    sub para_last(uword l) -> uword {
        while l + 1 < nlines {
            if (meta(l + 1, O_FLG) & F_SOFT) == 0
                break
            l++
        }
        return l
    }

    sub maxcol(uword l) -> ubyte {
        ubyte ln = meta(l, O_LEN)
        if ln > 0 and l + 1 < nlines {
            if (meta(l + 1, O_FLG) & F_SOFT) != 0
                return ln - 1
        }
        return ln
    }

    ; ---------------- paragraph stream ----------------
    sub gather(uword first, uword last) -> uword {
        uword n = 0
        uword l
        ubyte ln
        ld(first, LB)
        pa_al = LB[O_AL]
        pa_ind = LB[O_IND]
        pa_list = LB[O_LIST]
        pa_flags = LB[O_FLG] & F_HARD
        for l in first to last {
            if l != first
                ld(l, LB)
            ln = LB[O_LEN]
            if ln != 0 and n + ln <= SBMAX {
                sys.memcopy(LB + O_CH, sbch + n, ln)
                sys.memcopy(LB + O_STY, sbsty + n, ln)
                sys.memcopy(LB + O_COL, sbcol + n, ln)
                n += ln
            }
        }
        return n
    }

    sub scatter(uword first, uword oldlast, uword s0, uword cnt) -> uword {
        uword pos = s0
        uword endp = s0 + cnt
        uword cur = first
        uword avail = oldlast
        uword remaining
        ubyte take
        ubyte w = width_of(pa_ind, pa_list)
        ubyte i
        bool found
        ubyte fit
        ubyte wsum
        ubyte lim
        ubyte step
        ubyte tallb
        ubyte oldtall
        bool heightchg = false
        do {
            remaining = endp - pos
            ; fit = how many characters fit in w cells (large characters are 2 cells wide)
            lim = 80
            if remaining < 80
                lim = lsb(remaining)
            fit = 0
            wsum = 0
            while fit < lim {
                step = 1
                if (@(sbsty + pos + fit) & SZ_LARGE) != 0
                    step = 2
                if wsum + step > w
                    break
                wsum += step
                fit++
            }
            if remaining <= fit {
                take = lsb(remaining)
            } else {
                take = fit
                found = false
                i = fit
                while true {
                    if @(sbch + pos + i) == 32 {
                        found = true
                        break
                    }
                    if i == 0
                        break
                    i--
                }
                if found and i > 0
                    take = i + 1
                if take == 0
                    take = 1
            }
            sys.memset(LB, 256, 0)
            if take != 0 {
                sys.memcopy(sbch + pos, LB + O_CH, take)
                sys.memcopy(sbsty + pos, LB + O_STY, take)
                sys.memcopy(sbcol + pos, LB + O_COL, take)
            }
            LB[O_LEN] = take
            tallb = 0
            if take != 0 {
                for i in 0 to take - 1 {
                    if (@(sbsty + pos + i) & SZ_LARGE) != 0 {
                        tallb = F_TALL
                        break
                    }
                }
            }
            oldtall = 0
            if cur <= avail
                oldtall = meta(cur, O_FLG) & F_TALL
            if oldtall != tallb
                heightchg = true
            if cur == first
                LB[O_FLG] = pa_flags | tallb
            else
                LB[O_FLG] = F_SOFT | tallb
            LB[O_AL] = pa_al
            LB[O_IND] = pa_ind
            LB[O_LIST] = pa_list
            if cur > avail {
                if not insert_blank(cur)
                    break
                avail = cur
            }
            st(cur, LB)
            cur++
            pos += take
        } until pos >= endp
        while avail >= cur {
            delete_line(cur)
            avail--
        }
        if cur - 1 != oldlast or heightchg {
            need_repag = true
            mark_from(first)
        } else {
            mark_range(first, oldlast)
        }
        return cur - 1
    }

    sub offset_of(uword first, uword l, ubyte col) -> uword {
        uword off = col
        uword k = first
        while k < l {
            off += meta(k, O_LEN)
            k++
        }
        return off
    }

    sub locate(uword first, uword last, uword off) {
        uword l = first
        ubyte ln
        while true {
            ln = meta(l, O_LEN)
            if off < ln or l >= last {
                curline = l
                if off > ln
                    off = ln
                curcol = lsb(off)
                return
            }
            off -= ln
            l++
        }
    }

    sub sb_remove(uword off, uword n, uword cnt) {
        uword k = off
        while k + n < cnt {
            @(sbch + k) = @(sbch + k + n)
            @(sbsty + k) = @(sbsty + k + n)
            @(sbcol + k) = @(sbcol + k + n)
            k++
        }
    }

    ; ---------------- typing attributes ----------------
    sub sync_typing() {
        ubyte ln = meta(curline, O_LEN)
        if ln == 0
            return
        uword p = slot_ptr(oslot(curline))
        ubyte c = curcol
        if c > 0
            c--
        if c >= ln
            c = ln - 1
        tsty = @(p + O_STY + c) & $77
        tfg = @(p + O_COL + c) & 15
        tbg = @(p + O_COL + c) >> 4
    }

    ; ---------------- selection ----------------
    ; normalised selection -> (sn_l1, sn_c1, sn_l2, sn_c2)
    uword sn_l1
    ubyte sn_c1
    uword sn_l2
    ubyte sn_c2

    sub sel_norm() {
        if sel_l < curline or (sel_l == curline and sel_c <= curcol) {
            sn_l1 = sel_l
            sn_c1 = sel_c
            sn_l2 = curline
            sn_c2 = curcol
        } else {
            sn_l1 = curline
            sn_c1 = curcol
            sn_l2 = sel_l
            sn_c2 = sel_c
        }
    }

    sub clear_sel() {
        if sel_active {
            sel_norm()
            mark_range(sn_l1, sn_l2)
            sel_active = false
        }
    }

    sub select_all() {
        sel_l = 0
        sel_c = 0
        curline = nlines - 1
        curcol = meta(curline, O_LEN)
        sel_active = true
        mark_all()
    }

    ; ---------------- editing ----------------
    sub insert_run(ubyte n) {
        uword first = para_first(curline)
        uword last = para_last(curline)
        uword cnt = gather(first, last)
        if cnt + n > SBMAX {
            full_error = true
            return
        }
        uword off = offset_of(first, curline, curcol)
        uword k = cnt
        while k > off {
            k--
            @(sbch + k + n) = @(sbch + k)
            @(sbsty + k + n) = @(sbsty + k)
            @(sbcol + k + n) = @(sbcol + k)
        }
        sys.memcopy(&stg_ch, sbch + off, n)
        sys.memcopy(&stg_sty, sbsty + off, n)
        sys.memcopy(&stg_col, sbcol + off, n)
        cnt += n
        uword nl = scatter(first, last, 0, cnt)
        locate(first, nl, off + n)
        modified = true
    }

    sub insert_char(ubyte ch) {
        if sel_active
            delete_selection()
        ld(curline, LB)
        ubyte ln = LB[O_LEN]
        ubyte w = width_of(LB[O_IND], LB[O_LIST])
        ubyte cwn = 1
        if (tsty & SZ_LARGE) != 0
            cwn = 2
        if curcol <= ln and cells_of(LB, ln) + cwn <= w {
            ubyte i = ln
            while i > curcol {
                LB[O_CH + i] = LB[O_CH + i - 1]
                LB[O_STY + i] = LB[O_STY + i - 1]
                LB[O_COL + i] = LB[O_COL + i - 1]
                i--
            }
            LB[O_CH + curcol] = ch
            LB[O_STY + curcol] = tsty
            LB[O_COL + curcol] = (tbg << 4) | tfg
            LB[O_LEN] = ln + 1
            if cwn == 2 and (LB[O_FLG] & F_TALL) == 0 {
                LB[O_FLG] |= F_TALL
                need_repag = true
                mark_from(curline)
            }
            st(curline, LB)
            curcol++
            mark_range(curline, curline)
            modified = true
        } else {
            stg_ch[0] = ch
            stg_sty[0] = tsty
            stg_col[0] = (tbg << 4) | tfg
            insert_run(1)
        }
    }

    sub newline() {
        if sel_active
            delete_selection()
        uword first = para_first(curline)
        uword last = para_last(curline)
        uword cnt = gather(first, last)
        uword off = offset_of(first, curline, curcol)
        if cnt == 0 and pa_list != 0 {
            pa_list = 0
            void scatter(first, last, 0, 0)
            curline = first
            curcol = 0
            modified = true
            return
        }
        ubyte sal = pa_al
        ubyte sind = pa_ind
        ubyte slist = pa_list
        uword nl = scatter(first, last, 0, off)
        uword nw = nl + 1
        if not insert_blank(nw)
            return
        pa_al = sal
        pa_ind = sind
        pa_list = slist
        pa_flags = 0
        void scatter(nw, nw, off, cnt - off)
        curline = nw
        curcol = 0
        need_repag = true
        mark_from(first)
        modified = true
    }

    sub page_break() {
        if npages >= 60
            return
        newline()
        setmeta(curline, O_FLG, meta(curline, O_FLG) | F_HARD)
        need_repag = true
        mark_from(curline - 1)
    }

    sub delete_selection() {
        sel_norm()
        uword l1 = sn_l1
        uword l2 = sn_l2
        uword first = para_first(l1)
        uword last = para_last(l2)
        uword cnt = gather(first, last)
        uword off1 = offset_of(first, l1, sn_c1)
        uword off2 = offset_of(first, l2, sn_c2)
        if off2 > cnt
            off2 = cnt
        if off1 > off2
            off1 = off2
        sb_remove(off1, off2 - off1, cnt)
        cnt -= off2 - off1
        uword nl = scatter(first, last, 0, cnt)
        locate(first, nl, off1)
        sel_active = false
        mark_from(first)
        modified = true
    }

    sub delete_at_off(uword first, uword last, uword cnt, uword off) {
        ; remove the single stream char at off and reflow
        sb_remove(off, 1, cnt)
        uword nl = scatter(first, last, 0, cnt - 1)
        locate(first, nl, off)
        modified = true
    }

    sub backspace() {
        if sel_active {
            delete_selection()
            return
        }
        uword first
        uword last
        uword cnt
        uword off
        if curcol > 0 {
            first = para_first(curline)
            last = para_last(curline)
            cnt = gather(first, last)
            off = offset_of(first, curline, curcol)
            delete_at_off(first, last, cnt, off - 1)
            return
        }
        if curline == 0
            return
        ubyte flg = meta(curline, O_FLG)
        if (flg & F_HARD) != 0 {
            setmeta(curline, O_FLG, flg & ~F_HARD)
            need_repag = true
            mark_from(curline - 1)
            modified = true
            return
        }
        if (flg & F_SOFT) != 0 {
            ; col 0 of a wrapped line: remove the char before the break
            curline--
            curcol = meta(curline, O_LEN)
            if curcol == 0
                return
            first = para_first(curline)
            last = para_last(curline)
            cnt = gather(first, last)
            off = offset_of(first, curline, curcol)
            delete_at_off(first, last, cnt, off - 1)
            return
        }
        ; start of a paragraph: merge into the previous paragraph
        first = para_first(curline - 1)
        last = para_last(curline)
        off = offset_of(first, curline, 0)
        cnt = gather(first, last)
        uword nl = scatter(first, last, 0, cnt)
        locate(first, nl, off)
        modified = true
    }

    sub delete_fwd() {
        if sel_active {
            delete_selection()
            return
        }
        uword first = para_first(curline)
        uword last = para_last(curline)
        uword cnt = gather(first, last)
        uword off = offset_of(first, curline, curcol)
        if off < cnt {
            delete_at_off(first, last, cnt, off)
            return
        }
        if last + 1 >= nlines
            return
        last = para_last(last + 1)
        cnt = gather(first, last)
        uword nl = scatter(first, last, 0, cnt)
        locate(first, nl, off)
        modified = true
    }

    ; ---------------- character attribute changes ----------------
    ; kind: 0 toggle style bit(s), 1 font, 2 text colour, 3 highlight colour, 4 size (0 = 12 pt, 1 = 24 pt)
    sub apply_attr(ubyte kind, ubyte val) {
        if kind == 0
            tsty ^= val
        else if kind == 1
            tsty = (tsty & $cf) | (val << 4)
        else if kind == 2
            tfg = val
        else if kind == 3
            tbg = val
        else
            tsty = (tsty & ~SZ_LARGE) | (val << 6)
        if not sel_active
            return
        sel_norm()
        uword l
        ubyte a
        ubyte b
        ubyte i
        ubyte ln
        bool allset = true
        if kind == 0 {
            for l in sn_l1 to sn_l2 {
                ld(l, LB)
                ln = LB[O_LEN]
                a = 0
                b = ln
                if l == sn_l1
                    a = sn_c1
                if l == sn_l2 and sn_c2 < b
                    b = sn_c2
                i = a
                while i < b {
                    if (LB[O_STY + i] & val) == 0
                        allset = false
                    i++
                }
            }
            ; restore typing state consistent with the selection
            if allset
                tsty &= ~val
            else
                tsty |= val
        }
        for l in sn_l1 to sn_l2 {
            ld(l, LB)
            ln = LB[O_LEN]
            a = 0
            b = ln
            if l == sn_l1
                a = sn_c1
            if l == sn_l2 and sn_c2 < b
                b = sn_c2
            i = a
            while i < b {
                when kind {
                    0 -> {
                        if allset
                            LB[O_STY + i] &= ~val
                        else
                            LB[O_STY + i] |= val
                    }
                    1 -> LB[O_STY + i] = (LB[O_STY + i] & $cf) | (val << 4)
                    2 -> LB[O_COL + i] = (LB[O_COL + i] & $f0) | val
                    3 -> LB[O_COL + i] = (LB[O_COL + i] & $0f) | (val << 4)
                    else -> LB[O_STY + i] = (LB[O_STY + i] & ~SZ_LARGE) | (val << 6)
                }
                i++
            }
            st(l, LB)
            mark_range(l, l)
        }
        modified = true
        if kind == 4
            para_op(3, 0)       ; the new widths change the wrapping
    }

    ; ---------------- paragraph attribute changes ----------------
    ; kind 0 align (val 0/1/2), 1 indent delta (val 1 = in, 255 = out), 2 list (val 1 bullet, 2 number toggle), 3 re-wrap only
    sub para_op(ubyte kind, ubyte val) {
        uword l1 = curline
        uword l2 = curline
        if sel_active {
            sel_norm()
            l1 = sn_l1
            l2 = sn_l2
        }
        uword p = para_first(l1)
        uword endp = para_last(l2)
        uword cf = para_first(curline)
        uword coff = offset_of(cf, curline, curcol)
        uword last
        uword cnt
        uword nl
        bool changed = false
        while p <= endp {
            last = para_last(p)
            cnt = gather(p, last)
            if kind == 0 {
                if pa_list == 0
                    pa_al = val
            } else if kind == 1 {
                if val == 1 {
                    if pa_ind < MAXIND
                        pa_ind++
                } else if pa_ind > 0 {
                    pa_ind--
                }
            } else if kind == 2 {
                if pa_list == val
                    pa_list = 0
                else {
                    pa_list = val
                    pa_al = 0
                }
            }
            nl = scatter(p, last, 0, cnt)
            if p == cf
                locate(p, nl, coff)
            else if p < cf
                cf = cf + nl - last
            if nl != last {
                endp = endp + nl - last
                changed = true
            }
            p = nl + 1
        }
        if changed
            sel_active = false
        mark_all()
        modified = true
    }

    ; ---------------- clipboard ----------------
    sub clip_put(ubyte ch, ubyte sty, ubyte col) {
        if clip_n >= CLIPMAX
            return
        cx16.rambank(CLIPBANK)
        uword p = $a000 + clip_n * 3
        @(p) = ch
        @(p + 1) = sty
        @(p + 2) = col
        clip_n++
    }

    sub clip_get(uword k) {
        cx16.rambank(CLIPBANK)
        uword p = $a000 + k * 3
        cg_ch = @(p)
        cg_sty = @(p + 1)
        cg_col = @(p + 2)
    }

    sub copy_selection() {
        if not sel_active
            return
        sel_norm()
        clip_n = 0
        uword l
        ubyte a
        ubyte b
        ubyte i
        ubyte ln
        ubyte ch
        ubyte sty
        ubyte col
        for l in sn_l1 to sn_l2 {
            ld(l, LB)
            ln = LB[O_LEN]
            a = 0
            b = ln
            if l == sn_l1
                a = sn_c1
            if l == sn_l2 and sn_c2 < b
                b = sn_c2
            i = a
            while i < b {
                ch = LB[O_CH + i]
                sty = LB[O_STY + i]
                col = LB[O_COL + i]
                clip_put(ch, sty, col)
                i++
            }
            if l < sn_l2 {
                if l + 1 >= nlines or (meta(l + 1, O_FLG) & F_SOFT) == 0
                    clip_put(13, 0, 0)
            }
        }
    }

    sub cut_selection() {
        copy_selection()
        if sel_active
            delete_selection()
    }

    sub paste() {
        if clip_n == 0
            return
        if sel_active
            delete_selection()
        uword k = 0
        ubyte n
        while k < clip_n {
            n = 0
            while k < clip_n and n < 48 {
                clip_get(k)
                if cg_ch == 13
                    break
                stg_ch[n] = cg_ch
                stg_sty[n] = cg_sty
                stg_col[n] = cg_col
                n++
                k++
            }
            if n != 0
                insert_run(n)
            if k < clip_n {
                clip_get(k)
                if cg_ch == 13 {
                    newline()
                    k++
                }
            }
        }
        mark_all()
    }

    ; ---------------- cursor movement ----------------
    sub origin_of(uword l) -> ubyte {
        ; first text column (relative to the page) of the visible text of line l
        ld(l, LBV)
        return origin_buf()
    }

    sub origin_buf() -> ubyte {
        ubyte ind = LBV[O_IND]
        ubyte list = LBV[O_LIST]
        ubyte al = LBV[O_AL]
        ubyte left = left_of(ind, list)
        ubyte w = width_of(ind, list)
        ubyte tl = LBV[O_LEN]
        while tl > 0 and LBV[O_CH + tl - 1] == 32
            tl--
        tl = cells_of(LBV, tl)
        if al == 1 and tl < w
            return left + (w - tl) / 2
        if al == 2 and tl < w
            return left + (w - tl)
        return left
    }

    sub col_for_x(uword l, ubyte x) -> ubyte {
        ; text column (character index) of line l for page-relative cell x; large characters are 2 cells wide
        ubyte o = origin_of(l)
        ubyte m = maxcol(l)
        if x < o
            return 0
        ubyte cx = x - o
        ubyte i = 0
        ubyte cum = 0
        ubyte wd
        while i < m {
            wd = 1
            if (LBV[O_STY + i] & SZ_LARGE) != 0
                wd = 2
            if cx < cum + wd {
                if wd == 2 and cx > cum
                    i++
                return i
            }
            cum += wd
            i++
        }
        return m
    }

    sub goto_pos(uword l, ubyte c) {
        curline = l
        curcol = c
        sync_typing()
    }

    sub move_left() {
        if curcol > 0
            curcol--
        else if curline > 0 {
            curline--
            curcol = maxcol(curline)
        }
    }

    sub move_right() {
        if curcol < maxcol(curline)
            curcol++
        else if curline + 1 < nlines {
            curline++
            curcol = 0
        }
    }

    sub move_vert(byte dir, ubyte wantx) {
        if dir < 0 {
            if curline == 0
                return
            curline--
        } else {
            if curline + 1 >= nlines
                return
            curline++
        }
        curcol = col_for_x(curline, wantx)
    }

    sub cur_x() -> ubyte {
        ubyte o = origin_of(curline)
        return o + cells_of(LBV, curcol)
    }

    ; list number of the paragraph starting at line l (for numbered lists)
    sub list_number(uword l) -> ubyte {
        ubyte ind = meta(l, O_IND)
        ubyte n = 1
        uword k = l
        ubyte f
        ubyte i2
        while k > 0 {
            k--
            f = meta(k, O_FLG)
            if (f & F_SOFT) != 0
                continue
            i2 = meta(k, O_IND)
            if i2 > ind
                continue
            if i2 < ind or meta(k, O_LIST) != 2
                break
            n++
        }
        return n
    }
}
