; rtf.p8 - RTF export (every screen line is one fixed-layout paragraph so printing matches the screen)
;          and a reader for those files (and simple RTF from elsewhere).

%import syslib
%import diskio
%import conv
%import strings
%import doc
%import vid

rtf {
    %option ignore_unused

    uword obuf = memory("obuf", 512, 0)
    uword on
    bool oerr

    ubyte[16] ib
    ubyte[128] ibuf2

    sub flush_out() {
        if on != 0 {
            if not diskio.f_write(obuf, on)
                oerr = true
            on = 0
        }
    }

    sub put_c(ubyte c) {
        @(obuf + on) = c
        on++
        if on >= 500
            flush_out()
    }

    sub put_s(str s) {
        ubyte i = 0
        while s[i] != 0 {
            put_c(s[i])
            i++
        }
    }

    sub put_n(uword v) {
        uword s = conv.str_uw(v)
        ubyte i = 0
        while @(s + i) != 0 {
            put_c(@(s + i))
            i++
        }
    }

    sub put_hex(ubyte v) {
        ubyte h = v >> 4
        ubyte l = v & 15
        if h < 10
            put_c(iso:'0' + h)
        else
            put_c(iso:'a' + h - 10)
        if l < 10
            put_c(iso:'0' + l)
        else
            put_c(iso:'a' + l - 10)
    }

    sub export(str name) -> bool {
        oerr = false
        on = 0
        diskio.delete(name)
        if not diskio.f_open_w(name)
            return false
        put_s(iso:"{\\rtf1\\ansi\\ansicpg1252\\deff0\\deflang1033\r\n")
        put_s(iso:"{\\fonttbl{\\f0\\fmodern\\fcharset0 Courier New;}{\\f1\\fmodern\\fcharset0 Lucida Console;}{\\f2\\fmodern\\fcharset0 Andale Mono;}}\r\n")
        put_s(iso:"{\\colortbl;")
        ubyte i
        for i in 0 to 15 {
            put_s(iso:"\\red")
            put_n(vid.pal_hi[i] * 17)
            put_s(iso:"\\green")
            put_n((vid.pal_lo[i] >> 4) * 17)
            put_s(iso:"\\blue")
            put_n((vid.pal_lo[i] & 15) * 17)
            put_c(iso:';')
        }
        put_s(iso:"}\r\n\\paperw12240\\paperh15840\\margl1440\\margr1440\\margt1440\\margb1080\\viewkind1\r\n")
        ; X16 Write page: 64 columns x 54 lines of 12pt Courier (10 cpi, 6 lpi)
        uword l
        for l in 0 to doc.nlines - 1 {
            export_line(l)
            if oerr
                break
        }
        put_s(iso:"}\r\n")
        flush_out()
        diskio.f_close_w()
        return not oerr
    }

    sub export_line(uword l) {
        doc.ld(l, doc.LB)
        uword b = doc.LB
        ubyte ln = b[doc.O_LEN]
        ubyte flg = b[doc.O_FLG]
        ubyte al = b[doc.O_AL]
        ubyte ind = b[doc.O_IND]
        ubyte list = b[doc.O_LIST]
        ubyte left = doc.left_of(ind, list)
        bool soft = (flg & doc.F_SOFT) != 0
        while ln > 0 and b[doc.O_CH + ln - 1] == 32
            ln--
        put_s(iso:"\\pard\\plain\\sb0\\sa0\\sl-240\\slmult0\\ri140\\li")
        put_n((left as uword) * 144)
        if list != 0 and not soft
            put_s(iso:"\\fi-576")
        if al == 1
            put_s(iso:"\\qc")
        else if al == 2
            put_s(iso:"\\qr")
        else
            put_s(iso:"\\ql")
        if (flg & doc.F_HARD) != 0
            put_s(iso:"\\pagebb")
        put_s(iso:"{\\*\\xwp")
        ubyte pv = al | (list << 2) | (ind << 4)
        if soft
            pv |= 128
        put_n(pv)
        put_s(iso:"}\\fs24 ")
        if list != 0 and not soft {
            if list == 1 {
                if ind == 0
                    put_s(iso:"\\u9679?")
                else if ind == 1
                    put_s(iso:"\\u9675?")
                else
                    put_s(iso:"\\u9632?")
                put_s(iso:"   ")
            } else {
                ubyte n = doc.list_number(l)
                ubyte w = 2
                if n >= 10 {
                    put_c(iso:'0' + n / 10)
                    w = 3
                }
                put_c(iso:'0' + n % 10)
                put_c(iso:'.')
                while w < 4 {
                    put_c(iso:' ')
                    w++
                }
            }
        }
        ubyte i
        ubyte cs = 0
        ubyte cfg = 0
        ubyte cbg = 1
        ubyte s
        ubyte k
        ubyte ch
        bool any = false
        if ln != 0 {
            for i in 0 to ln - 1 {
                ch = b[doc.O_CH + i]
                s = b[doc.O_STY + i] & $37
                k = b[doc.O_COL + i]
                if ch < 32
                    ch = 32
                if s != cs or (k & 15) != cfg or (k >> 4) != cbg {
                    if (s & 1) != (cs & 1) {
                        if (s & 1) != 0
                            put_s(iso:"\\b")
                        else
                            put_s(iso:"\\b0")
                    }
                    if (s & 2) != (cs & 2) {
                        if (s & 2) != 0
                            put_s(iso:"\\i")
                        else
                            put_s(iso:"\\i0")
                    }
                    if (s & 4) != (cs & 4) {
                        if (s & 4) != 0
                            put_s(iso:"\\ul")
                        else
                            put_s(iso:"\\ulnone")
                    }
                    if (s & $30) != (cs & $30) {
                        put_s(iso:"\\f")
                        put_n((s >> 4) & 3)
                        if (s & $30) == $20
                            put_s(iso:"\\caps")
                        else
                            put_s(iso:"\\caps0")
                    }
                    if (k & 15) != cfg {
                        put_s(iso:"\\cf")
                        put_n((k & 15) + 1)
                    }
                    if (k >> 4) != cbg {
                        put_s(iso:"\\highlight")
                        if (k >> 4) == 1
                            put_c(iso:'0')
                        else
                            put_n((k >> 4) + 1)
                    }
                    put_c(iso:' ')
                    cs = s
                    cfg = k & 15
                    cbg = k >> 4
                }
                if ch == 92 or ch == iso:'{' or ch == iso:'}' {
                    put_c(92)
                    put_c(ch)
                } else if ch >= 128 {
                    put_c(92)
                    put_c(39)
                    put_hex(ch)
                } else
                    put_c(ch)
            }
        }
        put_s(iso:"\\par\r\n")
    }

    ; ======================= import =======================
    uword ilen
    uword ipos
    bool ieof
    ubyte[16] wname
    byte wparam
    bool whasparam
    uword wval              ; numeric parameter magnitude
    bool wneg

    ubyte depth
    ubyte skip_depth
    ubyte[20] gs_sty
    ubyte[20] gs_fg
    ubyte[20] gs_bg
    ubyte cur_sty
    ubyte cur_fg
    ubyte cur_bg
    ubyte line_al
    ubyte line_ind
    ubyte line_list
    bool line_soft
    bool line_hard
    bool line_started
    ubyte marker_skip
    ubyte uc_skip
    bool para_open
    uword pn
    bool first_flush
    ubyte para_hard
    ubyte pa_al_i
    ubyte pa_ind_i
    ubyte pa_list_i
    bool got_x16
    uword ibufp = memory("ibufp", 256, 0)

    sub next_byte() -> ubyte {
        if ipos >= ilen {
            if ieof
                return 0
            ilen = diskio.f_read(ibufp, 250)
            ipos = 0
            if ilen == 0 {
                ieof = true
                return 0
            }
        }
        ubyte c = @(ibufp + ipos)
        ipos++
        return c
    }

    sub peek_is_eof() -> bool {
        return ieof and ipos >= ilen
    }

    sub flush_para() {
        if not para_open
            return
        uword idx
        if first_flush {
            idx = 0
            first_flush = false
        } else {
            idx = doc.nlines
            if not doc.insert_blank(idx) {
                para_open = false
                return
            }
        }
        doc.pa_al = pa_al_i
        doc.pa_ind = pa_ind_i
        doc.pa_list = pa_list_i
        doc.pa_flags = para_hard
        void doc.scatter(idx, idx, 0, pn)
        para_open = false
        pn = 0
    }

    sub begin_line() {
        line_al = 0
        line_ind = 0
        line_list = 0
        line_soft = false
        line_hard = false
        line_started = false
        marker_skip = 0
        got_x16 = false
    }

    sub start_text() {
        if line_started
            return
        line_started = true
        if line_soft and para_open {
            if pn > 0 and pn < doc.SBMAX {
                if @(doc.sbch + pn - 1) != 32 {
                    @(doc.sbch + pn) = 32
                    @(doc.sbsty + pn) = @(doc.sbsty + pn - 1)
                    @(doc.sbcol + pn) = @(doc.sbcol + pn - 1)
                    pn++
                }
            }
        } else {
            flush_para()
            para_open = true
            pn = 0
            pa_al_i = line_al
            pa_ind_i = line_ind
            pa_list_i = line_list
            para_hard = 0
            if line_hard
                para_hard = doc.F_HARD
        }
    }

    sub add_char(ubyte c) {
        if marker_skip != 0 {
            marker_skip--
            return
        }
        if c < 32
            return
        start_text()
        if pn < doc.SBMAX - 1 {
            @(doc.sbch + pn) = c
            @(doc.sbsty + pn) = cur_sty
            @(doc.sbcol + pn) = (cur_bg << 4) | cur_fg
            pn++
        }
    }

    sub end_line() {
        start_text()        ; empty lines still start a paragraph
        begin_line()
    }

    sub is_word(str w) -> bool {
        return strings.compare(&wname, w) == 0
    }

    sub read_word(ubyte first) -> ubyte {
        ; first = first letter already read; reads the word name and numeric parameter. returns the delimiter char that follows (consumed if space)
        ubyte n = 0
        ubyte c = first
        while (c >= iso:'a' and c <= iso:'z') or (c >= iso:'A' and c <= iso:'Z') {
            if n < 14 {
                wname[n] = c
                n++
            }
            c = next_byte()
            if peek_is_eof()
                break
        }
        wname[n] = 0
        whasparam = false
        wneg = false
        wval = 0
        if c == iso:'-' {
            wneg = true
            c = next_byte()
        }
        while c >= iso:'0' and c <= iso:'9' {
            whasparam = true
            wval = wval * 10 + (c - iso:'0')
            c = next_byte()
            if peek_is_eof()
                break
        }
        if c == iso:' '
            return 0
        return c
    }

    sub apply_xwp(uword v) {
        line_al = lsb(v) & 3
        line_list = (lsb(v) >> 2) & 3
        line_ind = (lsb(v) >> 4) & 7
        line_soft = (lsb(v) & 128) != 0
        got_x16 = true
        if line_list != 0 and not line_soft
            marker_skip = 4
    }

    sub import(str name) -> bool {
        if not diskio.f_open(name)
            return false
        ilen = 0
        ipos = 0
        ieof = false
        depth = 0
        skip_depth = 0
        cur_sty = 0
        cur_fg = 0
        cur_bg = 1
        para_open = false
        pn = 0
        first_flush = true
        ubyte c
        ubyte pending = 0
        bool havepending = false
        bool body = false
        begin_line()
        ; start with an empty document
        while doc.nlines > 1
            doc.delete_line(doc.nlines - 1)
        sys.memset(doc.LB2, 256, 0)
        doc.st(0, doc.LB2)
        while true {
            if havepending {
                c = pending
                havepending = false
            } else {
                c = next_byte()
                if peek_is_eof() and c == 0
                    break
            }
            if c == iso:'{' {
                if depth < 19 {
                    gs_sty[depth] = cur_sty
                    gs_fg[depth] = cur_fg
                    gs_bg[depth] = cur_bg
                }
                depth++
            } else if c == iso:'}' {
                if depth > 0 {
                    depth--
                    if depth < 19 {
                        cur_sty = gs_sty[depth]
                        cur_fg = gs_fg[depth]
                        cur_bg = gs_bg[depth]
                    }
                }
                if skip_depth != 0 and depth < skip_depth
                    skip_depth = 0
            } else if c == 92 {
                c = next_byte()
                if c == iso:'\\' or c == iso:'{' or c == iso:'}' {
                    if skip_depth == 0 and body
                        add_char(c)
                } else if c == 39 {
                    ubyte h1 = next_byte()
                    ubyte h2 = next_byte()
                    ubyte v = 0
                    if h1 >= iso:'a'
                        v = h1 - iso:'a' + 10
                    else if h1 >= iso:'A'
                        v = h1 - iso:'A' + 10
                    else
                        v = h1 - iso:'0'
                    v <<= 4
                    if h2 >= iso:'a'
                        v |= h2 - iso:'a' + 10
                    else if h2 >= iso:'A'
                        v |= h2 - iso:'A' + 10
                    else
                        v |= h2 - iso:'0'
                    if skip_depth == 0 and body
                        add_char(v)
                } else if c == iso:'~' {
                    if skip_depth == 0 and body
                        add_char(32)
                } else if c == iso:'*' {
                    ; destination: only our own paragraph marker is interesting
                    c = next_byte()
                    if c == 92 {
                        c = next_byte()
                        ubyte d2 = read_word(c)
                        if d2 != 0 {
                            pending = d2
                            havepending = true
                        }
                        if is_word(iso:"xwp") and skip_depth == 0 {
                            apply_xwp(wval)
                        }
                    }
                    skip_depth = depth
                } else if (c >= iso:'a' and c <= iso:'z') or (c >= iso:'A' and c <= iso:'Z') {
                    ubyte d = read_word(c)
                    if d != 0 {
                        pending = d
                        havepending = true
                    }
                    if skip_depth == 0
                        control_word()
                    if (is_word(iso:"fonttbl") or is_word(iso:"colortbl") or is_word(iso:"stylesheet") or is_word(iso:"info") or is_word(iso:"pict") or is_word(iso:"header") or is_word(iso:"footer")) and skip_depth == 0
                        skip_depth = depth
                    if is_word(iso:"pard") or is_word(iso:"par") or is_word(iso:"sectd")
                        body = true
                }
            } else if c == 13 or c == 10 {
                ; ignored
            } else if skip_depth == 0 and body {
                if uc_skip != 0
                    uc_skip--
                else
                    add_char(c)
            }
        }
        diskio.f_close()
        flush_para()
        if first_flush {
            ; empty file
        }
        doc.curline = 0
        doc.curcol = 0
        doc.sel_active = false
        doc.need_repag = true
        doc.mark_all()
        return true
    }

    sub control_word() {
        if is_word(iso:"par") or is_word(iso:"line") {
            end_line()
        } else if is_word(iso:"pard") {
            begin_line()
        } else if is_word(iso:"plain") {
            cur_sty = 0
            cur_fg = 0
            cur_bg = 1
        } else if is_word(iso:"b") {
            if whasparam and wval == 0
                cur_sty &= ~1
            else
                cur_sty |= 1
        } else if is_word(iso:"i") {
            if whasparam and wval == 0
                cur_sty &= ~2
            else
                cur_sty |= 2
        } else if is_word(iso:"ul") {
            if whasparam and wval == 0
                cur_sty &= ~4
            else
                cur_sty |= 4
        } else if is_word(iso:"ulnone") {
            cur_sty &= ~4
        } else if is_word(iso:"f") {
            ubyte f = 0
            if wval < 3
                f = lsb(wval)
            cur_sty = (cur_sty & $0f) | (f << 4)
        } else if is_word(iso:"cf") {
            if wval >= 1 and wval <= 16
                cur_fg = lsb(wval) - 1
            else
                cur_fg = 0
        } else if is_word(iso:"highlight") or is_word(iso:"cb") {
            if wval >= 1 and wval <= 16
                cur_bg = lsb(wval) - 1
            else
                cur_bg = 1
        } else if is_word(iso:"qc") {
            if not got_x16
                line_al = 1
        } else if is_word(iso:"qr") {
            if not got_x16
                line_al = 2
        } else if is_word(iso:"ql") {
            if not got_x16
                line_al = 0
        } else if is_word(iso:"li") {
            if not got_x16 {
                uword lv = wval / 576
                if lv > doc.MAXIND
                    lv = doc.MAXIND
                line_ind = lsb(lv)
            }
        } else if is_word(iso:"pagebb") {
            line_hard = true
        } else if is_word(iso:"page") {
            line_hard = true
        } else if is_word(iso:"tab") {
            add_char(32)
            add_char(32)
            add_char(32)
            add_char(32)
        } else if is_word(iso:"u") {
            ubyte ch = iso:'?'
            if wval == 8217 or wval == 8216
                ch = 39
            else if wval == 8220 or wval == 8221
                ch = 34
            else if wval == 8211 or wval == 8212
                ch = iso:'-'
            else if wval == 8226 or wval == 9679
                ch = 7
            else if wval == 9675
                ch = iso:'o'
            else if wval == 9632
                ch = iso:'#'
            else if wval < 256
                ch = lsb(wval)
            add_char(ch)
            uc_skip = 1
        }
    }
}
