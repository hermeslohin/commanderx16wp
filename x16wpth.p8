; x16wpth.p8 - X16 Write's theme loader as a bank library: X16WPTH.BIN. X16 Write's main RAM is full,
; so the part of theme.p8 that reads theme files (init, next, load) runs here, and theme.p8 in the main
; program keeps only the role table, the drawing and Quill.
; It takes no RAM of its own: X16 Write loads it each time it is needed (at start and when Quill is
; clicked) into RAM bank 55 at $A400, over vid.p8's compose buffers ($A400-$ADFF, idle then), and the
; theme file is read into vid.p8's render buffers at $A000 (also idle). run() gets the addresses of
; the main program's theme.rl, theme.dk, theme.msg and theme.cur and copies its results there.
; Without this file X16 Write is shown in the built-in Sunset Arcade colours (and without Quill).

%address  $A400
%memtop   $AE00
%output   library

%import syslib
%import theme

main {
    %jmptable (
        th.run,         ; $A403  r0..r3 = &theme.rl, &theme.dk, &theme.msg, &theme.cur (the WP's), r4L = 0: the
                        ;        saved theme, 1: the next one -> A false if there are no theme files
    )

    sub start() {
    }
}

th {
    sub run() -> bool {
        uword prl = cx16.r0
        uword pdk = cx16.r1
        uword pmsg = cx16.r2
        uword pcur = cx16.r3
        bool ok = true
        theme.tbank = 55
        theme.tbuf = $a000
        theme.cur = @(pcur)
        if cx16.r4L == 0
            theme.init()
        else
            ok = theme.next()
        sys.memcopy(&theme.rl, prl, 64)
        sys.memcopy(&theme.dk, pdk, 32)
        sys.memcopy(&theme.msg + 7, pmsg + 7, 16)
        @(pcur) = theme.cur
        return ok and theme.cur != 0
    }
}
