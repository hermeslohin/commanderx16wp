; cloudtest.p8 - scripted headless test of the X16 Write ownCloud UI (X16WPCL.BIN) against a running hub.
; Same modules as X16 Write; keystrokes are injected from a VSYNC IRQ (one scripted key whenever the
; keyboard buffer is empty and the previous key was taken ~1 s ago); $9FB5=1 grabs a GIF frame.
; Driven by selftest/run_cloudtest.sh, which checks the results in ownCloud.
%import syslib
%import emudbg
%import view
%import rtf
%import cloudx
%zeropage basicsafe

main {
    ; script bytes: key codes; $FF = take a screenshot frame, $FE = pause, $00 = end
    ubyte[] k1 = [iso:'2', 0]
    ubyte[] k2 = [$11, $ff, 13, 0]
    ubyte[] k3 = [$11, $11, $ff, 13, 0]
    ubyte[] k4 = [20,20,20,20,20,20,20,20,20,20,20,20, iso:'L',iso:'K',iso:'T',iso:'E',iso:'S',iso:'T',iso:'-',iso:'W',iso:'P', $ff, 13, 0]
    ubyte[] k5 = [20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20, iso:'L',iso:'K',iso:'T',iso:'E',iso:'S',iso:'T',iso:'.',iso:'R',iso:'T',iso:'F', 13, $fe, $fe, $ff, iso:'n',
              20,20,20,20,20,20,20,20,20,20,20,20, iso:'L',iso:'K',iso:'T',iso:'E',iso:'S',iso:'T',iso:'-',iso:'N',iso:'E',iso:'W', 13, 0]
    ubyte[] k6 = [20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20, iso:'L',iso:'K',iso:'T',iso:'E',iso:'S',iso:'T',iso:'.',iso:'T',iso:'X',iso:'T', 13, iso:'o', 0]
    uword script
    ubyte sp
    ubyte idle
    bool armed

    ; act only when the keyboard buffer has been empty for a while: 30 frames before the next key,
    ; 150 frames (2.5 s, lets network work and redraws finish) before a screenshot
    sub irq() -> bool {
        if armed {
            ubyte k
            ubyte n
            k, n = cx16.kbdbuf_peek()
            if n != 0 {
                idle = 0
            } else {
                if idle != 255
                    idle++
                k = @(script + sp)
                if k == 0 {
                    armed = false
                } else if k == $fe {            ; pause ~2.5 s (network work in progress)
                    if idle >= 150 {
                        sp++
                        idle = 0
                    }
                } else if k == $ff {
                    if idle >= 150 {
                        poke($9fb5, 1)      ; one frame now (dialogs redraw continuously,
                        if idle >= 153 {    ; so grab a few frames and keep the best)
                            sp++
                            idle = 0
                        }
                    }
                } else if idle >= 30 {
                    cx16.kbdbuf_put(k)
                    sp++
                    idle = 0
                }
            }
        }
        return true
    }

    sub play(uword keys) {
        script = keys
        sp = 0
        idle = 0
        armed = true
    }

    sub log(str s) {
        emudbg.console_write(s)
    }
    sub status(str tag) {
        log(tag)
        log(iso:" status=[")
        log(view.status_msg)
        log(iso:"] file=[")
        log(view.filename)
        log(iso:"] lines=")
        log(conv.str_uw(doc.nlines))
        log(iso:"\n")
    }
    sub shot() {
        sys.wait(10)
        poke($9fb5, 1)
        sys.wait(10)
    }

    ; never runs: keeps the routines X16WPCL.BIN calls from being optimised away in this test build
    sub keepalive() {
        view.draw_box(0, 0, 1, 1)
        view.put(0, 0, iso:"", 0, 0)
        view.num(0, 0, 0, 0, 0)
        view.poll_mouse()
        view.draw_status()
        void view.dialog_input(iso:"", view.nbuf, 1)
        view.ensure_ext()
        view.copy_name_to_buf()
        vid.fill(0, 0, 1, 0, 0)
        diskio.delete(iso:"")
        void rtf.import(iso:"")
    }

    sub start() {
        if sp == 250 and idle == 251
            keepalive()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        doc.init_doc()
        view.set_filename(iso:"untitled.rtf")
        view.set_status(iso:"cloud test")
        view.redraw_everything()
        sys.set_irq(&irq)

        ; 1) Open menu -> "2" ownCloud; picker: DOWN to LKTEST.RTF, screenshot, ENTER
        play(&k1)
        ubyte m = cloudx.menu(0)
        log(iso:"MENU ")
        log(conv.str_ub(m))
        log(iso:"\n")
        view.redraw_everything()
        play(&k2)
        cloudx.cl_open()
        status(iso:"OPEN_RTF")
        shot()
        if rtf.export(iso:"WPEXP1.RTF")
            log(iso:"EXPORT1 ok\n")

        ; 2) open the .txt (hub converts it to RTF): DOWN DOWN ENTER
        play(&k3)
        cloudx.cl_open()
        status(iso:"OPEN_TXT")
        shot()

        ; 3) Save As to ownCloud as a new name (prefilled name: delete it, type the new one)
        play(&k4)
        cloudx.cl_save(1)
        status(iso:"SAVEAS_NEW")
        if rtf.export(iso:"WPEXP2.RTF")
            log(iso:"EXPORT2 ok\n")

        ; 4) Save (back to the same cloud file, If-Match the etag we got): no prompt
        doc.insert_char(iso:'!')
        cloudx.save()
        status(iso:"SAVE_SAME")
        if rtf.export(iso:"WPEXP3.RTF")
            log(iso:"EXPORT3 ok\n")

        ; 5) Save As onto an existing name -> conflict dialog (screenshot) -> New name -> LKTEST-NEW
        play(&k5)
        cloudx.cl_save(1)
        status(iso:"SAVEAS_CONFLICT_NEWNAME")

        ; 6) Save As onto LKTEST.TXT -> conflict -> Overwrite (hub stores plain UTF-8 text)
        play(&k6)
        cloudx.cl_save(1)
        status(iso:"SAVEAS_CONFLICT_OVERWRITE")

        ; 7) local SD save still works
        view.nbuf[0] = 0
        if rtf.export(iso:"LOCAL.RTF")
            log(iso:"LOCAL_SAVE ok\n")
        log(iso:"CLOUDTEST done\n")
        repeat {}
    }
}
