; x16wpsa.p8 - X16 Write's Save As folder browser as a bank library: X16WPSA.BIN, RAM bank 59 at
; $A000, loaded by X16WPCL.BIN (bank 62). One dialog for both places:
;   SD card:  folders and files of the DOS current directory; opening a folder CDs into it (the
;             document then lives there), [Up] = CD:.., [New folder] = MD:
;   ownCloud: one folder of Documents/ at a time (X16Link DIR), [New folder] = MKDIR
; Double-click a folder to open it, click a file to take its name, type a name, Save.
; Main-RAM routines of X16 Write through wpsyms.p8 (generated for bank 59 by tools/gen_wpsyms.py).

%address  $A000
%memtop   $C000
%output   library

%import syslib
%import x16link_ext
%import lk_fs
%import wpsyms

main {
    %jmptable (
        sa.setup,           ; $A003  r0 = check -> A true if this library matches
        sa.browse_e,        ; $A006  r0L = 0 SD card, 1 ownCloud -> A true = save as wp.nbuf
                            ;        ownCloud: starts in the folder of the name in PICKNAME ("" = top);
                            ;        the result (full Documents-relative name) is left in PICKNAME
        sa.key_path,        ; $A009  PICKNAME = "//<X16 Write's folder>/:X16LINK.KEY"
        sa.exists_e,        ; $A00C  r0 = name (main RAM) -> A true if it exists in the current directory
        sa.cd_back,         ; $A00F  CD back to where the last SD card browse started
    )

    sub start() {
    }
}

