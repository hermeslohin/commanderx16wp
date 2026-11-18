; vid.p8 - 640x240 (x2 vertical stretch) 16-colour bitmap text renderer for the X16 word processor.
; Every character is an 8x8 cell; fonts live in VRAM, styles (bold/italic/underline) are synthesized.

%import syslib

vid {
    %option ignore_unused

    ; --- palette indexes (VERA default C64-like palette, written explicitly in gfx_init) ---
    const ubyte C_BLACK = 0
    const ubyte C_WHITE = 1
    const ubyte C_RED = 2
    const ubyte C_CYAN = 3
    const ubyte C_PURPLE = 4
    const ubyte C_GREEN = 5
    const ubyte C_BLUE = 6
    const ubyte C_YELLOW = 7
    const ubyte C_ORANGE = 8
    const ubyte C_BROWN = 9
    const ubyte C_LRED = 10
    const ubyte C_DGRAY = 11
    const ubyte C_GRAY = 12
    const ubyte C_LGREEN = 13
    const ubyte C_LBLUE = 14
    const ubyte C_LGRAY = 15

    ; style byte: bit0 bold, bit1 italic, bit2 underline, bit3 raw glyph, bits 4-5 font,
    ; bit6 large (stored: the character is 2x2 cells). While rendering, a large character is split
    ; into cells: bit6 = left half, bit7 = right half; vhalf says which row (0 top, 1 bottom).
    const ubyte S_BOLD = 1
    const ubyte S_ITAL = 2
    const ubyte S_UNDER = 4
    const ubyte S_RAW = 8
    const ubyte NFONTS = 3

    const uword FONT_VRAM = $6000       ; bank 1, $16000 .. 3 fonts of 2 KB

    ; cell composition arrays: filled by the caller, drawn by render_run()
    ubyte[80] r_ch
    ubyte[80] r_sty
    ubyte[80] r_col         ; (bg<<4) | fg
    ubyte[80] c_fl
    ubyte vhalf             ; 0/1: top/bottom screen row of a large-size line (see render_run)
    uword c_gl = memory("c_gl", 640, 0)
    uword pairs = memory("pairs", 320, 0)

    ubyte[16] pal_lo = [$00,$ff,$00,$fe,$4c,$c5,$0a,$e7,$85,$40,$77,$33,$77,$f6,$8f,$bb]
    ubyte[16] pal_hi = [$0,$f,$8,$a,$c,$0,$0,$e,$d,$6,$f,$3,$7,$8,$0,$b]

    ; names (iso encoded) of the fonts, and the RTF fonts they map to
    str font_name0 = iso:"Courier New"
    str font_name1 = iso:"Lucida Console"
    str font_name2 = iso:"Andale Mono"

    sub font_name(ubyte f) -> str {
        when f {
            0 -> return font_name0
            1 -> return font_name1
            else -> return font_name2
        }
    }

    sub load_fonts() {
        ; copy the ROM charsets into VRAM font slots. slot0=ISO, slot1=PETSCII upper/lower, slot2=PETSCII upper/gfx
        ubyte slot
        ubyte cs
        for slot in 0 to 2 {
            when slot {
                0 -> cs = 1
                1 -> cs = 3
                else -> cs = 2
            }
            cx16.screen_set_charset(cs, 0)
            sys.set_irqd()
            cx16.vaddr(1, $f000, 0, 1)
            cx16.vaddr(1, FONT_VRAM + (slot as uword) * 2048, 1, 1)
            repeat 2048 {
                cx16.VERA_DATA1 = cx16.VERA_DATA0
            }
            sys.clear_irqd()
        }
        cbm.CHROUT($0f)         ; keyboard / console in ISO mode
    }

    sub gfx_init() {
        ubyte i
        ; palette
        sys.set_irqd()
        cx16.vaddr(1, $fa00, 0, 1)
        for i in 0 to 15 {
            cx16.VERA_DATA0 = pal_lo[i]
            cx16.VERA_DATA0 = pal_hi[i]
        }
        sys.clear_irqd()
        cx16.VERA_CTRL = 0
        cx16.VERA_DC_HSCALE = 128
        cx16.VERA_DC_VSCALE = 64
        cx16.VERA_L0_CONFIG = $06       ; bitmap mode, 4bpp
        cx16.VERA_L0_MAPBASE = 0
        cx16.VERA_L0_TILEBASE = $01     ; bitmap at VRAM 0, 640 pixels wide
        cx16.VERA_L0_HSCROLL_L = 0
        cx16.VERA_L0_HSCROLL_H = 0
        cx16.VERA_L0_VSCROLL_L = 0
        cx16.VERA_L0_VSCROLL_H = 0
        cx16.VERA_DC_VIDEO = (cx16.VERA_DC_VIDEO & $07) | $50       ; layer0 + sprites, layer1 off
        cx16.VERA_DC_BORDER = C_DGRAY
        clear_screen(C_GRAY)
        cx16.mouse_config(1, 80, 30)
    }

    sub gfx_off() {
        cx16.mouse_config(0, 0, 0)
        cx16.set_screen_mode(0)
        cbm.CHROUT($8f)
        cbm.CHROUT(147)
    }

    sub clear_screen(ubyte color) {
        ubyte v = (color << 4) | color
        sys.set_irqd()
        cx16.vaddr(0, 0, 0, 1)
        repeat 76800 / 8 {
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
            cx16.VERA_DATA0 = v
        }
        sys.clear_irqd()
    }

    sub glyph_code(ubyte font, ubyte ch) -> ubyte {
        if font == 0
            return ch
        ; PETSCII screen code sets
        if ch >= 97 and ch <= 122
            return ch - 96
        if ch >= 65 and ch <= 90 {
            if font == 1
                return ch
            return ch - 64
        }
        if ch == 64
            return 0
        if ch >= 91 and ch <= 95
            return ch - 64
        if ch == 96
            return 39
        if ch == 124
            return 93           ; | vertical bar
        if ch < 64
            return ch
        return 63
    }

    sub fetch_glyph(ubyte font, ubyte ch, uword dst) {
        ubyte code = glyph_code(font, ch)
        uword va = FONT_VRAM + (font as uword) * 2048 + (code as uword) * 8
        sys.set_irqd()
        cx16.vaddr(1, va, 1, 1)
        cx16.VERA_CTRL = 1
        ubyte j
        for j in 0 to 7 {
            @(dst + j) = cx16.VERA_DATA1
        }
        cx16.VERA_CTRL = 0
        sys.clear_irqd()
    }

    sub set_vaddr(ubyte row, ubyte r, ubyte col0) {
        uword y = (row as uword) * 8 + r
        uword a = y << 6
        uword b = y << 8
        uword s = a + b
        ubyte bank = 0
        if s < a
            bank = 1
        uword c = (col0 as uword) << 2
        s += c
        if s < c
            bank += 1
        cx16.VERA_CTRL = 0
        cx16.VERA_ADDR_L = lsb(s)
        cx16.VERA_ADDR_M = msb(s)
        cx16.VERA_ADDR_H = bank | $10
    }

    ; draws the first n cells of r_ch/r_sty/r_col at cell (col0,row)
    sub render_run(ubyte row, ubyte col0, ubyte n) {
        if n == 0
            return
        ubyte i
        ubyte s
        ubyte k
        ubyte fg
        ubyte bg
        ubyte f
        ubyte r
        ubyte g
        ubyte fl
        uword gp = c_gl
        uword pp = pairs
        for i in 0 to n-1 {
            s = r_sty[i]
            k = r_col[i]
            fg = k & 15
            bg = k >> 4
            if r_ch[i] == 32 and (s & 12) == 0 {
                c_fl[i] = 128
                @(pp) = (bg << 4) | bg
            } else {
                f = (s >> 4) & 3
                if (s & S_RAW) != 0
                    fetch_raw(f, r_ch[i], gp)
                else
                    fetch_glyph(f, r_ch[i], gp)
                c_fl[i] = (s & 7) | ((s >> 1) & $60)
                @(pp) = (bg << 4) | bg
                @(pp+1) = (bg << 4) | fg
                @(pp+2) = (fg << 4) | bg
                @(pp+3) = (fg << 4) | fg
            }
            gp += 8
            pp += 4
        }
        ubyte j
        ubyte v
        ubyte sr
        for r in 0 to 7 {
            sys.set_irqd()
            set_vaddr(row, r, col0)
            i = 0
            while i < n {
                fl = c_fl[i]
                if (fl & 128) != 0 {
                    ; run of blank cells sharing the same background: blast it out
                    pp = pairs + ((i as uword) << 2)
                    v = @(pp)
                    j = i + 1
                    while j < n and j - i < 60 {
                        if c_fl[j] < 128
                            break
                        if @(pairs + ((j as uword) << 2)) != v
                            break
                        j++
                    }
                    fillv((j - i) << 2, v)
                    i = j
                } else {
                    pp = pairs + ((i as uword) << 2)
                    if (fl & $60) != 0 {
                        ; large character: one glyph pixel -> 2x2 pixels; this cell shows one quarter
                        sr = (vhalf << 2) + (r >> 1)
                        g = @(c_gl + ((i as uword) << 3) + sr)
                        if (fl & S_ITAL) != 0 and sr < 4
                            g >>= 1
                        if (fl & S_BOLD) != 0
                            g |= g >> 1
                        if (fl & S_UNDER) != 0 and sr == 7
                            g = $ff
                        if (fl & $40) != 0
                            g <<= 4
                        cx16.VERA_DATA0 = @(pp + (g >> 7) * 3)
                        cx16.VERA_DATA0 = @(pp + ((g >> 6) & 1) * 3)
                        cx16.VERA_DATA0 = @(pp + ((g >> 5) & 1) * 3)
                        cx16.VERA_DATA0 = @(pp + ((g >> 4) & 1) * 3)
                        i++
                        continue
                    }
                    gp = c_gl + ((i as uword) << 3) + r
                    g = @(gp)
                    if fl != 0 {
                        if (fl & S_ITAL) != 0 and r < 4
                            g >>= 1
                        if (fl & S_BOLD) != 0
                            g |= g >> 1
                        if (fl & S_UNDER) != 0 and r == 7
                            g = $ff
                    }
                    cx16.VERA_DATA0 = @(pp + (g >> 6))
                    cx16.VERA_DATA0 = @(pp + ((g >> 4) & 3))
                    cx16.VERA_DATA0 = @(pp + ((g >> 2) & 3))
                    cx16.VERA_DATA0 = @(pp + (g & 3))
                    i++
                }
            }
            sys.clear_irqd()
        }
    }

    ; copy 'pages' * 256 bytes from VERA port 0 to VERA port 1 (addresses/increments set by caller)
    asmsub vcopy_pages(ubyte pages @Y) clobbers(A,X,Y) {
        %asm {{
            ldx  #0
-           lda  cx16.VERA_DATA0
            sta  cx16.VERA_DATA1
            inx
            bne  -
            dey
            bne  -
            rts
        }}
    }

    asmsub fillv(ubyte count @X, ubyte value @A) clobbers(X) {
        %asm {{
            cpx  #0
            beq  +
-           sta  cx16.VERA_DATA0
            dex
            bne  -
+           rts
        }}
    }

    sub fetch_raw(ubyte font, ubyte code, uword dst) {
        uword va = FONT_VRAM + (font as uword) * 2048 + (code as uword) * 8
        sys.set_irqd()
        cx16.vaddr(1, va, 1, 1)
        cx16.VERA_CTRL = 1
        ubyte j
        for j in 0 to 7 {
            @(dst + j) = cx16.VERA_DATA1
        }
        cx16.VERA_CTRL = 0
        sys.clear_irqd()
    }

    ; draw text string (iso encoded) at cell position, clipped to the screen
    sub text(ubyte col, ubyte row, str s, ubyte sty, ubyte fg, ubyte bg) {
        ubyte n = 0
        ubyte c
        ubyte k = (bg << 4) | fg
        while s[n] != 0 and col + n < 80 {
            c = s[n]
            r_ch[n] = c
            r_sty[n] = sty
            r_col[n] = k
            n++
        }
        render_run(row, col, n)
    }

    sub fill(ubyte col, ubyte row, ubyte n, ubyte fg, ubyte bg) {
        ubyte i
        ubyte k = (bg << 4) | fg
        if n == 0
            return
        for i in 0 to n-1 {
            r_ch[i] = 32
            r_sty[i] = 0
            r_col[i] = k
        }
        render_run(row, col, n)
    }

    ; right-aligned decimal number helper into r_ arrays is in the view module
}
