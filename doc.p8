; doc.p8 - document model: lines in banked RAM, paragraphs with soft word wrap, pages, editing, clipboard.

%import syslib
%import diskio
%import vmtab
%import tblx
%import pix

doc {
    %option ignore_unused

    const ubyte COLS = 64
    const ubyte PLINES = 54
    const uword MAXLINES = vmt.MAXLINES ; 8192 lines (with X16WPVM.BIN; without it: see maxlines)
    const ubyte MAXPAGES = vmt.MAXPAGES
    const ubyte MAXIND = 6
    const uword SBMAX = 640
    const ubyte CLIPBANK = 63
    const uword CLIPMAX = 2700
    const ubyte VMBANK = vmt.VMBANK

    ; line slot layout (256 bytes, banked RAM, 32 slots per bank)
    const ubyte O_CH = 0
    const ubyte O_STY = 80
    const ubyte O_COL = 160
    const ubyte O_LEN = 240
    const ubyte O_FLG = 241
    const ubyte O_AL = 242
    const ubyte O_IND = 243
    const ubyte O_LIST = 244
    const ubyte O_TBL = 245         ; table row: number of columns (1..8) | TB_HEAD on a table's first row
    const ubyte TB_HEAD = 16        ; (tblx.p8 / x16wptb.p8; 0 = normal line)
    const ubyte O_PIC = 246         ; picture line: picture id 1..15 (pix.p8 / x16wppi.p8; 0 = no picture)
    const ubyte O_PROW = 247        ; picture line: its row in the picture (byte 0: the picture's line count)
    const ubyte F_SOFT = 1
    const ubyte F_HARD = 2
    const ubyte F_TALL = 4          ; the line holds 18/24 pt (2x2 cell) characters: it is 2 screen rows high
    const ubyte F_TALL3 = 8         ; the line holds 36 pt (3x3 cell) characters: it is 3 screen rows high
    ; character size: style bits 6-7. 0 = 12 pt (1 cell), SZ_LARGE = 24 pt (2x2 cells),
    ; $80 = 18 pt (2x2 cells, drawn 1.5x), $C0 = 36 pt (3x3 cells)
    const ubyte SZ_LARGE = $40
    const ubyte SZ_MASK = $c0
    ubyte[4] SZ_CODE = [0, $80, $40, $c0]       ; 12, 18, 24, 36 pt (the font menu's order)

    ; Line order: 4 bytes for every line in RAM banks 1..4 (ent()): its slot number, a copy of its O_FLG
    ; and, on a picture's first line, the picture's line count. So paginating and finding paragraphs
    ; never needs the lines' text, which may be in a swap file.
    ; Line slots are paged (vmtab.p8): slot_ptr() finds or brings in the slot's section (32 slots = one
    ; 8 KB bank). X16WPVM.BIN (bank 58) swaps sections to the SD card; without it the document is as long
    ; as the frame banks hold (736 lines with 512 KB, 3328 with 2 MB). The first line of every page
    ; (pf()), the map of used slots and the paging tables are in bank 58 too.
    uword maxlines
    bool vm_on                      ; X16WPVM.BIN is there and swap files work
    bool pg_over                    ; repaginate: the text needs more than MAXPAGES pages
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
    ubyte[54] pc_row                ; (line - first line of the page) * 4 + sub-row, 255 = empty
    ubyte pc_page = 255

    ; ---------------- paging (vmtab.p8, x16wpvm.p8) ----------------
    extsub @bank VMBANK $A000 = vm_init() clobbers(A, X, Y)
    extsub @bank VMBANK $A003 = vm_setup(uword xfer @R0) clobbers(X, Y) -> bool @A
    extsub @bank VMBANK $A006 = vm_fault(ubyte sec @R0) clobbers(X, Y) -> ubyte @A
    extsub @bank VMBANK $A009 = vm_quit() clobbers(A, X, Y)

    ; at start, before init_doc()
    sub vm_load() {
        cx16.rambank(VMBANK)
        if diskio.load_raw(iso:"X16WPVM.BIN", $a000) != 0 {
            vm_init()
            vm_on = vm_setup(&vm_xfer)
        }
    }

    ; at the end: delete the swap files
    sub vm_end() {
        if vm_on
            vm_quit()
    }

    ; 8 KB between RAM bank r0L and the file X16WPVM.BIN has opened (r0H = 0: read into the bank, 1: write
    ; the bank). The library calls this with a plain JSR from bank 58 and gets bank 58 back.
    ; Out: r1L = 0 if all 8192 bytes went through.
    asmsub vm_xfer() clobbers(A, X, Y) {
        %asm {{
            lda  cx16.r0L
            sta  $00
            stz  cx16.r3
            lda  #$a0
            sta  cx16.r3+1
_loop       ldx  cx16.r3
            ldy  cx16.r3+1
            lda  cx16.r0H
            bne  _wr
            lda  #128
            clc
            jsr  cx16.MACPTR
            bra  _moved
_wr         lda  #128
            clc
            jsr  cx16.MCIOUT
_moved      bcs  _end
            txa
            clc
            adc  cx16.r3
            sta  cx16.r3
            tya
            adc  cx16.r3+1
            sta  cx16.r3+1
            jsr  cbm.READST
            bne  _end
            lda  cx16.r3+1
            cmp  #$c0
            bcc  _loop
_end        ldx  #1
            lda  cx16.r3+1
            cmp  #$c0
            bne  +
            ldx  #0
+           stx  cx16.r1L
            lda  #p8c_VMBANK
            sta  $00
            rts
        }}
    }

    ; empty document: no slots used, the frame banks hold sections 0, 1, 2, ... (nothing swapped out)
    sub vm_reset() {
        cx16.rambank(VMBANK)
        sys.memset(vmt.TABLES, vmt.STATEND - vmt.TABLES, 0)
        uword nb = cx16.numbanks()
        if nb > 145
            nb = 145                        ; banks 145.. are for pictures (x16wppi.p8)
        cx16.r0L = lsb(nb)
        %asm {{
            ldy  #p8b_vmt.p8c_FBANK0        ; y = frame bank, x = the section it holds
            ldx  #0
-           tya
            sta  p8b_vmt.p8v_secfr,x
            txa
            sta  p8b_vmt.p8v_frsec,y
            lda  #p8b_vmt.p8c_F_FRAME
            sta  p8b_vmt.p8v_fruse,y
            inx
            iny
            cpy  #p8b_vmt.p8c_FBANK1+1
            bne  +
            ldy  #64
+           cpy  cx16.r0L
            bcc  -
            stx  cx16.r0H
        }}
        maxlines = MAXLINES
        if not vm_on
            maxlines = mkword(cx16.r0H, 0) >> 3     ; 32 lines a frame
    }

    ; ---------------- slots ----------------
    ; address of line slot `slot`, its bank mapped (read back from the swap file if it was swapped out).
    ; use = vmt.F_REF to read it, vmt.F_REF | vmt.F_DIRTY to change it. Valid until the next slot_ptr().
    asmsub slot_ptr(uword slot @AY, ubyte use @X) -> uword @AY {
        %asm {{
            stx  P8ZP_SCRATCH_REG
            sta  P8ZP_SCRATCH_W1
            tya                     ; section = slot / 32
            asl  a
            asl  a
            asl  a
            sta  P8ZP_SCRATCH_B1
            lda  P8ZP_SCRATCH_W1
            lsr  a
            lsr  a
            lsr  a
            lsr  a
            lsr  a
            ora  P8ZP_SCRATCH_B1
            tax
            lda  #p8c_VMBANK
            sta  $00
            lda  p8b_vmt.p8v_secfr,x
            bne  _in
            lda  p8v_vm_on          ; no X16WPVM.BIN: every line is in RAM, only a stray slot number
            bne  +                  ; (an unused line order entry) gets here
            lda  #p8b_vmt.p8c_FBANK0
            bra  _in
+           lda  P8ZP_SCRATCH_W1    ; not in RAM: X16WPVM.BIN brings it in (its code uses the scratch bytes)
            pha
            lda  P8ZP_SCRATCH_REG
            pha
            stx  cx16.r0L
            jsr  cx16.JSRFAR
            .word $a006             ; vm_fault
            .byte p8c_VMBANK
            tax
            pla
            sta  P8ZP_SCRATCH_REG
            pla
            sta  P8ZP_SCRATCH_W1
            txa
_in         tax                     ; x = the frame bank
            lda  p8b_vmt.p8v_fruse,x
            ora  P8ZP_SCRATCH_REG
            sta  p8b_vmt.p8v_fruse,x
            stx  $00
            lda  P8ZP_SCRATCH_W1    ; $a000 + (slot & 31) * 256
            and  #31
            ora  #$a0
            tay
            lda  #0
            rts
        }}
    }

    ; a free slot, near slot `hint` if possible (lines next to each other stay in the same section);
    ; $ffff if there is none. The map has a bit per slot (bank 58, vmt.SLOTMAP).
    asmsub alloc_slot(uword hint @R0) clobbers(X) -> uword @AY {
        %asm {{
            lda  #p8c_VMBANK
            sta  $00
            lda  p8v_maxlines       ; r1 = bytes in the map, r2 = bytes left to look at
            sta  cx16.r1
            lda  p8v_maxlines+1
            ldx  #3
-           lsr  a
            ror  cx16.r1
            lsr  cx16.r0+1
            ror  cx16.r0
            dex
            bne  -
            sta  cx16.r1+1
            sta  cx16.r2+1
            lda  cx16.r1
            sta  cx16.r2
            lda  cx16.r0+1          ; start at byte hint / 8 (0 if that is past the end)
            cmp  cx16.r1+1
            bcc  _loop
            bne  _wrap
            lda  cx16.r0
            cmp  cx16.r1
            bcc  _loop
_wrap       stz  cx16.r0
            stz  cx16.r0+1
_loop       lda  cx16.r2
            ora  cx16.r2+1
            beq  _none
            clc
            lda  cx16.r0
            adc  #<p8b_vmt.p8c_SLOTMAP
            sta  cx16.r3
            lda  cx16.r0+1
            adc  #>p8b_vmt.p8c_SLOTMAP
            sta  cx16.r3+1
            lda  (cx16.r3)
            cmp  #255
            bne  _found
            lda  cx16.r2
            bne  +
            dec  cx16.r2+1
+           dec  cx16.r2
            inc  cx16.r0
            bne  +
            inc  cx16.r0+1
+           lda  cx16.r0
            cmp  cx16.r1
            bne  _loop
            lda  cx16.r0+1
            cmp  cx16.r1+1
            bne  _loop
            bra  _wrap
_none       lda  #$ff
            tay
            rts
_found      ldx  #0                 ; lowest clear bit: x = its number, P8ZP_SCRATCH_B1 = its mask
            ldy  #1
-           lsr  a
            bcc  +
            inx
            pha
            tya
            asl  a
            tay
            pla
            bra  -
+           tya
            ora  (cx16.r3)
            sta  (cx16.r3)
            ldy  #3                 ; slot = byte * 8 + bit
-           asl  cx16.r0
            rol  cx16.r0+1
            dey
            bne  -
            txa
            ora  cx16.r0
            ldy  cx16.r0+1
            rts
        }}
    }

    asmsub free_slot(uword s @AY) clobbers(A, X, Y) {
        %asm {{
            tax
            and  #7
            sta  P8ZP_SCRATCH_B1
            txa
            sty  P8ZP_SCRATCH_W1+1
            ldx  #3
-           lsr  P8ZP_SCRATCH_W1+1
            ror  a
            dex
            bne  -
            clc
            adc  #<p8b_vmt.p8c_SLOTMAP
            sta  P8ZP_SCRATCH_W1
            lda  P8ZP_SCRATCH_W1+1
            adc  #>p8b_vmt.p8c_SLOTMAP
            sta  P8ZP_SCRATCH_W1+1
            lda  #p8c_VMBANK
            sta  $00
            lda  #1
            ldx  P8ZP_SCRATCH_B1
            beq  +
-           asl  a
            dex
            bne  -
+           eor  #255
            and  (P8ZP_SCRATCH_W1)
            sta  (P8ZP_SCRATCH_W1)
            rts
        }}
    }

    ; line idx's 4-byte entry in the line order (its bank mapped)
    asmsub ent(uword idx @AY) clobbers(X) -> uword @AY {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            tya
            lsr  a
            lsr  a
            lsr  a
            clc
            adc  #p8b_vmt.p8c_OBANK
            sta  $00
            tya                     ; ((idx & 2047) << 2) + $a000
            and  #7
            asl  P8ZP_SCRATCH_B1
            rol  a
            asl  P8ZP_SCRATCH_B1
            rol  a
            ora  #$a0
            tay
            lda  P8ZP_SCRATCH_B1
            rts
        }}
    }

    sub oslot(uword idx) -> uword {
        return peekw(ent(idx))
    }

    ; line idx's slot was changed at p: copy its flags (and picture line count) into its entry
    sub sync_ent(uword idx, uword p) {
        cx16.r10 = p
        %asm {{
            ldy  #p8c_O_FLG
            lda  (cx16.r10),y
            sta  cx16.r11L
            stz  cx16.r11H
            ldy  #p8c_O_PIC
            lda  (cx16.r10),y
            beq  +
            iny                     ; O_PROW
            lda  (cx16.r10),y
            bne  +
            lda  (cx16.r10)         ; a picture's first line: its line count
            sta  cx16.r11H
+
        }}
        pokew(ent(idx) + 2, cx16.r11)
    }

    sub ld(uword idx, uword dst) {
        sys.memcopy(slot_ptr(oslot(idx), vmt.F_REF), dst, 248)
    }

    sub st(uword idx, uword src) {
        uword p = slot_ptr(oslot(idx), vmt.F_REF | vmt.F_DIRTY)
        sys.memcopy(src, p, 248)
        sync_ent(idx, p)
    }

    ; n bytes between RAM bank b at a and main RAM at d (out: main -> bank), for x16wppi.p8, which
    ; can't switch banks itself; the range must not cross the end of the bank (out: 0 or 1)
    sub bxfer(ubyte b, uword a, uword d, uword n, ubyte out) {
        ubyte ob = cx16.getrambank()
        cx16.rambank(b)
        if out != 0
            sys.memcopy(d, a, n)
        else
            sys.memcopy(a, d, n)
        cx16.rambank(ob)
    }

    sub meta(uword idx, ubyte off) -> ubyte {
        if off == O_FLG
            return @(ent(idx) + 2)          ; from the line order: no need to bring the line in
        return @(slot_ptr(oslot(idx), vmt.F_REF) + off)
    }

    sub setmeta(uword idx, ubyte off, ubyte v) {
        uword p = slot_ptr(oslot(idx), vmt.F_REF | vmt.F_DIRTY)
        @(p + off) = v
        sync_ent(idx, p)
    }

    ; line order entries idx.. one place up (up: room for a line at idx), or idx + 1.. one place down
    ; (over idx); entry by entry, from bank to bank
    sub oshift(uword idx, bool up) {
        cx16.r5 = nlines - idx
        cx16.r4 = ent(nlines)
        if not up {
            cx16.r5--
            cx16.r4 = ent(idx)
        }
        cx16.r6L = cx16.getrambank()
        cx16.r6H = up as ubyte
        %asm {{
            ; r4 = destination entry (bank r6L), r5 = entries to move, r6H = up
_loop       lda  cx16.r5
            ora  cx16.r5+1
            beq  _done
            ldx  cx16.r6L
            lda  cx16.r6H
            beq  _down
            sec                     ; up: source = destination - 4
            lda  cx16.r4
            sbc  #4
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r4+1
            sbc  #0
            cmp  #$a0
            bcs  _src
            lda  #$bf
            dex
            bra  _src
_down       clc                     ; down: source = destination + 4
            lda  cx16.r4
            adc  #4
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r4+1
            adc  #0
            cmp  #$c0
            bcc  _src
            lda  #$a0
            inx
_src        sta  P8ZP_SCRATCH_W1+1
            ldy  #3
-           stx  $00
            lda  (P8ZP_SCRATCH_W1),y
            sta  P8ZP_SCRATCH_B1
            lda  cx16.r6L
            sta  $00
            lda  P8ZP_SCRATCH_B1
            sta  (cx16.r4),y
            dey
            bpl  -
            lda  P8ZP_SCRATCH_W1    ; the source is the next destination
            sta  cx16.r4
            lda  P8ZP_SCRATCH_W1+1
            sta  cx16.r4+1
            stx  cx16.r6L
            lda  cx16.r5
            bne  +
            dec  cx16.r5+1
+           dec  cx16.r5
            bra  _loop
_done       rts                     ; (a sub ending in %asm gets no rts of its own)
        }}
    }

    sub insert_blank(uword idx) -> bool {
        cx16.rambank(VMBANK)
        if nlines >= maxlines or pg_over or vmt.stat != 0 {
            full_error = true
            return false
        }
        uword s = 0
        if idx != 0
            s = oslot(idx - 1)
        s = alloc_slot(s)
        if s == $ffff {
            full_error = true
            return false
        }
        oshift(idx, true)
        uword e = ent(idx)
        pokew(e, s)
        pokew(e + 2, 0)
        nlines++
        sys.memset(LBV, 256, 0)
        sys.memcopy(LBV, slot_ptr(s, vmt.F_REF | vmt.F_DIRTY), 248)
        return true
    }

    sub delete_line(uword idx) {
        ubyte ob = cx16.getrambank()
        free_slot(oslot(idx))
        oshift(idx, false)
        cx16.rambank(ob)
        nlines--
    }

    sub init_doc() {
        vm_reset()
        nlines = 0
        pg_over = false
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

    ; first line of page p
    sub pf(ubyte p) -> uword {
        cx16.rambank(VMBANK)
        return peekw(vmt.PF + (p as uword << 1))
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
        ubyte w = 0
        ubyte i
        if n == 0
            return 0
        for i in 0 to n - 1
            w += sz_w(@(b + O_STY + i))
        return w
    }

    ; cells (wide and high) of a character with style s
    sub sz_w(ubyte s) -> ubyte {
        if s & SZ_MASK == 0
            return 1
        if s & SZ_MASK == SZ_MASK
            return 3
        return 2
    }

    ; screen rows of a line with flags f, and the flags for h rows
    sub line_h(ubyte f) -> ubyte {
        if f & F_TALL3 != 0
            return 3
        if f & F_TALL != 0
            return 2
        return 1
    }

    sub tall_flag(ubyte h) -> ubyte {
        if h == 3
            return F_TALL3
        if h == 2
            return F_TALL
        return 0
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
        ubyte need
        uword e
        pg_over = false
        cx16.rambank(VMBANK)
        pokew(vmt.PF, 0)
        for l in 0 to nlines - 1 {
            e = ent(l)
            f = @(e + 2)
            h = line_h(f)
            need = h
            if @(e + 3) != 0
                need = @(e + 3)                     ; a picture's first line: keep it on one page
            if l > 0 {
                if (f & F_HARD) != 0 or rows + need > PLINES {
                    if p < MAXPAGES - 1 {
                        p++
                        cx16.rambank(VMBANK)
                        pokew(vmt.PF + (p as uword << 1), l)
                        rows = 0
                    } else
                        pg_over = true          ; more than MAXPAGES pages: no more lines
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
        while p > 0 and pf(p) > l
            p--
        return p
    }

    sub build_pagemap(ubyte p) {
        if pc_page == p
            return
        uword endl = nlines
        if p + 1 < npages and pf(p + 1) < endl
            endl = pf(p + 1)
        ubyte r = 0
        ubyte n = 0
        uword l = pf(p)
        ubyte h
        ubyte k
        while l < endl and r < PLINES {
            h = line_h(meta(l, O_FLG))
            k = 0
            while k < h and r < PLINES {
                pc_row[r] = (n << 2) | k
                r++
                k++
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
        ubyte n = lsb(l - pf(p)) << 2
        ubyte r = 0
        while r < PLINES - 1 and pc_row[r] != n
            r++
        return (p as uword) * 55 + 1 + r
    }

    ; returns 0=line (cx16.r0=line, cx16.r1L=sub-row 0..2), 1=blank paper, 2=page top separator (r0=page), 3=beyond
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
        cx16.r0 = pf(pp) + (e >> 2)
        cx16.r1L = e & 3
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
                step = sz_w(@(sbsty + pos + fit))
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
            tallb = 1
            if take != 0 {
                for i in 0 to take - 1 {
                    step = sz_w(@(sbsty + pos + i))
                    if step > tallb
                        tallb = step
                }
            }
            tallb = tall_flag(tallb)
            oldtall = 0
            if cur <= avail
                oldtall = meta(cur, O_FLG) & (F_TALL | F_TALL3)
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
        if off + n < cnt
            sb_move(off + n, off, cnt - off - n)
    }

    ; n characters of the paragraph stream from offset a to offset b (the ranges may overlap)
    sub sb_move(uword a, uword b, uword n) {
        cx16.memory_copy(sbch + a, sbch + b, n)
        cx16.memory_copy(sbsty + a, sbsty + b, n)
        cx16.memory_copy(sbcol + a, sbcol + b, n)
    }

    ; ---------------- typing attributes ----------------
    sub sync_typing() {
        ubyte ln = meta(curline, O_LEN)
        if ln == 0
            return
        uword p = slot_ptr(oslot(curline), vmt.F_REF)
        ubyte c = curcol
        if c > 0
            c--
        if c >= ln
            c = ln - 1
        if @(p + O_STY + c) & 8 != 0
            return                  ; a table border glyph
        tsty = @(p + O_STY + c) & $f7
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
        sb_move(off, off + n, cnt - off)
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
        ubyte cwn = sz_w(tsty)
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
            if cwn > line_h(LB[O_FLG]) {
                LB[O_FLG] = (LB[O_FLG] & ~(F_TALL | F_TALL3)) | tall_flag(cwn)
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
        if npages >= MAXPAGES - 1 or meta(curline, O_TBL) != 0 or meta(curline, O_PIC) != 0
            return
        newline()
        if full_error
            return                          ; no room for the new line: no break either
        setmeta(curline, O_FLG, meta(curline, O_FLG) | F_HARD)
        need_repag = true
        mark_from(curline - 1)
    }

    sub delete_selection() {
        if pix.delsel()
            return
        if tblx.delsel()
            return
        delsel_plain()
    }

    ; delete_selection without tables (x16wptb.p8 calls this for the parts outside tables)
    sub delsel_plain() {
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
    ; kind: 0 toggle style bit(s), 1 font, 2 text colour, 3 highlight colour, 4 size (val = SZ_CODE[..]: 0 12 pt, $80 18 pt, $40 24 pt, $c0 36 pt)
    ; line l into LB, and the part of it in the (normalised) selection: characters sp_a .. sp_b - 1
    ubyte sp_a
    ubyte sp_b
    sub sel_span(uword l) {
        ld(l, LB)
        sp_a = 0
        sp_b = LB[O_LEN]
        if l == sn_l1
            sp_a = sn_c1
        if l == sn_l2 and sn_c2 < sp_b
            sp_b = sn_c2
    }

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
            tsty = (tsty & ~SZ_MASK) | val
        if not sel_active
            return
        sel_norm()
        uword l
        ubyte i
        bool allset = true
        if kind == 0 {
            for l in sn_l1 to sn_l2 {
                sel_span(l)
                i = sp_a
                while i < sp_b {
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
            sel_span(l)
            if kind == 4 and LB[O_TBL] != 0
                sp_b = sp_a                 ; no 24 pt in tables
            i = sp_a
            while i < sp_b {
                if LB[O_STY + i] & 8 != 0 {
                    i++
                    continue                ; table border glyph
                }
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
                    else -> LB[O_STY + i] = (LB[O_STY + i] & ~SZ_MASK) | val
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
            if LB[O_TBL] != 0 or LB[O_PIC] != 0 {
                p = last + 1
                continue                    ; table rows and pictures keep their layout
            }
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
        if sty & 8 != 0 {
            ch = 32                 ; table border glyph
            sty = 0
        }
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
        ubyte i
        ubyte ch
        ubyte sty
        ubyte col
        for l in sn_l1 to sn_l2 {
            sel_span(l)
            i = sp_a
            while i < sp_b {
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
        pix.paste()                         ; on a picture: paste on a new line after it
        if clip_n == 0 or tblx.paste()
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
            wd = sz_w(LBV[O_STY + i])
            if cx < cum + wd {
                if wd > 1 and cx - cum >= (wd + 1) / 2
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
