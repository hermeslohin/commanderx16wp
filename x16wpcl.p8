; x16wpcl.p8 - ownCloud UI of X16 Write as a bank library: X16WPCL.BIN, RAM bank 62 at $A000.
; Open: dial the hub, list Documents/ in a scrollable picker (mouse + keys), download the chosen
; file (.rtf as is, .txt and .docx converted to RTF by the hub) and load it.
; Save As to a .docx name: the hub converts the RTF to a Word document (and back on Open).
; Save / Save As: export RTF to a temp file and upload it (create-only, or overwrite exactly the
; version we opened); a conflict asks Overwrite / New name / Cancel.
; Save As (SD card and ownCloud) shows a folder browser, the bank library X16WPSA.BIN (RAM bank 59,
; x16wpsa.p8), which this library loads at setup. On the SD card Save As changes the DOS current
; directory (CD), which then is where the document lives; the key file is read with an absolute
; path to X16 Write's own folder.
; It calls X16 Write's main-RAM routines through wpsyms.p8 (generated from the WP build by
; tools/gen_wpsyms.py) and the X16Link libraries in banks 60/61. Build: make -C apps/wp.

%address  $A000
%memtop   $C000
%output   library

%import syslib
%import x16link_ext
%import lk_util
%import wpsyms

main {
    %jmptable (
        cloud.setup,        ; $A003  r0 = &vid.text as the WP sees it, r1 = temp file name -> A true if this library matches
        cloud.open_doc,     ; $A006
        cloud.save_entry,   ; $A009  r0L = 0 Save, 1 Save As to ownCloud, 2 Save As on the SD card
        cloud.menu_entry,   ; $A00C  r0L = 0 Open menu, 1 Save As menu -> A 0 SD, 1 ownCloud, 255 cancel
        cloud.is_cloud,     ; $A00F  -> A
        cloud.forget,       ; $A012
        cloud.get_bmx,      ; $A015  pick a .bmx in Documents/ and download it (raw) to the temp file -> A true
    )

    sub start() {
        cloud.forget()
    }
}

