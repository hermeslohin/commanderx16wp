; x16wphc.p8 - 256-colour pictures for X16 Write as a bank library: X16WPHC.BIN, RAM bank 55 at $AE00
; (the first $E00 bytes of bank 55 are vid.p8's render buffers). Loaded by X16WPPL.BIN (pl.setup) and
; called by X16WPPI.BIN (pi.draw_entry) for every row of the page view.
;
; The page itself is a 640 x 240 x 4 bpp bitmap on VERA layer 0, so it has 16 colours. Pictures are
; drawn instead on layer 1, which sits on top of it: 16 x 8 pixel tiles in 8 bpp, colour 0 transparent,
; with palette entries 16..241 (the Sunset UI keeps 0..15) holding a 6 x 7 x 5 RGB cube and 16 greys.
; Every BMX colour goes to the nearest of those (per channel for the cube, the mean for the greys), so
; any number of pictures can be on screen together without fighting over palette entries.
;
; VRAM is the limit: the bitmap takes 75 KB, the fonts, Quill and the mouse pointer some more, so there
; are 310 tiles (39,680 pixels) free, about one 320 x 240 picture's worth, in three pieces:
;   $12C00-$12FFF tiles 600..607 (600 = the all-zero tile every empty map cell points to)
;   $13100-$14FFF tiles 610..671 (the KERNAL mouse pointer is at $13000)
;   $15000-$15FFF the layer 1 map, 64 x 32 cells (40 x 30 of them on screen)
;   $18100-$1F97F tiles 770..1010 (after Quill; includes the KERNAL text screen and charset, which
;                 X16 Write doesn't use while it runs; the charset is reloaded when it quits)
; Each screen row of the page view that shows a picture owns one run of tiles (rs/rn). A row that gets
; no tiles (all taken) returns false and X16WPPI.BIN draws it in the 16 colours on layer 0 as before.
; A row that already shows the same picture row is left alone (cursor blinks redraw the cursor line).
; When the view scrolls (view.vtop changed since the last call) the rows and their map rows move along,
; the way view.set_vtop moves the bitmap. Dialogs (view.draw_box) turn layer 1 off; the next row drawn
; turns it back on.

%address  $AE00
%memtop   $C000
%output   library

%import syslib
%import wpsyms

main {
    %jmptable (
        hc.setup,       ; $AE03  r0 = &vid.text as the WP sees it -> A true if set up (palette, layer 1)
        hc.row_entry,   ; $AE06  a page view row (registers: see row_entry) -> A true if done here
    )

    sub start() {
    }
}

hc {
    const ubyte ROW0 = 5                ; view.ROW0
    const ubyte ROWS = 24               ; view.VIEWROWS
    const uword NT = 310                ; tiles in the pool
    const uword ZT = 600                ; the all-zero tile (VRAM $12C00)
    const uword MAPV = $5000            ; layer 1 map at VRAM $15000 (bank 1), 128 bytes a row

    ; screen rows of the page view: first pool tile, tile count (0 = none), picture id and row shown
    uword[ROWS] rs
    ubyte[ROWS] rn
    ubyte[ROWS] rid
    ubyte[ROWS] rpr
    uword vt                            ; view.vtop the rows belong to
    ubyte gen                           ; X16WPPI.BIN's picture generation they belong to
    ubyte mapid                         ; picture map8 is for (0 = none)
    ubyte[256] map8                     ; BMX colour -> palette entry 16..241

    ; the colour cube: levels of red / green / blue, and the nearest level of each value 0..15
    ubyte[6] vr = [0, 3, 6, 9, 12, 15]
    ubyte[7] vg = [0, 3, 5, 8, 10, 13, 15]
    ubyte[5] vb = [0, 4, 8, 11, 15]
    ubyte[16] lr = [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5]
    ubyte[16] lg = [0, 0, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 6]
    ubyte[16] lb = [0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4]
    ubyte[4] sh2 = [6, 4, 2, 0]

    ; the row being drawn (row_entry)
    ubyte sr
    ubyte id
    ubyte prow
    ubyte bpp
    ubyte pbank
    uword w
    uword h
    uword dw
    uword dh
    uword bpl
    uword sacc
    long soff

    sub setup() -> bool {
        if cx16.r0 != wp.CHECK
            return false
        ubyte r
        ubyte g
        ubyte b
        sys.set_irqd()
        cx16.vaddr(1, $fa00 + 16 * 2, 0, 1)        ; palette entries 16.. : the cube, then the greys
        for r in 0 to 5 {
            for g in 0 to 6 {
                for b in 0 to 4 {
                    cx16.VERA_DATA0 = (vg[g] << 4) | vb[b]
                    cx16.VERA_DATA0 = vr[r]
                }
            }
        }
        for r in 0 to 15 {
            cx16.VERA_DATA0 = r * $11
            cx16.VERA_DATA0 = r
        }
        cx16.vaddr(1, $2c00, 0, 1)                  ; tile ZT
        repeat 128
            cx16.VERA_DATA0 = 0
        sys.clear_irqd()
        for r in 0 to 31
            clearmap(r - ROW0)
        cx16.VERA_L1_CONFIG = $13                   ; 32 x 64 map, tiles, 8 bpp
        cx16.VERA_L1_MAPBASE = $a8                  ; $15000
        cx16.VERA_L1_TILEBASE = $01                 ; tiles from VRAM 0, 16 x 8
        cx16.VERA_L1_HSCROLL = 0
        cx16.VERA_L1_VSCROLL = 0
        vt = wp.vtop
        return true
    }

    sub sqd(ubyte a, ubyte b) -> uword {
        ubyte d = a - b
        if a < b
            d = b - a
        return (d as uword) * d
    }

    ; the palette entry nearest to r, g, b (0..15 each): the cube, or a grey if that is nearer
    sub colour(ubyte r, ubyte g, ubyte b) -> ubyte {
        ubyte ir = lr[r]
        ubyte ig = lg[g]
        ubyte ib = lb[b]
        ubyte k = (r + g + b + 1) / 3
        if sqd(k, r) + sqd(k, g) + sqd(k, b) < sqd(vr[ir], r) + sqd(vg[ig], g) + sqd(vb[ib], b)
            return 226 + k
        return 16 + (ir * 7 + ig) * 5 + ib
    }

    ; n bytes of the picture's data (banks from pbank) from offset off into main RAM at dst
    sub xfer(long off, uword dst, uword n) {
        uword a
        uword c
        while n != 0 {
            a = lsw(off) & $1fff
            c = $2000 - a
            if c > n
                c = n
            wp.bxfer(pbank + ((lsb(msw(off)) << 3) | (msb(lsw(off)) >> 5)), $a000 + a, dst, c, 0)
            off += c
            dst += c
            n -= c
        }
    }

    ; map8 for picture id from its BMX palette (missing entries are black)
    sub load_map() {
        uword buf = wp.sbch
        xfer(256, buf, 32)
        uword ent = @(buf + 10)
        if ent == 0
            ent = 256
        ubyte st = @(buf + 11)
        sys.memset(&map8, 256, 16)                  ; black
        xfer(256 + 32, buf, ent * 2)
        repeat ent {
            map8[st] = colour(@(buf + 1) & 15, @(buf) >> 4, @(buf) & 15)
            st++
            buf += 2
        }
        mapid = id
    }

    ; pool tile -> VRAM tile number
    sub phys(uword v) -> uword {
        if v < 7
            return 601 + v
        if v < 69
            return 603 + v
        return 701 + v
    }

    sub map_addr(ubyte row) -> uword {
        return MAPV + ((ROW0 + row) as uword) * 128
    }

    ; map row of screen row i (ROW0 + i; may wrap below 0 for setup) back to the empty tile
    sub clearmap(ubyte i) {
        sys.set_irqd()
        cx16.vaddr(1, map_addr(i), 0, 1)
        repeat 40 {
            cx16.VERA_DATA0 = lsb(ZT)
            cx16.VERA_DATA0 = msb(ZT)
        }
        sys.clear_irqd()
    }

    ; screen row i shows no picture any more: its tiles go back to the pool
    sub clear(ubyte i) {
        clearmap(i)
        rn[i] = 0
        rid[i] = 0
    }

    ; screen row src (tiles and map row) becomes screen row dst; src outside the view: dst empty
    sub move(ubyte src, ubyte dst) {
        if src >= ROWS {
            clear(dst)
            return
        }
        rs[dst] = rs[src]
        rn[dst] = rn[src]
        rid[dst] = rid[src]
        rpr[dst] = rpr[src]
        sys.set_irqd()
        cx16.vaddr(1, map_addr(src), 0, 1)
        cx16.vaddr(1, map_addr(dst), 1, 1)
        repeat 80
            cx16.VERA_DATA1 = cx16.VERA_DATA0
        cx16.VERA_CTRL = 0
        sys.clear_irqd()
    }

    ; the view scrolled since the last call: move the rows with it (view.set_vtop moved the bitmap)
    sub sync() {
        uword v = wp.vtop
        ubyte i
        ubyte k
        if v > vt and v - vt < ROWS {
            k = lsb(v - vt)
            for i in 0 to ROWS - 1
                move(i + k, i)
        } else if vt > v and vt - v < ROWS {
            k = lsb(vt - v)
            i = ROWS
            repeat ROWS {
                i--
                move(i - k, i)              ; i < k wraps to >= ROWS: empty
            }
        } else if v != vt {
            for i in 0 to ROWS - 1
                clear(i)
        }
        vt = v
    }

    ; n free pool tiles in a run: the first, or $ffff
    sub find(ubyte n) -> uword {
        uword c = 0
        ubyte i = 0
        ubyte j
        repeat {
            if c + n <= NT {
                for j in 0 to ROWS - 1 {
                    if rn[j] != 0 and c < rs[j] + rn[j] and rs[j] < c + n
                        goto next
                }
                return c
            }
next:
            while i < ROWS and rn[i] == 0
                i++
            if i == ROWS
                return $ffff
            c = rs[i] + rn[i]
            i++
        }
    }

    ; r0L screen row of the page view, r1L picture id (0 = no picture on that row), r2L its row in the
    ; picture, r3 w, r4 h, r5 shown w, r6 shown h, r7 BMX bytes per line, r8L bpp, r9L first data bank,
    ; r10 source line of the row's first pixel row and r11 the remainder (shown row * h / shown h),
    ; r12 + r13L << 16 offset of that line in the picture's data, r13H X16WPPI.BIN's generation (changes
    ; when a picture id is freed or reused). -> true: done here; false: draw it in 16 colours on layer 0.
    sub row_entry() -> bool {
        sr = cx16.r0L
        id = cx16.r1L
        prow = cx16.r2L
        w = cx16.r3
        h = cx16.r4
        dw = cx16.r5
        dh = cx16.r6
        bpl = cx16.r7
        bpp = cx16.r8L
        pbank = cx16.r9L
        sacc = cx16.r11
        soff = mklong2(cx16.r13L, cx16.r12)
        ubyte i
        if cx16.r13H != gen {
            gen = cx16.r13H
            mapid = 0
            for i in 0 to ROWS - 1
                rid[i] = 0                  ; still shown, but redrawn when next drawn
        }
        if sr >= ROWS
            return false
        sync()
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_VIDEO |= $20           ; layer 1 on (dialogs turn it off)
        if id == 0 {
            clear(sr)
            return true
        }
        if rn[sr] != 0 and rid[sr] == id and rpr[sr] == prow
            return true
        clear(sr)
        if id != mapid
            load_map()
        uword xs = (64 + (512 - dw) / 2) & $fffe
        uword xe = xs + dw
        ubyte c0 = lsb(xs >> 4)
        ubyte n = lsb((xe - 1) >> 4) - c0 + 1
        uword t = find(n)
        if t == $ffff
            return false
        rs[sr] = t
        rn[sr] = n
        rid[sr] = id
        rpr[sr] = prow
        uword buf = wp.sbch
        uword dy = (prow as uword) * 8
        uword x
        uword sx
        uword acc
        uword p
        ubyte r
        ubyte v
        bool have
        for r in 0 to 7 {
            have = dy < dh
            if have
                xfer(soff, buf, bpl)
            x = (c0 as uword) << 4
            sx = 0
            acc = 0
            sys.set_irqd()
            for i in 0 to n - 1 {
                p = phys(t + i)
                cx16.vaddr(lsb(p >> 9), (p << 7) + (r as uword) * 16, 0, 1)
                repeat 16 {
                    v = 0
                    if have and x >= xs and x < xe {
                        when bpp {
                            8 -> v = @(buf + sx)
                            4 -> {
                                v = @(buf + (sx >> 1))
                                if sx & 1 == 0
                                    v >>= 4
                                v &= 15
                            }
                            2 -> v = (@(buf + (sx >> 2)) >> sh2[lsb(sx) & 3]) & 3
                            else -> v = (@(buf + (sx >> 3)) >> (7 - (lsb(sx) & 7))) & 1
                        }
                        v = map8[v]
                        acc += w
                        while acc >= dw {
                            acc -= dw
                            sx++
                        }
                    }
                    cx16.VERA_DATA0 = v
                    x++
                }
            }
            sys.clear_irqd()
            dy++
            sacc += h
            while sacc >= dh {
                sacc -= dh
                soff += bpl
            }
        }
        sys.set_irqd()
        cx16.vaddr(1, map_addr(sr) + (c0 as uword) * 2, 0, 1)
        for i in 0 to n - 1 {
            p = phys(t + i)
            cx16.VERA_DATA0 = lsb(p)
            cx16.VERA_DATA0 = msb(p)
        }
        sys.clear_irqd()
        return true
    }
}
