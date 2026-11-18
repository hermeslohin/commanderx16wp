; theme.p8 - X16 Office "Sunset Arcade" theme, shared by X16 Write, X16 Sheets, X16 Files and
; X16 Calendar (the same file in every repository; keep the copies identical).
;
; * The palette: vid.pal_lo/pal_hi hold the Sunset colours. Every index keeps roughly its old meaning
;   (red is hot pink, blue is a brighter blue, ...), so documents still look right on screen.
;   doc_lo/doc_hi are the original colours: RTF/XLSX export writes those, so a saved document keeps
;   the colours it always had.
; * Theme glyphs in font slot 3, codes 240..244 (the toolbar icons use codes 0..63 of that slot):
;   title bar stripes, desk stars, pill caps for buttons.
; * "Quill", a little pencil, is hardware sprite 1 (16x8, 4bpp, 3 frames at VRAM $18000, free in all
;   four apps). It sits at the left end of the status bar, blinks now and then, and hops when cheer()
;   is called (after a save, a copy, a sync...). tick() animates it: call it once per frame.
;
; Colour roles (indexes are the vid.C_* names):
;   desk / empty space     C_BLACK (#213) with stars (desk())
;   title row 0            stripes(); app name YELLOW bold on BLACK; other text WHITE on BLACK; [X] BLACK on RED
;   toolbar rows           C_DGRAY (#326); buttons: pills (pill()) or icon cells, face GRAY (#659) with
;                          WHITE glyphs; file buttons RED/ORANGE/CYAN faces; "on" toggles BLACK on YELLOW
;   page / list / cells    C_WHITE (cream #FED) with C_BLACK ink; folders BLUE bold
;   selection              BLACK on RED (pink bar)
;   column headers         BLACK on YELLOW; path / info rows BLACK on LGRAY (#CBF)
;   status bar row 29      WHITE on BLACK, text from column 3 (Quill is in columns 0-1); errors RED
;   dialogs                body LGRAY, title bar PURPLE (BLACK text) or RED for warnings (WHITE text),
;                          buttons BLACK on YELLOW
;   scroll bars            track BLACK, thumb RED

%import syslib
%import vid

theme {
    %option ignore_unused

    const ubyte G_STRIPE = 240          ; pink over orange, fading down (fg RED, bg ORANGE)
    const ubyte G_STAR = 241            ; one dot
    const ubyte G_STAR2 = 242           ; a small twinkle
    const ubyte G_LCAP = 243            ; left end of a pill (fg = face, bg = background)
    const ubyte G_RCAP = 244            ; right end of a pill
    const ubyte NGLYPHS = 5
    const ubyte S_THEME = vid.S_RAW | $30       ; style byte: raw glyph from font slot 3

    ; the original (C64-like) palette: what documents are saved with
    ubyte[16] doc_lo = [$00,$ff,$00,$fe,$4c,$c5,$0a,$e7,$85,$40,$77,$33,$77,$f6,$8f,$bb]
    ubyte[16] doc_hi = [$0,$f,$8,$a,$c,$0,$0,$e,$d,$6,$f,$3,$7,$8,$0,$b]

    ubyte[NGLYPHS * 8] glyphs = [
        $ff, $ff, $ff, $dd, $aa, $44, $00, $00,     ; G_STRIPE
        $00, $00, $00, $08, $00, $00, $00, $00,     ; G_STAR
        $00, $10, $10, $7c, $10, $10, $00, $00,     ; G_STAR2
        $0f, $3f, $7f, $7f, $7f, $7f, $3f, $0f,     ; G_LCAP
        $f0, $fc, $fe, $fe, $fe, $fe, $fc, $f0      ; G_RCAP
    ]

    ; Quill: 16x8 pixels, 4bpp (left pixel in the high nibble), colour 0 = transparent.
    ; a = LRED eraser, f = LGRAY ferrule, 7 = YELLOW body, b = DGRAY eyes, 2 = RED smile,
    ; 1 = cream wood, c = GRAY lead
    const uword SPR_VRAM = $8000        ; bank 1: $18000
    ubyte[3 * 64] quill = [
        ; frame 0: looking happy
        $0a, $af, $77, $77, $77, $77, $10, $00,
        $aa, $af, $77, $77, $77, $77, $11, $00,
        $aa, $af, $77, $b7, $7b, $77, $11, $00,
        $aa, $af, $77, $b7, $7b, $77, $11, $c0,
        $aa, $af, $77, $77, $77, $77, $11, $c0,
        $aa, $af, $72, $77, $77, $27, $11, $00,
        $aa, $af, $77, $22, $22, $77, $11, $00,
        $0a, $af, $77, $77, $77, $77, $10, $00,
        ; frame 1: blink
        $0a, $af, $77, $77, $77, $77, $10, $00,
        $aa, $af, $77, $77, $77, $77, $11, $00,
        $aa, $af, $77, $77, $77, $77, $11, $00,
        $aa, $af, $7b, $b7, $7b, $b7, $11, $c0,
        $aa, $af, $77, $77, $77, $77, $11, $c0,
        $aa, $af, $72, $77, $77, $27, $11, $00,
        $aa, $af, $77, $22, $22, $77, $11, $00,
        $0a, $af, $77, $77, $77, $77, $10, $00,
        ; frame 2: cheering (eyes ^ ^, big smile)
        $0a, $af, $77, $77, $77, $77, $10, $00,
        $aa, $af, $77, $b7, $7b, $77, $11, $00,
        $aa, $af, $7b, $7b, $b7, $b7, $11, $00,
        $aa, $af, $77, $77, $77, $77, $11, $c0,
        $aa, $af, $72, $77, $77, $27, $11, $c0,
        $aa, $af, $72, $22, $22, $27, $11, $00,
        $aa, $af, $77, $22, $22, $77, $11, $00,
        $0a, $af, $77, $77, $77, $77, $10, $00
    ]

    const uword QUILL_X = 4
    const uword QUILL_Y = 29 * 8

    ubyte frames            ; frame counter
    ubyte hop               ; frames of cheering left
    ubyte shown_frame = 255
    ubyte shown_dy = 255

    ; after vid.gfx_init(): glyphs into font slot 3, Quill into VRAM, sprite 1 on
    sub init() {
        ubyte i
        sys.set_irqd()
        cx16.vaddr(1, vid.FONT_VRAM + 3 * 2048 + (G_STRIPE as uword) * 8, 0, 1)
        for i in 0 to NGLYPHS * 8 - 1
            cx16.VERA_DATA0 = glyphs[i]
        cx16.vaddr(1, SPR_VRAM, 0, 1)
        for i in 0 to 3 * 64 - 1
            cx16.VERA_DATA0 = quill[i]
        sys.clear_irqd()
        cx16.VERA_DC_BORDER = vid.C_BLACK
        frames = 0
        hop = 0
        shown_frame = 255
        shown_dy = 255
        place(0, 0)
    }

    ; sprite 1 attributes: frame f, raised by dy pixels
    sub place(ubyte f, ubyte dy) {
        if f == shown_frame and dy == shown_dy
            return
        shown_frame = f
        shown_dy = dy
        uword a = $0c00 + (f as uword) * 2         ; ($18000 + f * 64) >> 5
        uword y = QUILL_Y - dy
        sys.set_irqd()
        cx16.vaddr(1, $fc08, 0, 1)
        cx16.VERA_DATA0 = lsb(a)
        cx16.VERA_DATA0 = msb(a) & 15          ; bit 7 = 0: 4bpp
        cx16.VERA_DATA0 = lsb(QUILL_X)
        cx16.VERA_DATA0 = msb(QUILL_X)
        cx16.VERA_DATA0 = lsb(y)
        cx16.VERA_DATA0 = msb(y)
        cx16.VERA_DATA0 = $0c                   ; z = in front of layer 0
        cx16.VERA_DATA0 = $10                   ; 8 high, 16 wide, palette offset 0
        sys.clear_irqd()
    }

    ; once per frame
    sub tick() {
        frames++
        if hop != 0 {
            hop--
            ubyte dy = 0
            if hop & 8 != 0
                dy = 2
            else if hop & 4 != 0
                dy = 1
            place(2, dy)
            return
        }
        ; blink for 6 frames every 256
        if frames < 6
            place(1, 0)
        else
            place(0, 0)
    }

    ; something went well: Quill hops twice
    sub cheer() {
        hop = 32
    }

    ; before leaving graphics mode
    sub off() {
        sys.set_irqd()
        cx16.vaddr(1, $fc0e, 0, 0)
        cx16.VERA_DATA0 = 0                     ; z = 0: sprite 1 disabled
        sys.clear_irqd()
        shown_frame = 255
    }

    ; ---------------- drawing ----------------

    ; n cells of title bar stripes
    sub stripes(ubyte col, ubyte row, ubyte n) {
        ubyte i
        if n == 0
            return
        for i in 0 to n - 1 {
            vid.r_ch[i] = G_STRIPE
            vid.r_sty[i] = S_THEME
            vid.r_col[i] = (vid.C_ORANGE << 4) | vid.C_RED
        }
        vid.render_run(row, col, n)
    }

    ; n cells of starry desk (the pattern depends on the position, so redraws match)
    sub desk(ubyte col, ubyte row, ubyte n) {
        ubyte i
        ubyte h
        if n == 0
            return
        for i in 0 to n - 1 {
            h = ((col + i) * 7 + row * 13) & 31
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            vid.r_col[i] = (vid.C_BLACK << 4) | vid.C_GRAY
            if h == 3 {
                vid.r_ch[i] = G_STAR2
                vid.r_sty[i] = S_THEME
            } else if h == 11 or h == 22 {
                vid.r_ch[i] = G_STAR
                vid.r_sty[i] = S_THEME
            }
        }
        vid.render_run(row, col, n)
    }

    ; one pill cap cell (g = G_LCAP / G_RCAP)
    sub cap(ubyte col, ubyte row, ubyte g, ubyte face, ubyte bg) {
        vid.r_ch[0] = g
        vid.r_sty[0] = S_THEME
        vid.r_col[0] = (bg << 4) | face
        vid.render_run(row, col, 1)
    }

    ; a pill button: cap, label (fg on face), cap; uses slen(label) + 2 cells
    sub pill(ubyte col, ubyte row, uword label, ubyte fg, ubyte face, ubyte bg) {
        ubyte n = 0
        vid.r_ch[0] = G_LCAP
        vid.r_sty[0] = S_THEME
        vid.r_col[0] = (bg << 4) | face
        while @(label + n) != 0 and col + n < 78 {
            vid.r_ch[n + 1] = @(label + n)
            vid.r_sty[n + 1] = 0
            vid.r_col[n + 1] = (face << 4) | fg
            n++
        }
        vid.r_ch[n + 1] = G_RCAP
        vid.r_sty[n + 1] = S_THEME
        vid.r_col[n + 1] = (bg << 4) | face
        vid.render_run(row, col, n + 2)
    }
}
