; x16wpcl.p8 - ownCloud UI of X16 Write as a bank library: X16WPCL.BIN, RAM bank 62 at $A000.
; Open: dial the hub, list Documents/ in a scrollable picker (mouse + keys), download the chosen
; file (.rtf as is, .txt converted to RTF by the hub) and load it.
; Save / Save As: export RTF to a temp file and upload it (create-only, or overwrite exactly the
; version we opened); a conflict asks Overwrite / New name / Cancel.
; It calls X16 Write's main-RAM routines through wpsyms.p8 (generated from the WP build by
; tools/gen_wpsyms.py) and the X16Link libraries in banks 60/61. Build: make -C apps/wp.

%address  $A000
%memtop   $C000
%output   library

%import syslib
%import x16link_ext
%import wpsyms

main {
    %jmptable (
        cloud.setup,        ; $A003  r0 = &vid.text as the WP sees it, r1 = temp file name -> A true if this library matches
        cloud.open_doc,     ; $A006
        cloud.save_entry,   ; $A009  r0L = 1 Save As (ask a name), 0 Save
        cloud.menu_entry,   ; $A00C  r0L = 0 Open menu, 1 Save As menu -> A 0 SD, 1 ownCloud, 255 cancel
        cloud.is_cloud,     ; $A00F  -> A
        cloud.forget,       ; $A012
    )

    sub start() {
        cloud.forget()
    }
}

cloud {
    const ubyte C_WHITE = 1
    const ubyte C_RED = 2
    const ubyte C_BLUE = 6
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

    uword TMPN                  ; temp file name (lives in the WP's main RAM)
    sub setup() -> bool {
        TMPN = cx16.r1
        return cx16.r0 == wp.CHECK
    }

    sub save_entry() {
        save_doc(cx16.r0L != 0)
    }

    sub menu_entry() -> ubyte {
        if cx16.r0L == 0
            return menu2(3, iso:"1 Open from SD card...", iso:"2 Open from ownCloud...")
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

    sub online() -> bool {
        busy(iso:"Connecting to the hub...")
        lkx_copy(iso:"X16LINK.KEY", pickname)
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
        if @(row + 1) & 1 != 0
            fg = C_GRAY             ; unsupported type: shown, not openable
        if i == sel {
            bg = C_BLUE
            fg = C_WHITE
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


    sub choose() -> bool {
        if @(row + 1) & 1 != 0 {
            busy(iso:"That file type can't be opened (RTF/TXT only)")
            return false
        }
        if lkapi.list_name(sel, pickname, 64) != 0
            return false
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
        wp.vid_fill(PX, PY, PW, C_WHITE, C_BLUE)
        wp.put(PX + 2, PY, iso:"Open from ownCloud - Documents", C_WHITE, C_BLUE)
        wp.put(PX + 2, PY + 2, iso:"Name                                      Size  Modified        Type", C_DGRAY, C_LGRAY)
        wp.put(PX + 17, PY + PROWS + 4, iso:"Enter=open  Esc=cancel", C_DGRAY, C_LGRAY)
        wp.put(PX + PW - 22, PY + PROWS + 4, iso:"[ Open ]", 0, C_WHITE)
        wp.put(PX + PW - 12, PY + PROWS + 4, iso:"[Cancel]", 0, C_WHITE)
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
        wp.put(16, 11, iso:"Save conflict", C_WHITE, C_RED)
        wp.put(16, 13, wp.nbuf, 0, C_LGRAY)
        if exists
            wp.put(16, 14, iso:"already exists on ownCloud.", 0, C_LGRAY)
        else
            wp.put(16, 14, iso:"was changed on ownCloud since you opened it.", 0, C_LGRAY)
        wp.put(17, 16, iso:"[Overwrite]", 0, C_WHITE)
        wp.put(32, 16, iso:"[New name]", 0, C_WHITE)
        wp.put(47, 16, iso:"[ Cancel ]", 0, C_WHITE)
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

    sub ask_name() -> bool {
        bool ok = wp.dialog_input(iso:"Save As to ownCloud (Documents/)", wp.nbuf, 30)
        wp.redraw_everything()
        if ok
            wp.ensure_ext()
        return ok and @(wp.nbuf + 0) != 0
    }

    sub same_as_current() -> bool {
        ubyte i = 0
        repeat {
            if @(wp.nbuf + i) != cname[i]
                return false
            if cname[i] == 0
                return true
            i++
        }
    }

    ; ask = Save As (prompt for a name); otherwise Save back to the document's own cloud file
    sub save_doc(bool ask) {
        ubyte mode = 0
        if ask or not is_cloud() {
            if is_cloud()
                lkx_copy(&cname, wp.nbuf)
            else
                wp.copy_name_to_buf()
            if not ask_name()
                return
        } else
            lkx_copy(&cname, wp.nbuf)
        busy(iso:"Saving...")
        if not wp.rtf_export(TMPN) {
            wp.set_status(iso:"SAVE FAILED (temp file)")
            wp.redraw_everything()
            return
        }
        if online() {
            if is_cloud() and same_as_current() {
                mode = 1                    ; overwrite exactly the version we have
                lkx_copy(&cetag, setag)
                lkapi.set_etag(setag)
            } else
                @(setag) = 0
                lkapi.set_etag(setag)
            repeat {
                busy(iso:"Uploading...")
                ubyte st = lkapi.upload(TMPN, wp.nbuf, mode, 1)
                if st == 0 {
                    lkapi.get_etag(setag, 48)
                    lkx_copy(setag, &cetag)
                    lkx_copy(wp.nbuf, &cname)
                    wp.set_filename(&cname)
                    wp.modified = false
                    wp.set_status(iso:"Saved to ownCloud")
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
        }
        wp.disk_delete(TMPN)
        wp.redraw_everything()
    }
}
