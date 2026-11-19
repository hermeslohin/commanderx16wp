; theme.p8 - X16 Office themes, shared by X16 Write, X16 Sheets, X16 Files and X16 Calendar
; (the same file in every repository; keep the copies identical).
;
; A theme is a file on the SD card, X16THEME1.BIN .. X16THEME9.BIN (made by tools/mkthemes.py, the
; same script in every repository). Only the chosen theme is read, and almost all of it goes straight
; into VRAM: the 16 colours into the VERA palette, its glyphs into font slot 3 (codes 240..255) and
; Quill's three frames into the sprite data. Main RAM keeps only the role table rl[] (which colour
; each part of the screen uses), the desk pattern dk[] and the theme's name. The file is read into
; a buffer of the app's (vid.TBANK / vid.TBUF: 512 bytes of banked RAM that is idle meanwhile).
; Clicking Quill calls next(): the next theme is applied and remembered in X16THEME.CFG (one byte,
; the theme number), which every app reads at start, so a theme picked in one app is used by all.
; Without theme files the apps still work, in the built-in Sunset Arcade colours below.
;
; Theme file (472 bytes):
;   0  "X16T" + version 1 + 3 spare     24  palette, 16 x (lo, hi) as VERA stores it
;   8  name, 16 bytes iso, space-padded    56  rl[64]     120  dk[32]
;   152 16 glyphs for codes 240..255    280 Quill, 3 frames of 16x8 4bpp (64 bytes each)
;
; Colours keep their meaning in every theme: index 0 is ink, 1 is paper, 2 a red, 7 a yellow...
; (documents and spreadsheets store these indexes). doc_lo/doc_hi are the original colours that
; RTF/XLSX export writes, whatever the theme.
;
; Role values: a "pair" is (bg << 4) | fg (for buttons: face << 4 | glyph), a "char" is a screen
; code (32 = blank, 240..255 = theme glyph), anything else is one colour index.

%import syslib
%import diskio
%import vid

