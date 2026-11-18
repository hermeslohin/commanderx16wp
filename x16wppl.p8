; x16wppl.p8 - pictures for X16 Write, the loading side: X16WPPL.BIN, RAM bank 56 at $A200 (the
; first 512 bytes of bank 56 are rtf.p8's file buffer). Loaded at start by pix.p8: the Picture button
; (a BMX file from the SD card, or from ownCloud's Documents/ through X16WPCL.BIN, bank 62), reading
; and checking BMX files, the palette map, RTF import of {\*\xwpbmx HEX}, and the toolbar's tool tips
; (they live here to leave main RAM for the program). The picture table and its RAM banks belong to
; X16WPPI.BIN (x16wppi.p8, bank 54, which describes the design); this library calls its jump table.
; It calls X16 Write's main-RAM routines through wpsyms.p8 (tools/gen_wpsyms.py for bank 56).

%address  $A200
%memtop   $C000
%output   library

%import syslib
%import wpsyms

main {
    %jmptable (
        pl.setup,       ; $A203  r0 = &vid.text as the WP sees it -> A true if this library matches
        pl.button,      ; $A206  the Picture button
        pl.import,      ; $A209  RTF import: \*\xwpbmx read, the hex follows up to the closing brace
        pl.tip_entry,   ; $A20C  r0L = button id: its tool tip in the status bar
    )

    sub start() {
    }
}

pl {
    const ubyte O_LEN = 240
    const ubyte O_TBL = 245
    const ubyte O_PIC = 246
    const ubyte O_PROW = 247
    const ubyte MAXPIC = 15

    ; X16WPPI.BIN (bank 54)
    extsub @bank 54 $A015 = a_alloc(uword lo @R0, ubyte hi @R1) clobbers(X, Y) -> ubyte @A
    extsub @bank 54 $A018 = a_xfer(ubyte id @R0, uword offlo @R1, ubyte offhi @R2, uword dst @R3, uword n @R4, ubyte out @R5) clobbers(A, X, Y)
    extsub @bank 54 $A01B = a_free(ubyte id @R0) clobbers(A, X, Y)
    extsub @bank 54 $A01E = a_begin() clobbers(X, Y) -> ubyte @A
    extsub @bank 54 $A021 = a_shrink(ubyte id @R0, ubyte nb @R1) clobbers(A, X, Y)
    extsub @bank 54 $A024 = a_set(ubyte id @R0) clobbers(A, X, Y)
    extsub @bank 54 $A027 = a_lines(ubyte id @R0, uword at @R1, ubyte reuse @R2) clobbers(X, Y) -> bool @A

    ; the header being checked (hdr)
    uword h_w
    uword h_h
    uword h_data
    uword h_bpl
    uword h_ent
    ubyte h_start
    ubyte h_bpp
    long h_total                        ; length the BMX must have

    ubyte[256] map
    uword s_first                       ; span()
    uword s_last

    ; the Sunset screen palette (vid.pal_lo / pal_hi): green<<4|blue, red
    ubyte[16] pal_lo = [$13,$ed,$48,$dd,$8f,$b4,$6e,$d4,$93,$52,$9b,$26,$59,$fa,$cf,$bf]
    ubyte[16] pal_hi = [$2,$f,$f,$4,$9,$4,$3,$f,$f,$a,$f,$3,$6,$b,$8,$c]

    sub setup() -> bool {
        if cx16.r0 != wp.CHECK
            return false
        load_hc()
        return true
    }

    ; X16WPHC.BIN (x16wphc.p8): 256-colour pictures on layer 1, RAM bank 55 at $AE00
    extsub @bank 55 $AE00 = hc_init() clobbers(A, X, Y)
    extsub @bank 55 $AE03 = hc_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank 54 $A02A = a_hc() clobbers(A, X, Y)

    sub load_hc() {
        if not wp.f_open(iso:"X16WPHC.BIN")
            return
        uword sb = wp.sbch
        uword a = $ae00
        uword n
        while true {
            n = wp.f_read(sb, 512)
            if n == 0
                break
            if n > $c000 - a {
                wp.f_close()
                return
            }
            wp.bxfer(55, a, sb, n, 1)
            a += n
        }
        wp.f_close()
        if a == $ae00
            return
        hc_init()
        if hc_setup(wp.CHECK)
            a_hc()
    }

    ; X16WPCL.BIN (bank 62, loaded by cloudx.menu): pick a .bmx on ownCloud, download it to the temp file
    extsub @bank 62 $A015 = cl_get_bmx() clobbers(X, Y) -> bool @A
    str TMPN = iso:"X16WP.TMP"


    ; n bytes of picture id's data from offset off into main RAM at dst (out: from main RAM)
    sub xfer(ubyte id, long off, uword dst, uword n, bool out) {
        a_xfer(id, lsw(off), lsb(msw(off)), dst, n, out as ubyte)
    }

    sub status(uword s) {
        wp.set_status(s)
        wp.draw_status()
    }

    sub changed(uword l) {
        wp.need_repag = true
        wp.mark_from(l)
        wp.rd_mode = 2
        wp.modified = true
    }

    ; ---------------- BMX header ----------------
    ; checks the 32-byte header at buf (main RAM): true if X16 Write can show it (sets h_*)
    sub hdr(uword buf) -> bool {
        if @(buf) != $42 or @(buf + 1) != $4d or @(buf + 2) != $58 or @(buf + 3) != 1
            return false
        h_bpp = @(buf + 4)
        if h_bpp != 1 and h_bpp != 2 and h_bpp != 4 and h_bpp != 8
            return false
        h_w = peekw(buf + 6)
        h_h = peekw(buf + 8)
        if h_w == 0 or h_w > 640 or h_h == 0 or h_h > 1024 or @(buf + 14) != 0
            return false
        h_ent = @(buf + 10)
        if h_ent == 0
            h_ent = 256
        h_start = @(buf + 11)
        h_data = peekw(buf + 12)
        if h_data < 32 + h_ent * 2
            return false
        h_bpl = (h_w * h_bpp) >> 3
        if h_bpl == 0
            h_bpl = 1
        h_total = (h_data as long) + (h_bpl as long) * h_h
        return true
    }

    ; the shown size and the palette map of picture id (its BMX is in its banks, header in h_*)
    sub finish(ubyte id) {
        uword dw = h_w
        uword dh = (h_h + 1) / 2
        if h_w > 496 or h_h > 640 {
            if (h_w as long) * 640 >= (h_h as long) * 496 {
                dw = 496
                dh = lsw((h_h as long) * 496 / ((h_w as long) * 2))
            } else {
                dh = 320
                dw = lsw((h_w as long) * 640 / h_h)
            }
        }
        dw &= $fffe
        if dw < 2
            dw = 2
        if dh == 0
            dh = 1
        uword lb = wp.LB
        pokew(lb, h_w)
        pokew(lb + 2, h_h)
        pokew(lb + 4, dw)
        pokew(lb + 6, dh)
        pokew(lb + 8, h_bpl)
        pokew(lb + 10, h_data)
        @(lb + 12) = h_bpp
        @(lb + 13) = lsb((dh + 7) / 8)
        pokew(lb + 14, lsw(h_total))
        @(lb + 16) = lsb(msw(h_total))
        a_set(id)
        ; palette map: BMX colour -> nearest Sunset colour (missing entries are black)
        uword sb = wp.sbch
        xfer(id, 256 + 32, sb, h_ent * 2, false)
        ubyte k = near(0, 0, 0)
        uword i
        for i in 0 to 255
            map[lsb(i)] = k
        ubyte g
        for i in 0 to h_ent - 1 {
            g = @(sb + i * 2)
            map[lsb(h_start + i)] = near(@(sb + i * 2 + 1) & 15, g >> 4, g & 15)
        }
        sys.memcopy(&map, sb, 256)
        xfer(id, 0, sb, 256, true)
    }

    ; the Sunset colour nearest to r, g, b (0..15 each)
    sub near(ubyte r, ubyte g, ubyte b) -> ubyte {
        ubyte best = 0
        uword bestd = $ffff
        ubyte c
        uword d
        for c in 0 to 15 {
            d = 3 * sq(pal_hi[c], r) + 4 * sq(pal_lo[c] >> 4, g) + 2 * sq(pal_lo[c] & 15, b)
            if d < bestd {
                bestd = d
                best = c
            }
        }
        return best
    }

    sub sq(ubyte a, ubyte b) -> uword {
        ubyte d = a - b
        if a < b
            d = b - a
        return (d as uword) * d
    }

    ; ---------------- picture lines ----------------
    sub pid(uword l) -> ubyte {
        if l >= wp.nlines
            return 0
        return wp.meta(l, O_PIC)
    }

    ; first and last line of the picture on line l
    sub span(uword l) {
        s_first = l - wp.meta(l, O_PROW)
        s_last = s_first + wp.meta(l, 0) - 1
    }

    sub button() {
        ubyte id
        ubyte m = wp.cloud_menu(2)              ; 0 SD card (also without the ownCloud files), 1 ownCloud
        wp.redraw_everything()
        if m == 255
            return
        if m == 1 {
            if not cl_get_bmx()
                return
            id = load_file(TMPN)
            wp.disk_delete(TMPN)
        } else {
            uword buf = wp.nbuf
            @(buf) = 0
            bool ok = wp.dialog_input(iso:"Insert picture: BMX file on the SD card", buf, 24)
            wp.rd_mode = 2
            if not ok
                return
            id = load_file(buf)
        }
        if id == 0
            return
        ; where: on an empty line, before it; after a picture or table; else after the paragraph
        uword cur = wp.curline
        uword at
        if pid(cur) != 0 {
            span(cur)
            at = s_last + 1
        } else if wp.meta(cur, O_TBL) != 0 {
            at = cur
            while at < wp.nlines and wp.meta(at, O_TBL) != 0
                at++
        } else if wp.meta(cur, O_LEN) == 0 and wp.para_last(cur) == cur
            at = cur
        else
            at = wp.para_last(cur) + 1
        if not a_lines(id, at, 0) {
            a_free(id)
            status(iso:"The document is too long for this picture")
            return
        }
        uword after = at + wp.meta(at, 0)
        if after >= wp.nlines or pid(after) != 0 or wp.meta(after, O_TBL) != 0
            void wp.insert_blank(after)
        wp.sel_active = false
        wp.curline = at
        wp.curcol = 0
        changed(at)
        status(iso:"Picture inserted")
        wp.theme_hop = 32
    }

    ; reads a BMX file from the SD card into a new picture: its id, or 0 (status says why)
    sub load_file(uword name) -> ubyte {
        uword sb = wp.sbch
        if not wp.f_open(name) {
            status(iso:"Can't open that file")
            return 0
        }
        if wp.f_read(sb, 32) != 32 or not hdr(sb) {
            wp.f_close()
            status(iso:"Not a BMX picture X16 Write can show")
            return 0
        }
        long need = 256 + h_total
        ubyte id = a_alloc(lsw(need), lsb(msw(need)))
        if id == 0 {
            wp.f_close()
            status(iso:"Not enough memory for this picture")
            return 0
        }
        status(iso:"Loading the picture...")
        xfer(id, 256, sb, 32, true)
        long off = 288
        long left = h_total - 32
        uword c
        uword got
        while left > 0 {
            c = 512
            if left < 512
                c = lsw(left)
            got = wp.f_read(sb, c)
            if got == 0
                break
            xfer(id, off, sb, got, true)
            off += got
            left -= got
        }
        wp.f_close()
        if left > 0 {
            a_free(id)
            status(iso:"The picture file is too short")
            return 0
        }
        finish(id)
        return id
    }

    ; \*\xwpbmx: read the hex up to the closing brace into the longest free run of banks, then make
    ; the picture's lines at the end of the document (rtf.p8 handles the brace itself)
    sub import() {
        wp.flush_para()
        ubyte id = a_begin()
        long cap = (cx16.r1L as long) << 13
        uword sb = wp.sbch
        long off = 256
        uword k = 0
        ubyte c
        ubyte v
        ubyte acc = 0
        bool half = false
        repeat {
            c = wp.next_byte()
            if c == iso:'}' or c == 0
                break
            if c >= iso:'0' and c <= iso:'9'
                v = c - iso:'0'
            else if c >= iso:'a' and c <= iso:'f'
                v = c - iso:'a' + 10
            else if c >= iso:'A' and c <= iso:'F'
                v = c - iso:'A' + 10
            else
                continue
            if half {
                @(sb + k) = acc | v
                k++
                if k == 256 {
                    if id != 0 and off + 256 <= cap
                        xfer(id, off, sb, 256, true)
                    off += 256
                    k = 0
                }
            } else
                acc = v << 4
            half = not half
        }
        if id == 0
            return
        if k != 0 and off + k <= cap
            xfer(id, off, sb, k, true)
        off += k
        long blen = off - 256
        bool ok = blen >= 32 and off <= cap
        if ok {
            xfer(id, 256, sb, 32, false)
            ok = hdr(sb) and blen >= h_total
        }
        if not ok {
            a_free(id)
            return
        }
        a_shrink(id, lsb((256 + h_total + 8191) >> 13))    ; keep only the banks it needs
        finish(id)
        uword at = wp.nlines
        bool reuse = wp.first_flush
        if reuse {
            wp.first_flush = false
            at = 0
        }
        if not a_lines(id, at, reuse as ubyte)
            a_free(id)
    }

    ; ---------------- tool tips ----------------
    ; A tip borrows the status bar: the message under it (e.g. "Hub unreachable: ...") is kept and
    ; comes back when the mouse leaves the toolbar (id 0). If something else wrote the status bar while
    ; a tip was showing (a button's own result), that message stays and becomes the one to keep.
    ubyte[51] keep
    uword shown                 ; the tip on the status bar now, 0 = none

    sub tip_entry() {
        tip(cx16.r0L)
    }

    ; the status bar still shows the tip (set_status pads it with spaces)
    sub tip_showing() -> bool {
        if shown == 0
            return false
        ubyte i = 0
        while @(shown + i) != 0 {
            if @(wp.status_msg + i) != @(shown + i)
                return false
            i++
        }
        return true
    }

    sub tip(ubyte id) {
        if not tip_showing() {
            ubyte i
            for i in 0 to 50
                keep[i] = @(wp.status_msg + i)
        }
        shown = 0
        if id == 0 {
            status(&keep)
            return
        }
        uword s = iso:""
        when id {
            1 -> s = iso:"New document"
            2 -> s = iso:"Open from SD card or ownCloud"
            3 -> s = iso:"Save (back to ownCloud if opened there)"
            4 -> s = iso:"Save As on SD card or ownCloud"
            5 -> s = iso:"Cut"
            6 -> s = iso:"Copy"
            7 -> s = iso:"Paste"
            8 -> s = iso:"Select all"
            9 -> s = iso:"Insert page break"
            10 -> s = iso:"Bold"
            11 -> s = iso:"Italic"
            12 -> s = iso:"Underline"
            13 -> s = iso:"Align left"
            14 -> s = iso:"Center"
            15 -> s = iso:"Align right"
            16 -> s = iso:"Bulleted list"
            17 -> s = iso:"Numbered list"
            18 -> s = iso:"Decrease indent"
            19 -> s = iso:"Increase indent"
            20 -> s = iso:"Quit"
            21 -> s = iso:"Change font and size"
            22 -> s = iso:"Table: insert, add or delete rows"
            23 -> s = iso:"Insert a BMX picture from the SD card"
            else -> {
                if id >= 100 and id < 116
                    s = iso:"Text color"
                else if id >= 120 and id < 136
                    s = iso:"Highlight color"
            }
        }
        if @(s) == 0 {
            status(&keep)           ; no tip for this one: show the kept message
            return
        }
        shown = s
        status(s)
    }
}