cloud {
    ; colour indexes (Sunset Arcade theme roles, see theme.p8 in the main program)
    const ubyte C_BLACK = 0
    const ubyte C_WHITE = 1
    const ubyte C_RED = 2
    const ubyte C_PURPLE = 4
    const ubyte C_BLUE = 6
    const ubyte C_YELLOW = 7
    const ubyte C_DGRAY = 11
    const ubyte C_GRAY = 12
    const ubyte C_LGRAY = 15

    ubyte[64] cname             ; remote name in Documents/ ("" = not a cloud document)
    ubyte[48] cetag             ; etag of the version we opened/saved last
    ; Buffers handed to the X16Link libraries must be visible from banks 60/61, so they live in the
    ; free part of golden RAM after XB: $0608-$06F3 (see x16link_ext.p8 for the full map).
    const uword row = $0608         ; 72  picker row from list_row
    const uword pickname = $0650    ; 64  chosen name / key file name
    const uword setag = $0690       ; 48  etag in/out (set_etag, get_etag, conflict)
    const uword emsg = $06c0        ; 52  error text

    ; Save As browser library (X16WPSA.BIN, bank 59)
    const ubyte SABANK = 59
    extsub @bank SABANK $A000 = sa_init() clobbers(A, X, Y)
    extsub @bank SABANK $A003 = sa_setup(uword check @R0) clobbers(X, Y) -> bool @A
    extsub @bank SABANK $A006 = sa_browse(ubyte cl @R0) clobbers(X, Y) -> bool @A
    extsub @bank SABANK $A009 = sa_key_path() clobbers(A, X, Y)
    extsub @bank SABANK $A00C = sa_exists(uword name @R0) clobbers(X, Y) -> bool @A
    extsub @bank SABANK $A00F = sa_cd_back() clobbers(A, X, Y)


    ; Sunset Arcade dialog button: "[label]" drawn as a yellow pill. The pill caps are the theme glyphs
    ; 243/244 in font slot 3 (theme.p8 uploads them; style $38 = raw glyph from slot 3).
    ubyte[2] lcap = [243, 0]
    ubyte[2] rcap = [244, 0]
    sub button(ubyte x, ubyte y, uword label) {
        ubyte n = lkut.slen(label) - 1
        wp.vid_text(x, y, &lcap, $38, C_YELLOW, C_LGRAY)
        @(label + n) = 0
        wp.vid_text(x + 1, y, label + 1, 0, C_BLACK, C_YELLOW)
        @(label + n) = iso:']'
        wp.vid_text(x + n, y, &rcap, $38, C_YELLOW, C_LGRAY)
    }

    uword TMPN                  ; temp file name (lives in the WP's main RAM)
    sub setup() -> bool {
        TMPN = cx16.r1
        if cx16.r0 != wp.CHECK
            return false
        ; load X16WPSA.BIN into bank 59: X16 Write's own load_raw, called with bank 59 mapped
        ; (the file name must be outside banked RAM)
        lkx_copy(iso:"X16WPSA.BIN", pickname)
        if wp.load_raw59(pickname, $a000) == 0
            return false
        sa_init()
        return sa_setup(wp.CHECK)
    }

    sub save_entry() {
        if cx16.r0L == 2
            sd_save_as()
        else
            save_doc(cx16.r0L != 0)
    }

    sub menu_entry() -> ubyte {
        if cx16.r0L == 0
            return menu2(3, iso:"1 Open from SD card...", iso:"2 Open from ownCloud...")
        if cx16.r0L == 2
            return menu2(30, iso:"1 Picture from SD card...", iso:"2 Picture from ownCloud...")
        return menu2(9, iso:"1 Save As on SD card...", iso:"2 Save As to ownCloud...")
    }

    ; two-entry popup under a toolbar button: 0 = first, 1 = second, 255 = cancelled
    sub menu2(ubyte x, str a, str b) -> ubyte {
        bool prev = true
        ubyte k
        wp.draw_box(x, 3, 28, 4)
        wp.vid_fill(x + 1, 4, 26, 0, C_WHITE)
        wp.vid_fill(x + 1, 5, 26, 0, C_WHITE)
        wp.put(x + 2, 4, a, 0, C_WHITE)
        wp.put(x + 2, 5, b, 0, C_WHITE)
        repeat {
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == iso:'1'
                return 0
            if k == iso:'2'
                return 1
            if k == 27 or k == 3
                return 255
            wp.poll_mouse()
            if wp.mouse_btn & 1 != 0 {
                if not prev {
                    if wp.mouse_cx > x and wp.mouse_cx < x + 27 and (wp.mouse_cy == 4 or wp.mouse_cy == 5)
                        return wp.mouse_cy - 4
                    return 255
                }
                prev = true
            } else
                prev = false
        }
    }

    sub is_cloud() -> bool {
        return cname[0] != 0
    }

    sub forget() {
        cname[0] = 0
        cetag[0] = 0
    }

    sub busy(str s) {
        wp.set_status(s)
        wp.draw_status()
    }

    sub fail(str what) {
        ; "<what>: <reason from the libraries>"
        ubyte i = 0
        while what[i] != 0 {
            @(emsg + i) = what[i]
            i++
        }
        @(emsg + i) = iso:':'
        @(emsg + i + 1) = iso:' '
        lkapi.get_error(emsg + i + 2, 50 - i - 2)
        wp.set_status(emsg)
    }

    ; "//<home>/:X16LINK.KEY": the key next to X16WP.PRG, wherever the current directory is
    sub online() -> bool {
        busy(iso:"Connecting to the hub...")
        sa_key_path()               ; pickname = "//<X16 Write's folder>/:X16LINK.KEY"
        ubyte st = lkapi.load_key(pickname)
        if st == 0
            st = lkapi.connect()
        if st != 0 {
            lkapi.forget()
            fail(iso:"Hub unreachable")
            return false
        }
        return true
    }

    ; ---------------- picker ----------------
    const ubyte PX = 3
    const ubyte PY = 3
    const ubyte PW = 74
    const ubyte PROWS = 18
    const ubyte LROW = PY + 3
    uword total
    uword top
    uword sel

    sub draw_row(ubyte r) {
        uword i = top + r
        ubyte y = LROW + r
        ubyte fg = 0
        ubyte bg = C_WHITE
        wp.vid_fill(PX + 1, y, PW - 2, 0, bg)
        if i >= total
            return
        if lkapi.list_row(i, row) != 0 {
            wp.vid_text(PX + 2, y, iso:"(list error)", 0, C_RED, bg)
            return
        }
        if not openable()
            fg = C_GRAY             ; unsupported type: shown, not openable
        if i == sel {
            bg = C_RED
            fg = C_BLACK
            wp.vid_fill(PX + 1, y, PW - 2, fg, bg)
        }
        wp.vid_text(PX + 2, y, row + 2, 0, fg, bg)
    }

    sub draw_pos() {
        wp.put(PX + 2, PY + PROWS + 4, iso:"      of      ", C_DGRAY, C_LGRAY)
        wp.num(PX + 2, PY + PROWS + 4, sel + 1, C_DGRAY, C_LGRAY)
        wp.num(PX + 11, PY + PROWS + 4, total, C_DGRAY, C_LGRAY)
    }

    sub draw_list() {
        ubyte r
        for r in 0 to PROWS - 1
            draw_row(r)
        draw_pos()
    }

    ; move the selection; only the two changed rows are redrawn unless the list scrolls
    sub move_to(uword i) {
        if total == 0
            return
        if i >= total
            i = total - 1
        uword old = sel
        uword otop = top
        sel = i
        if sel < top
            top = sel
        if sel >= top + PROWS
            top = sel - PROWS + 1
        if top != otop {
            draw_list()
        } else if old != sel {
            draw_row(lsb(old - top))
            draw_row(lsb(sel - top))
            draw_pos()
        }
    }

    sub up(uword n) {
        if sel >= n
            move_to(sel - n)
        else
            move_to(0)
    }


    ; RTF (1), TXT (2) and DOCX (3) open as RTF (conv 1); spreadsheets (4, 5) belong to X16 Sheets;
    ; when picking a picture (bmxmode) only BMX (7) and PNG / JPEG / GIF / BMP (8, which the hub
    ; converts to BMX with conv 4) can be chosen; picktype = the chosen file's type
    bool bmxmode
    ubyte picktype
    sub openable() -> bool {
        if @(row + 1) & 1 != 0
            return false
        if bmxmode
            return @(row) == 7 or @(row) == 8
        return @(row) >= 1 and @(row) <= 3
    }

    sub choose() -> bool {
        if not openable() {
            if bmxmode
                busy(iso:"Choose a picture (BMX, PNG, JPEG, GIF, BMP)")
            else
                busy(iso:"That file type can't be opened (RTF/TXT/DOCX only)")
            return false
        }
        if lkapi.list_name(sel, pickname, 64) != 0
            return false
        picktype = @(row)
        return true
    }

    sub pick() -> bool {
        ubyte k
        bool prev = true
        ubyte lastclick = 255
        ubyte lastt
        total = lkapi.list_total()
        top = 0
        sel = 0
        wp.draw_box(PX, PY, PW, PROWS + 6)
        wp.vid_fill(PX, PY, PW, 0, C_PURPLE)
        if bmxmode
            wp.vid_text(PX + 2, PY, iso:"Insert picture from ownCloud - Documents", 1, C_BLACK, C_PURPLE)
        else
            wp.vid_text(PX + 2, PY, iso:"Open from ownCloud - Documents", 1, C_BLACK, C_PURPLE)
        wp.vid_fill(PX + 1, PY + 2, PW - 2, 0, C_YELLOW)
        wp.put(PX + 2, PY + 2, iso:"Name                                      Size  Modified        Type", C_BLACK, C_YELLOW)
        wp.put(PX + 17, PY + PROWS + 4, iso:"Enter=open  Esc=cancel", C_DGRAY, C_LGRAY)
        button(PX + PW - 22, PY + PROWS + 4, iso:"[ Open ]")
        button(PX + PW - 12, PY + PROWS + 4, iso:"[Cancel]")
        if bmxmode
            busy(iso:"Choose a BMX, PNG, JPEG, GIF or BMP picture")
        else
            busy(iso:"Choose a document (ownCloud Documents/)")
        if total == 0
            wp.put(PX + 2, LROW, iso:"(Documents is empty)", C_DGRAY, C_WHITE)
        draw_list()
        repeat {
            sys.waitvsync()
            k = cbm.GETIN2()
            when k {
                27, 3 -> return false
                13 -> {
                    if total != 0 and lkapi.list_row(sel, row) == 0 and choose()
                        return true
                }
                $91 -> up(1)
                $11 -> move_to(sel + 1)
                $82 -> up(PROWS)                ; PgUp
                $02 -> move_to(sel + PROWS)     ; PgDn
                $13 -> move_to(0)               ; Home
                $04 -> move_to(total - 1)       ; End
            }
            wp.poll_mouse()
            if wp.mouse_wheel < 0
                up(3)
            else if wp.mouse_wheel > 0
                move_to(sel + 3)
            if wp.mouse_btn & 1 != 0 {
                if not prev {
                    ubyte cy = wp.mouse_cy
                    ubyte cx = wp.mouse_cx
                    if cy == PY + PROWS + 4 and cx >= PX + PW - 22 and cx < PX + PW - 14 {
                        if total != 0 and lkapi.list_row(sel, row) == 0 and choose()
                            return true
                    } else if cy == PY + PROWS + 4 and cx >= PX + PW - 12 and cx < PX + PW - 4 {
                        return false
                    } else if cy >= LROW and cy < LROW + PROWS and cx > PX and cx < PX + PW - 1 {
                        uword i = top + cy - LROW
                        if i < total {
                            ubyte now = lsb(cbm.RDTIM16())
                            if lsb(i) == lastclick and i == sel and now - lastt < 30 {
                                if lkapi.list_row(sel, row) == 0 and choose()
                                    return true
                            }
                            lastclick = lsb(i)
                            lastt = now
                            move_to(i)
                        }
                    }
                }
                prev = true
            } else
                prev = false
        }
    }

    ; ---------------- open ----------------
    sub open_doc() {
        if online() {
            busy(iso:"Reading the Documents list...")
            if lkapi.list_begin() != 0 {
                fail(iso:"List failed")
            } else if pick() {
                wp.redraw_everything()
                busy(iso:"Downloading...")
                if lkapi.download(pickname, TMPN, 1) != 0 {
                    fail(iso:"Open failed")
                } else if wp.rtf_import(TMPN) {
                    lkapi.get_etag(setag, 48)
                    lkx_copy(setag, &cetag)
                    lkx_copy(pickname, &cname)
                    wp.set_filename(&cname)
                    wp.modified = false
                    wp.vtop = 0
                    wp.set_status(iso:"Opened from ownCloud")
                    wp.theme_hop = 32         ; theme.cheer(): Quill hops
                } else {
                    wp.set_status(iso:"Could not read that document")
                }
                wp.disk_delete(TMPN)
            } else {
                wp.set_status(iso:"Open cancelled")
            }
            lkapi.hangup()
            lkapi.forget()                  ; key out of RAM until the next transfer
        }
        wp.redraw_everything()
    }

    ; the Picture button, ownCloud: pick a .bmx and download it as it is (conv 3), or a PNG / JPEG / GIF /
    ; BMP picture, which the hub converts to a BMX (conv 4, at most 320 x 240), to the temp file;
    ; X16WPPL.BIN reads it from there (and deletes it). Hubs without conv 4 list pictures as type 0.
    sub get_bmx() -> bool {
        bool ok = false
        bmxmode = true
        if online() {
            busy(iso:"Reading the Documents list...")
            if lkapi.list_begin() != 0 {
                fail(iso:"List failed")
            } else if pick() {
                wp.redraw_everything()
                ubyte conv = 3
                if picktype == 8 {
                    conv = 4
                    busy(iso:"Converting the picture on the hub...")
                } else
                    busy(iso:"Downloading the picture...")
                if lkapi.download(pickname, TMPN, conv) != 0
                    fail(iso:"Download failed")
                else
                    ok = true
            } else {
                wp.set_status(iso:"Cancelled")
            }
            lkapi.hangup()
            lkapi.forget()
        }
        bmxmode = false
        wp.redraw_everything()
        return ok
    }

    sub lkx_copy(uword src, uword dst) {
        ubyte i = 0
        while @(src + i) != 0 and i < 63 {
            @(dst + i) = @(src + i)
            i++
        }
        @(dst + i) = 0
    }

    ; ---------------- save ----------------
    ; 0 = overwrite, 1 = new name, 2 = cancel
    sub conflict_dialog(bool exists) -> ubyte {
        bool prev = true
        ubyte k
        wp.draw_box(14, 11, 52, 7)
        wp.vid_fill(14, 11, 52, C_WHITE, C_RED)
        wp.vid_text(16, 11, iso:"Save conflict", 1, C_WHITE, C_RED)
        wp.put(16, 13, pickname, 0, C_LGRAY)
        if exists
            wp.put(16, 14, iso:"already exists on ownCloud.", 0, C_LGRAY)
        else
            wp.put(16, 14, iso:"was changed on ownCloud since you opened it.", 0, C_LGRAY)
        button(17, 16, iso:"[Overwrite]")
        button(32, 16, iso:"[New name]")
        button(47, 16, iso:"[ Cancel ]")
        repeat {
            sys.waitvsync()
            k = cbm.GETIN2()
            if k == iso:'o' or k == iso:'O'
                return 0
            if k == iso:'n' or k == iso:'N'
                return 1
            if k == 27 or k == 3 or k == iso:'c' or k == iso:'C'
                return 2
            wp.poll_mouse()
            if wp.mouse_btn & 1 != 0 {
                if not prev and wp.mouse_cy == 16 {
                    if wp.mouse_cx >= 17 and wp.mouse_cx < 28
                        return 0
                    if wp.mouse_cx >= 32 and wp.mouse_cx < 42
                        return 1
                    if wp.mouse_cx >= 47 and wp.mouse_cx < 57
                        return 2
                }
                prev = true
            } else
                prev = false
        }
    }

    ; browse ownCloud for the folder + name (starting at the folder of the name in pickname);
    ; the full name (Documents-relative) ends up in pickname
    sub ask_name() -> bool {
        return sa_browse(1)
    }

    sub same_as_current() -> bool {
        ubyte i = 0
        repeat {
            if @(pickname + i) != cname[i]
                return false
            if cname[i] == 0
                return true
            i++
        }
    }

    ; ask = Save As (browse for a folder and name); otherwise Save back to the document's own cloud file
    sub save_doc(bool ask) {
        ubyte mode = 0
        if not online() {
            wp.redraw_everything()
            return
        }
        if ask or not is_cloud() {
            ; start in the document's own folder with its name
            @(pickname) = 0
            if is_cloud() {
                lkx_copy(&cname, pickname)
                lkut.scopy(leaf(&cname), wp.nbuf, 31)
            } else
                wp.copy_name_to_buf()
            if not ask_name() {
                done(iso:"Save cancelled")
                return
            }
        } else
            lkx_copy(&cname, pickname)
        busy(iso:"Saving...")
        if not wp.rtf_export(TMPN) {
            done(iso:"SAVE FAILED (temp file)")
            return
        }
        if is_cloud() and same_as_current() {
            mode = 1                    ; overwrite exactly the version we have
            lkx_copy(&cetag, setag)
        } else
            @(setag) = 0
        lkapi.set_etag(setag)
        repeat {
            busy(iso:"Uploading...")
            ubyte st = lkapi.upload(TMPN, pickname, mode, 1)
            if st == 0 {
                lkapi.get_etag(setag, 48)
                lkx_copy(setag, &cetag)
                lkx_copy(pickname, &cname)
                wp.set_filename(leaf(&cname))
                wp.modified = false
                wp.set_status(iso:"Saved to ownCloud")
                wp.theme_hop = 32         ; theme.cheer(): Quill hops
                break
            }
            if st != lkapi.S_CONFLICT {
                fail(iso:"Save failed")
                break
            }
            ubyte kind = lkapi.conflict(setag, 48)
            ubyte choice = conflict_dialog(kind == 1)
            wp.redraw_everything()
            if choice == 0 {
                mode = 1
                lkapi.set_etag(setag)  ; overwrite the version the hub just told us about
            } else if choice == 1 {
                if not ask_name() {
                    wp.set_status(iso:"Save cancelled")
                    break
                }
                mode = 0
                @(setag) = 0
                lkapi.set_etag(setag)
            } else {
                wp.set_status(iso:"Save cancelled")
                break
            }
        }
        lkapi.hangup()
        lkapi.forget()                  ; key out of RAM until the next transfer
        wp.disk_delete(TMPN)
        wp.redraw_everything()
    }

    ; last segment of a path
    sub leaf(uword p) -> uword {
        uword l = p
        while @(p) != 0 {
            if @(p) == iso:'/'
                l = p + 1
            p++
        }
        return l
    }

    sub done(str msg) {
        lkapi.hangup()
        lkapi.forget()
        wp.set_status(msg)
        wp.redraw_everything()
    }

    ; ---------------- Save As on the SD card ----------------
    sub sd_save_as() {
        wp.copy_name_to_buf()
        if not sa_browse(0) {
            sa_cd_back()                ; cancelled: back to where we were
            wp.set_status(iso:"Save cancelled")
            wp.redraw_everything()
            return
        }
        if sa_exists(wp.nbuf) {
            bool yes = wp.dialog_yesno(iso:"Replace the existing file?")
            wp.redraw_everything()
            if not yes {
                wp.set_status(iso:"Save cancelled")
                wp.draw_status()
                return
            }
        }
        busy(iso:"Saving...")
        if wp.rtf_export(wp.nbuf) {
            forget()
            wp.set_filename(wp.nbuf)
            wp.modified = false
            wp.set_status(iso:"Saved as RTF")
            wp.theme_hop = 32         ; theme.cheer(): Quill hops
        } else
            wp.set_status(iso:"SAVE FAILED")
        wp.redraw_everything()
    }

}