theme {
    %option ignore_unused

    const ubyte G_LCAP = 243            ; left end of a pill (fg = face, bg = background); every theme
    const ubyte G_RCAP = 244            ; right end of a pill        has these two at 243 and 244
    const ubyte S_THEME = vid.S_RAW | $30       ; style byte: raw glyph from font slot 3
    const uword SPR_VRAM = $8000        ; Quill, bank 1: $18000

    ; ---- roles: indexes into rl[] ----
    const ubyte R_DESK = 0              ; desk colour (behind the page / cards)
    const ubyte R_DESK_A = 1            ; desk pattern: dk[(col * A + row * B) & 31]
    const ubyte R_DESK_B = 2
    const ubyte R_BORDER = 3
    const ubyte R_TTL_CH = 4            ; title row 0: fill char, pair
    const ubyte R_TTL = 5
    const ubyte R_TTL_NAME = 6          ; pair: the app's name
    const ubyte R_TTL_TXT = 7           ; pair: file name, page count... on the title row
    const ubyte R_TTL_WARN = 8          ; fg on R_TTL_TXT's bg: "modified"
    const ubyte R_QUIT = 9              ; button pair: Quit
    const ubyte R_TOOL = 10             ; toolbar rows' colour
    const ubyte R_BTN = 11              ; button pairs: normal, on, disabled,
    const ubyte R_BTN_ON = 12
    const ubyte R_BTN_OFF = 13
    const ubyte R_BTN_1 = 14            ;   accents 1-4: New / Copy / Add (1), Open / Move (2),
    const ubyte R_BTN_2 = 15            ;   Save / Refresh / Sync (3), New folder / Today (4)
    const ubyte R_BTN_3 = 16
    const ubyte R_BTN_4 = 17
    const ubyte R_FIELD = 18            ; pair: a field on the toolbar (Write's font box)
    const ubyte R_FIELD_HI = 19         ; fg: a value in it
    const ubyte R_STRIP = 20            ; pair: Write's colour row (labels)
    const ubyte R_SW_T0 = 21            ; swatches, a char per cell (text colour 2 cells, highlight 2 cells):
    const ubyte R_SW_T1 = 22            ;   0 = a block of the colour; else that char (32 or a glyph) in the
    const ubyte R_SW_B0 = 23            ;   colour on the strip (in R_SW_INK where the colour is the
    const ubyte R_SW_B1 = 24            ;   strip's own)
    const ubyte R_SW_INK = 25
    const ubyte R_BAR = 26              ; pair: entry bar / path row (light)
    const ubyte R_BAR_DIM = 27          ; fg: hints on it
    const ubyte R_TAPE = 28             ; pair: Write's ruler, weekday and column header rows
    const ubyte R_TAPE_CAP = 29         ; colour of the ruler's end caps
    const ubyte R_TAPE_ALT = 30         ; pair: weekend headers
    const ubyte R_PAPER = 31            ; pair: page, cells, lists
    const ubyte R_PAPER_DIM = 32        ; colour: paper of another month / an inactive selection
    const ubyte R_MARG = 33             ; pair + chars: the cells either side of Write's page
    const ubyte R_MARG_L = 34
    const ubyte R_MARG_R = 35
    const ubyte R_SHADOW = 36           ; colour: shadow right of the page
    const ubyte R_PTOP_CH = 37          ; top edge of a page: char, pair, mask (the char is drawn
    const ubyte R_PTOP = 38             ;   where (col & mask) == 0, elsewhere blank), label pair
    const ubyte R_PTOP_MASK = 39
    const ubyte R_PTOP_LBL = 40
    const ubyte R_SEL = 41              ; pair: selection
    const ubyte R_SEL_DIM = 42          ; pair: selection in an inactive pane
    const ubyte R_HEAD_ON = 43          ; pairs: card headers, active / inactive
    const ubyte R_HEAD_OFF = 44
    const ubyte R_STAT = 45             ; pair: status bar row 29
    const ubyte R_STAT_LBL = 46         ; fg: labels on it ("Ln", "Sum")
    const ubyte R_STAT_HI = 47          ; fg: values / progress on it
    const ubyte R_SCROLL = 48           ; pair: scroll bar track and arrows
    const ubyte R_THUMB = 49            ; colour: scroll bar thumb
    const ubyte R_DLG = 50              ; pair: dialog body
    const ubyte R_DLG_TTL = 51          ; pair: dialog title bar
    const ubyte R_DLG_WARN = 52         ; pair: warning title bar
    const ubyte R_DLG_BTN = 53          ; pill pair (face << 4 | label)
    const ubyte R_DLG_EDGE = 54         ; colour: the dialog's top and bottom rows
    const ubyte R_FOOT = 55             ; pair: pane footer
    const ubyte R_HDR2 = 56             ; pair: Sheets' column headers
    const ubyte R_ROWHDR = 57           ; pair: Sheets' row headers
    const ubyte R_FBAR = 58             ; pair: Sheets' formula text
    const ubyte R_GRID = 59             ; colour: grid lines
    const ubyte R_CHIP_OK = 60          ; fg on R_TTL_TXT's bg: "ownCloud"

    ; Sunset Arcade, used until a theme file is read
    ubyte[64] rl = [
        0, 7, 13, 0,                                    ; desk, A, B, border
        240, $82, $07, $01, 10, $20,                    ; title row, Quit
        11, $c1, $70, $cb, $20, $80, $30, $70, $10, 6,  ; toolbar
        $01, 0, 0, 0, 0, 0,                             ; Write's colour row
        $f0, 11,                                        ; bar
        $70, 2, $80,                                    ; tape
        $10, 15, $00, 32, 32, 11, 240, $82, 0, $07,    ; paper, page edges
        $20, $f0, $20, $40,                             ; selection, card headers
        $01, 7, 7,                                      ; status bar
        $02, 2,                                         ; scroll bar
        $f0, $40, $21, $70, 0, $fb,                     ; dialogs, footer
        $b1, $0c, $01, 15, 13,                          ; Sheets
        0, 0, 0 ]
    ; desk pattern: (fg << 4) | glyph (0 = none, n = code 240 + n)
    ubyte[32] dk = [$c0,$c0,$c0,$c2,$c0,$c0,$c0,$c0, $c0,$c0,$c0,$c1,$c0,$c0,$c0,$c0,
                    $c0,$c0,$c0,$c0,$c0,$c0,$c1,$c0, $c0,$c0,$c0,$c0,$c0,$c0,$c0,$c0]
    ubyte cur                           ; theme number now shown (0 = built-in)
    ubyte tbank = vid.TBANK             ; where load() reads a theme file to (512 bytes; an app can
    uword tbuf = vid.TBUF               ;   point these elsewhere before init())
    str fname = iso:"X16THEME1.BIN"
    str cfgname = iso:"@:X16THEME.CFG"
    ; the status bar message after next(); the theme's name is read into it at msg + 7
    str msg = iso:"Theme: Sunset Arcade   "
    str tip = iso:"Click Quill: next theme"

    ; the original (C64-like) palette: what documents are saved with
    ubyte[16] doc_lo = [$00,$ff,$00,$fe,$4c,$c5,$0a,$e7,$85,$40,$77,$33,$77,$f6,$8f,$bb]
    ubyte[16] doc_hi = [$0,$f,$8,$a,$c,$0,$0,$e,$d,$6,$f,$3,$7,$8,$0,$b]

    const uword QUILL_X = 4
    const uword QUILL_Y = 29 * 8

    ubyte frames            ; frame counter
    ubyte hop               ; frames of cheering left
    ubyte shown_frame = 255
    ubyte shown_dy = 255

    ; after vid.gfx_init() and the app's icons: the theme from X16THEME.CFG (or the first one), Quill on
    sub init() {
        ubyte n = 1
        ubyte b = cx16.getrambank()
        cx16.rambank(tbank)
        if diskio.load_raw(&cfgname + 2, tbuf) == tbuf + 1
            n = @(tbuf)
        cx16.rambank(b)
        if not load(n)
            void load(1)
        frames = 0
        hop = 0
        place(0, 0)
    }

    ; the next theme file (after the last one, the first again); remembered for every app.
    ; false: there are no theme files. The caller shows msg and redraws the screen.
    sub next() -> bool {
        if load(cur + 1) or load(1) {
            if diskio.f_open_w(cfgname) {
                void diskio.f_write(&cur, 1)
                diskio.f_close_w()
            }
            return true
        }
        return false
    }

    ; reads X16THEME<n>.BIN (into the buffer tbuf in RAM bank tbank) and applies it
    sub load(ubyte n) -> bool {
        if n == 0 or n > 9
            return false
        fname[8] = iso:'0' + n
        ubyte b = cx16.getrambank()
        cx16.rambank(tbank)
        uword t = tbuf
        bool ok = diskio.load_raw(fname, t) == t + 472 and @(t) == iso:'X' and @(t + 3) == iso:'T'
        if ok {
            sys.memcopy(t + 8, &msg + 7, 16)
            sys.memcopy(t + 56, &rl, 64)
            sys.memcopy(t + 120, &dk, 32)
            vput($fa00, t + 24, 32)                 ; palette
            vput(vid.FONT_VRAM + 3 * 2048 + 240 * 8, t + 152, 128)
            vput(SPR_VRAM, t + 280, 192)            ; Quill
            cur = n
            cx16.VERA_DC_BORDER = rl[R_BORDER]
        }
        cx16.rambank(b)
        return ok
    }

    ; n bytes from src to VRAM bank 1 at a
    sub vput(uword a, uword src, ubyte n) {
        sys.set_irqd()
        cx16.vaddr(1, a, 0, 1)
        repeat n {
            cx16.VERA_DATA0 = @(src)
            src++
        }
        sys.clear_irqd()
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
        if cur != 0
            cx16.VERA_DATA0 = $0c               ; z: in front of layer 0
        else
            cx16.VERA_DATA0 = 0                 ; no theme file: no Quill
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

    ; a click on Quill (row 29, columns 0-1)?
    sub on_quill(ubyte cx, ubyte cy) -> bool {
        return cy == 29 and cx < 2
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

    ; n cells of the title row's fill
    sub stripes(ubyte col, ubyte row, ubyte n) {
        ubyte i
        if n == 0
            return
        for i in 0 to n - 1 {
            vid.r_ch[i] = rl[R_TTL_CH]
            vid.r_sty[i] = 0
            if rl[R_TTL_CH] >= 240
                vid.r_sty[i] = S_THEME
            vid.r_col[i] = rl[R_TTL]
        }
        vid.render_run(row, col, n)
    }

    ; desk cells for columns col.. of (virtual) row into vid.r_ch/r_sty/r_col[0..n-1]
    sub desk_fill(ubyte col, ubyte row, ubyte n) {
        ubyte i
        ubyte e
        ubyte h = col * rl[R_DESK_A] + row * rl[R_DESK_B]
        ubyte bg = rl[R_DESK] << 4
        if n == 0
            return
        for i in 0 to n - 1 {
            e = dk[h & 31]
            vid.r_ch[i] = 32
            vid.r_sty[i] = 0
            if e & 15 != 0 {
                vid.r_ch[i] = 240 + (e & 15)
                vid.r_sty[i] = S_THEME
            }
            vid.r_col[i] = bg | (e >> 4)
            h += rl[R_DESK_A]
        }
    }

    ; n cells of desk
    sub desk(ubyte col, ubyte row, ubyte n) {
        desk_fill(col, row, n)
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
