; saveas.p8 - scripted headless test of the Save As folder browser (X16WPSA.BIN) on the SD card and
; on ownCloud, with the real X16WPCL.BIN / X16WPSA.BIN built against this program's symbols.
; Keystrokes come from a VSYNC IRQ (as in cloudtest.p8). Driven by selftest/run_saveastest.sh, which
; runs it on a FAT32 SD card image against the hub link server with an in-memory ownCloud and checks
; where the files landed.
%import syslib
%import emudbg
%import view
%import rtf
%import cloudx
%zeropage basicsafe

main {
    ; script bytes: key codes, $FF = GIF frame (run_saveastest.sh SHOT=1), $00 = end. 20 = backspace, $11 = down, 136 = F7, 27 = Esc
    ; 1) SD: F7 new folder LETTERS (the only folder: row 0), Up = list keys, Enter = open, name "mom", Enter
    ubyte[] k1 = [136, iso:'L',iso:'E',iso:'T',iso:'T',iso:'E',iso:'R',iso:'S', 13,
                  $91, 13, 20,20,20,20,20,20,20,20,20,20,20,20, iso:'m',iso:'o',iso:'m', $ff, 13, 0]
    ; 2) SD again, same folder and name: Enter, then "Replace?" -> y
    ubyte[] k2 = [13, iso:'y', 0]
    ; 3) SD: Up selects "..", Enter goes up to /, then Esc = cancel: must CD back to /LETTERS
    ubyte[] k3 = [$91, 13, 27, 0]
    ; 4) ownCloud: F7 Reports, down to it (Photos first), Enter, name "q3", Enter
    ubyte[] k4 = [136, iso:'R',iso:'e',iso:'p',iso:'o',iso:'r',iso:'t',iso:'s', 13,
                  $11, 13, 20,20,20,20,20,20,20, iso:'q',iso:'3', $ff, 13, 0]
    ; 5) ownCloud Save As, starts in Reports with q3.rtf: Enter (same file: overwrites its own version)
    ubyte[] k5 = [13, 0]
    uword script
    ubyte sp
    ubyte idle
    bool armed

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
                } else if k == $ff {
                    if idle >= 60 {
                        poke($9fb5, 1)
                        sp++
                        idle = 0
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
        log(iso:"] cwd=[")
        log(diskio.curdir())
        log(iso:"]\n")
    }

    ; never runs: keeps the routines the bank libraries call from being optimised away in this build
    sub keepalive() {
        view.draw_box(0, 0, 1, 1)
        view.put(0, 0, iso:"", 0, 0)
        view.num(0, 0, 0, 0, 0)
        view.poll_mouse()
        view.draw_status()
        void view.dialog_input(iso:"", view.nbuf, 1)
        void view.dialog_yesno(iso:"")
        view.ensure_ext()
        view.copy_name_to_buf()
        vid.fill(0, 0, 1, 0, 0)
        diskio.delete(iso:"")
        void diskio.load_raw(iso:"", 0)
        void rtf.import(iso:"")
        void rtf.export(iso:"")
        view.set_filename(iso:"")
    }

    sub start() {
        if sp == 250 and idle == 251
            keepalive()
        vid.load_fonts()
        vid.gfx_init()
        view.init()
        doc.init_doc()
        doc.insert_char(iso:'A')
        view.set_filename(iso:"untitled.rtf")
        view.set_status(iso:"save as test")
        view.redraw_everything()
        sys.set_irq(&irq)
        if not cloudx.load() {
            log(iso:"LOAD failed\n")
            log(iso:"SAVEAS done\n")
            repeat {}
        }
        play(&k1)
        cloudx.cl_save(2)
        status(iso:"SD_NEWFOLDER_SAVE")
        doc.insert_char(iso:'B')
        play(&k2)
        cloudx.cl_save(2)
        status(iso:"SD_REPLACE")
        play(&k3)
        cloudx.cl_save(2)
        status(iso:"SD_CANCEL")
        doc.insert_char(iso:'C')
        play(&k4)
        cloudx.cl_save(1)
        status(iso:"OC_NEWFOLDER_SAVE")
        doc.insert_char(iso:'D')
        play(&k5)
        cloudx.cl_save(1)
        status(iso:"OC_SAVEAS_SAME")
        log(iso:"SAVEAS done\n")
        repeat {}
    }
}