sa {
    const ubyte C_WHITE = 1
    const ubyte C_BLUE = 6
    const ubyte C_DGRAY = 11
    const ubyte C_LGRAY = 15
    const uword pickname = $0650    ; 64 bytes of golden RAM, shared with X16WPCL.BIN

    ubyte[64] home                  ; X16 Write's folder (absolute), for X16LINK.KEY
    ubyte[64] sdpath                ; DOS current directory as we track it
    ubyte[64] start                 ; where the last SD card browse started (Cancel goes back)

    sub setup() -> bool {
        curdir()
        lkut.scopy(&home, &sdpath, 64)
        return cx16.r0 == wp.CHECK
    }

    sub busy(str s) {
        wp.set_status(s)
        wp.draw_status()
    }

    sub browse_e() -> bool {
        if cx16.r0L == 0 {
            lkut.scopy(&sdpath, &start, 64)
            return browse(false)
        }
        lkut.scopy(pickname, &bdir, 64)
        lkfs.up(&bdir)
        if not browse(true)
            return false
        if not lkfs.join(&bdir, wp.nbuf, pickname) {
            busy(iso:"Name too long (63 characters with the folders)")
            return false
        }
        return true
    }

    sub exists_e() -> bool {
        return sd_exists(cx16.r0)
    }

    sub cd_back() {
        void cd(&start)
    }

    sub key_path() {
        ubyte n = 0
        @(pickname) = iso:'/'
        if home[1] != 0 {
            lkut.scopy(&home, pickname + 1, 60)
            n = lkut.slen(pickname)
        } else
            n = 1
        @(pickname + n) = iso:'/'
        lkut.scopy(iso:":X16LINK.KEY", pickname + n + 1, 14)
    }


    ; ---------------- DOS (current directory, folders) ----------------
    ubyte[72] dcmd
    sub dos(uword a, uword b) -> bool {
        lkut.scopy(a, &dcmd, 8)
        ubyte n = lkut.slen(&dcmd)
        lkut.scopy(b, &dcmd + n, 64)
        cbm.SETNAM(lkut.slen(&dcmd), &dcmd)
        cbm.SETLFS(15, 8, 15)
        void cbm.OPEN()
        cbm.CLRCHN()
        cbm.CLOSE(15)
        return lkut.dos_ok()
    }

    ; CD to an absolute folder; sdpath follows
    sub cd(uword path) -> bool {
        if not dos(iso:"CD:", path)
            return false
        lkut.scopy(path, &sdpath, 64)
        return true
    }

    ; home = the DOS current directory: "$=C" lists it and its parents, innermost first
    sub curdir() {
        uword t = &tmp
        home[0] = iso:'/'
        home[1] = 0
        if not dir_open2(iso:"$=C")
            return
        while dir_next() {
            if dnm[0] == iso:'/'
                continue
            lkut.scopy(&home, t, 64)
            home[0] = iso:'/'
            lkut.scopy(&dnm, &home + 1, 62)
            ubyte n = lkut.slen(&home)
            if t[1] != 0 and n + lkut.slen(t) < 64
                lkut.scopy(t, &home + n, 64 - n)
        }
        dir_close()
    }

    sub sd_exists(uword name) -> bool {
        cbm.SETNAM(lkut.slen(name), name)
        cbm.SETLFS(12, 8, 0)
        void cbm.OPEN()
        bool e = lkut.dos_ok()
        cbm.CLOSE(12)
        return e
    }

    ubyte[41] dnm
    bool disdir
    sub dir_open() -> bool {
        return dir_open2(iso:"$")
    }

    sub dir_open2(uword spec) -> bool {
        cbm.SETNAM(lkut.slen(spec), spec)
        cbm.SETLFS(12, 8, 0)
        void cbm.OPEN()
        void cbm.CHKIN(12)
        repeat 6
            void cbm.CHRIN()            ; load address, link, line number of the header
        while cbm.CHRIN() != 0 {
            if cbm.READST() != 0
                return false
        }
        return cbm.READST() == 0
    }

    sub dir_close() {
        cbm.CLRCHN()
        cbm.CLOSE(12)
    }

    ; next entry -> dnm, disdir; skips ".", ".." and names longer than 40
    sub dir_next() -> bool {
        ubyte c
        ubyte n
        repeat {
            repeat 4
                void cbm.CHRIN()        ; link, blocks
            if cbm.READST() != 0
                return false
            do {
                c = cbm.CHRIN()
                if c == 0 or cbm.READST() != 0
                    return false
            } until c == iso:'"'
            n = 0
            repeat {
                c = cbm.CHRIN()
                if c == iso:'"' or c == 0 or cbm.READST() != 0
                    break
                if n < 41
                    dnm[n] = c
                n++
            }
            do {
                c = cbm.CHRIN()
            } until c != iso:' ' or cbm.READST() != 0
            disdir = c == iso:'D'
            while cbm.CHRIN() != 0 {
                if cbm.READST() != 0
                    break
            }
            if n == 0 or n > 40 or (dnm[0] == iso:'.' and (n == 1 or (n == 2 and dnm[1] == iso:'.')))
                continue
            dnm[n] = 0
            return true
        }
    }

    ; ---------------- Save As folder browser (SD card or ownCloud) ----------------
    const ubyte BX = 6
    const ubyte BY = 3
    const ubyte BW = 68
    const ubyte BR = 12                 ; list rows
    const ubyte LY = BY + 4
    const ubyte NY = BY + 17            ; name field row
    const ubyte HY = BY + 19            ; buttons row
    ubyte[64] bdir                      ; ownCloud folder (Documents-relative)
    bool bcl
    uword btotal
    uword btop
    uword bsel
    bool lfocus                         ; arrows moved the list since the last typed key
    ubyte[72] tmp                       ; scratch path (dialog title, curdir, enter, new folder)
    ubyte[41] selname                   ; the selected row, captured while the rows are drawn
    bool seldir

    sub hasup() -> bool {
        if bcl
            return bdir[0] != 0
        return sdpath[1] != 0
    }

    ; logical row i (".." first, then folders, then files): remember it if selected, draw it if visible
    sub row(uword i, uword name, bool dir) {
        if i == bsel {
            lkut.scopy(name, &selname, 41)
            seldir = dir
        }
        if i < btop or i >= btop + BR
            return
        ubyte y = LY + lsb(i - btop)
        ubyte fg = 0
        ubyte bg = C_WHITE
        ubyte sty = 0
        if dir {
            fg = C_BLUE
            sty = 1                     ; bold
        }
        if i == bsel {
            bg = C_BLUE
            fg = C_WHITE
        }
        wp.vid_fill(BX + 2, y, BW - 4, fg, bg)
        wp.vid_text(BX + 3, y, name, sty, fg, bg)
        if dir
            wp.vid_text(BX + 3 + lkut.slen(name), y, iso:"/", sty, fg, bg)
    }

    ; read the folder and draw the visible rows (the SD card listing is not kept: no room)
    sub fill() -> bool {
        uword i = 0
        selname[0] = 0
        if hasup() {
            row(0, iso:"..", true)
            i = 1
        }
        if bcl {
            if lkfs.dir_begin(&bdir) != 0
                return false
            btotal = i + lkfs.total
            ubyte r
            for r in 0 to BR - 1 {
                uword k = btop + r
                if k >= i and k < btotal {
                    uword e = lkfs.entry(k - i)
                    if e == 0
                        return false
                    lkfs.name(e, &dnm, 41)
                    row(k, &dnm, lkfs.is_dir(e))
                }
            }
        } else {
            bool pass
            for pass in [true, false] {
                if dir_open() {
                    while dir_next() {
                        if disdir == pass {
                            row(i, &dnm, disdir)
                            i++
                        }
                    }
                }
                dir_close()
            }
            btotal = i
        }
        ; blank the rows below the end of the list
        i = btotal
        while i < btop + BR {
            if i >= btop
                wp.vid_fill(BX + 2, LY + lsb(i - btop), BW - 4, 0, C_WHITE)
            i++
        }
        return true
    }

    sub draw_name() {
        wp.vid_fill(BX + 9, NY, 32, 0, C_WHITE)
        wp.vid_text(BX + 9, NY, wp.nbuf, 0, 0, C_WHITE)
        wp.vid_fill(BX + 9 + lkut.slen(wp.nbuf), NY, 1, C_WHITE, 0)       ; cursor
    }

    sub draw_dialog() {
        wp.draw_box(BX, BY, BW, 21)
        wp.vid_fill(BX, BY, BW, C_WHITE, C_BLUE)
        if bcl
            wp.put(BX + 2, BY, iso:"Save As to ownCloud", C_WHITE, C_BLUE)
        else
            wp.put(BX + 2, BY, iso:"Save As on the SD card", C_WHITE, C_BLUE)
        wp.put(BX + 2, BY + 2, iso:"Folder:", C_DGRAY, C_LGRAY)
        if bcl {
            lkut.scopy(iso:"/Documents/", &tmp, 72)
            lkut.scopy(&bdir, &tmp + 11, 61)
        } else
            lkut.scopy(&sdpath, &tmp, 72)
        uword tp = &tmp
        ubyte n = lkut.slen(&tmp)
        if n > 34
            tp += n - 34
        wp.put(BX + 10, BY + 2, tp, 0, C_LGRAY)
        wp.put(BX + 46, BY + 2, iso:"[ Up ]", 0, C_WHITE)
        wp.put(BX + 53, BY + 2, iso:"[New folder]", 0, C_WHITE)
        wp.put(BX + 2, NY, iso:"Name:", 0, C_LGRAY)
        wp.put(BX + 2, HY, iso:"Double-click opens a folder  F7=new folder", C_DGRAY, C_LGRAY)
        wp.put(BX + 46, HY, iso:"[ Save ]", 0, C_WHITE)
        wp.put(BX + 56, HY, iso:"[Cancel]", 0, C_WHITE)
        draw_name()
    }

    sub refill() {
        ubyte k
        for k in 0 to BR - 1
            wp.vid_fill(BX + 2, LY + k, BW - 4, 0, C_WHITE)
        redraw()
    }

    ; draw the rows again (the list is read again)
    sub redraw() {
        if not fill() {
            busy(iso:"Can't read that folder")
            btotal = 0
        }
    }

    sub bmove(uword i) {
        if btotal == 0
            return
        if i >= btotal
            i = btotal - 1
        bsel = i
        if bsel < btop
            btop = bsel
        else if bsel >= btop + BR
            btop = bsel - BR + 1
        redraw()
    }

    sub bup(uword n) {
        if bsel >= n
            bmove(bsel - n)
        else
            bmove(0)
    }

    ; enter folder `name` (".." = up); false = can't
    sub enter(uword name) -> bool {
        uword np = &tmp
        bool ok
        if bcl {
            lkut.scopy(&bdir, np, 64)
            if name[0] == iso:'.' and name[1] == iso:'.'
                lkfs.up(np)
            else if not lkfs.join(&bdir, name, np)
                return false
            lkut.scopy(np, &bdir, 64)
            ok = true
        } else {
            lkut.scopy(&sdpath, np, 64)
            if name[0] == iso:'.' and name[1] == iso:'.' {
                ubyte n = lkut.slen(np)
                while n > 1 and np[n - 1] != iso:'/'
                    n--
                if n > 1
                    n--
                np[n] = 0
            } else {
                ubyte a = lkut.slen(np)
                if a == 1
                    a = 0
                if a + 1 + lkut.slen(name) > 63
                    return false
                np[a] = iso:'/'
                lkut.scopy(name, np + a + 1, 63 - a)
            }
            ok = cd(np)
        }
        btop = 0
        bsel = 0
        lfocus = false
        draw_dialog()
        refill()
        return ok
    }

    ; row bsel: a folder is opened, a file gives its name
    sub take() {
        if bsel >= btotal or selname[0] == 0
            return
        if seldir {
            lkut.scopy(&selname, &dnm, 41)
            void enter(&dnm)
        } else if lkut.slen(&selname) <= 30 {
            lkut.scopy(&selname, wp.nbuf, 31)
            lfocus = false
            draw_name()
        }
    }

    sub new_folder() {
        dnm[0] = 0
        bool ok = wp.dialog_input(iso:"New folder name", &dnm, 30)
        if ok and dnm[0] != 0 {
            if bcl
                ok = lkfs.join(&bdir, &dnm, &tmp) and lkfs.mkdir(&tmp) == 0
            else
                ok = dos(iso:"MD:", &dnm)
            if not ok
                busy(iso:"Could not make that folder")
        }
        draw_dialog()
        refill()
    }

    sub finish() -> bool {
        wp.ensure_ext()
        wp.redraw_everything()
        return true
    }

    ; Save As browser: true = save as wp.nbuf in the folder shown (SD: the current directory,
    ; ownCloud: bdir)
    sub browse(bool cl) -> bool {
        bcl = cl
        btop = 0
        bsel = 0
        lfocus = false
        bool prev = true
        ubyte lastclick = 255
        ubyte lastt
        ubyte k
        draw_dialog()
        refill()
        busy(iso:"Choose a folder and type a name")
        repeat {
            sys.waitvsync()
            k = cbm.GETIN2()
            when k {
                0 -> {}
                27, 3 -> return false
                13 -> {
                    if lfocus
                        take()
                    else if @(wp.nbuf) != 0
                        return finish()
                }
                $91 -> {
                    lfocus = true
                    bup(1)
                }
                $11 -> {
                    lfocus = true
                    bmove(bsel + 1)
                }
                136 -> new_folder()             ; F7
                $82 -> bup(BR)
                $02 -> bmove(bsel + BR)
                8, 20 -> {
                    ubyte n = lkut.slen(wp.nbuf)
                    if n != 0
                        @(wp.nbuf + n - 1) = 0
                    lfocus = false
                    draw_name()
                }
                else -> {
                    ubyte n2 = lkut.slen(wp.nbuf)
                    if ((k >= 32 and k < 127) or k >= 160) and n2 < 30 {
                        @(wp.nbuf + n2) = k
                        @(wp.nbuf + n2 + 1) = 0
                        lfocus = false
                        draw_name()
                    }
                }
            }
            wp.poll_mouse()
            if wp.mouse_wheel < 0
                bup(3)
            else if wp.mouse_wheel > 0
                bmove(bsel + 3)
            if wp.mouse_btn & 1 != 0 {
                if not prev {
                    ubyte cy = wp.mouse_cy
                    ubyte cx = wp.mouse_cx
                    if cy == HY and cx >= BX + 46 and cx < BX + 54 {
                        if @(wp.nbuf) != 0
                            return finish()
                    } else if cy == HY and cx >= BX + 56 and cx < BX + 64 {
                        return false
                    } else if cy == BY + 2 and cx >= BX + 46 and cx < BX + 52 {
                        if hasup()
                            void enter(iso:"..")
                    } else if cy == BY + 2 and cx >= BX + 53 and cx < BX + 65 {
                        new_folder()
                    } else if cy >= LY and cy < LY + BR and cx > BX + 1 and cx < BX + BW - 2 {
                        uword i = btop + cy - LY
                        if i < btotal {
                            ubyte now = lsb(cbm.RDTIM16())
                            bool dbl = lsb(i) == lastclick and i == bsel and now - lastt < 30
                            lastclick = lsb(i)
                            lastt = now
                            bmove(i)
                            if dbl or not seldir {
                                take()
                                lastclick = 255
                            }
                        }
                    }
                }
                prev = true
            } else
                prev = false
        }
    }
}
