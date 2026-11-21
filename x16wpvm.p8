; x16wpvm.p8 - X16 Write's paged line store as a bank library: X16WPVM.BIN, RAM bank 58 at $A000.
; With it a document can be longer than the RAM: the line slots are in 32-line sections of 8 KB, and
; the sections that don't fit in the frame banks are kept in swap files on the SD card (memory map and
; tables: vmtab.p8). doc.p8 (main RAM) finds a section's frame bank itself; only when the section is
; not in RAM it calls fault() here, which frees a frame (clock / second chance: a frame used since the
; last sweep gets another round; a changed one is written to its swap file first) and reads the
; section back from its swap file if it has one.
;
; Swap files: //X16WPSWP/S000 .. S255 on the SD card (absolute, so Save As changing the current folder
; doesn't matter). The emulator's host file system has no absolute paths: there they are X16WPSW000 ..
; in the folder X16 Write started in. setup() and quit() delete them. Each file is a whole 8 KB bank.
; The library can't map another RAM bank while it runs from bank 58, so the 8 KB transfer itself is
; doc.vm_xfer in main RAM (its address comes in setup()); the library opens and closes the files.

%address  $A000
%memtop   $B000
%output   library

%import syslib
%import vmtab

main {
    %jmptable (
        vm.setup,       ; $A003  r0 = &doc.vm_xfer -> A true if swap files can be written
        vm.fault,       ; $A006  r0L = section -> A its frame bank (now in RAM)
        vm.quit,        ; $A009  delete the swap files
    )

    sub start() {
    }
}

vm {
    const ubyte LFN = 6                 ; not 12 / 13: an RTF file may be open for reading or writing
    uword xfer
    ubyte hand                          ; clock hand (a bank number)
    ubyte nlen                          ; the section number goes at name + nlen
    ubyte roff                          ; read with name + roff (without the "@" / "@:")
    ubyte[28] name
    ubyte[24] dcmd

    sub setup() -> bool {
        xfer = cx16.r0
        hand = 0
        void cmd(iso:"MD//:X16WPSWP")
        if try(iso:"@//X16WPSWP/:S", 1)
            return true
        return try(iso:"@:X16WPSW", 2)          ; emulator host file system
    }

    ; use this name prefix if a swap file can be written with it (a test file, deleted again)
    sub try(str pfx, ubyte ro) -> bool {
        nlen = 0
        while pfx[nlen] != 0 {
            name[nlen] = pfx[nlen]
            nlen++
        }
        roff = ro
        bool ok = io(255, vmt.VMBANK, true)
        quit()
        return ok
    }

    ; "S//X16WPSWP/:S*" or "S:X16WPSW*": delete every swap file
    sub quit() {
        ubyte i = 1
        dcmd[0] = iso:'S'
        while i < nlen {
            dcmd[i] = name[i]
            i++
        }
        dcmd[i] = iso:'*'
        dcmd[i + 1] = 0
        void cmd(&dcmd)
    }

    uword[4] keep                       ; fault() leaves cx16.r0 .. r3 as they were

    sub fault() -> ubyte {
        ubyte sec = cx16.r0L                    ; (before memcopy: its arguments go in r0 / r1)
        sys.memcopy(&cx16.r0, &keep, 8)
        ubyte old
        ubyte u
        ubyte b
        uword n = 0
        while true {
            hand++
            b = hand
            u = vmt.fruse[b]
            if u == 0
                continue
            n++
            if n < 600 and u & vmt.F_REF != 0 {
                vmt.fruse[b] = u & ~vmt.F_REF           ; used lately: another round
                continue
            }
            old = vmt.frsec[b]
            if u & vmt.F_DIRTY != 0 {
                if io(old, b, true)
                    vmt.secst[old] |= vmt.S_DISK
                else {
                    vmt.stat |= vmt.ST_BROKEN           ; no new lines from now on
                    if n < 600
                        continue                        ; look for one that needs no writing
                }
            }
            vmt.secfr[old] = 0
            break
        }
        if vmt.secst[sec] & vmt.S_DISK != 0 {
            if not io(sec, b, false)
                vmt.stat |= vmt.ST_BROKEN
        }
        vmt.secfr[sec] = b
        vmt.frsec[b] = sec
        vmt.fruse[b] = vmt.F_FRAME | vmt.F_REF
        sys.memcopy(&keep, &cx16.r0, 8)
        return b
    }

    ; section sec's swap file <-> RAM bank b (all 8 KB)
    sub io(ubyte sec, ubyte b, bool wr) -> bool {
        ubyte i = nlen
        ubyte u
        name[i] = iso:'0' + sec / 100
        name[i + 1] = iso:'0' + sec / 10 % 10
        name[i + 2] = iso:'0' + sec % 10
        i += 3
        uword nm = &name
        if wr {
            name[i] = iso:','
            name[i + 1] = iso:'S'
            name[i + 2] = iso:','
            name[i + 3] = iso:'W'
            i += 4
        } else {
            nm += roff
            i -= roff
        }
        cbm.SETNAM(i, nm)
        cbm.SETLFS(LFN, 8, LFN)
        void cbm.OPEN()
        if wr
            cbm.CHKOUT(LFN)
        else
            void cbm.CHKIN(LFN)
        cx16.r0L = b
        cx16.r0H = wr as ubyte
        void call(xfer)
        u = cx16.r1L
        cbm.CLRCHN()
        cbm.CLOSE(LFN)
        return dos_ok() and u == 0
    }

    ; a DOS command; true if the drive says 0x (00 OK, 01 FILES SCRATCHED)
    sub cmd(uword c) -> bool {
        ubyte n = 0
        while @(c + n) != 0
            n++
        cbm.SETNAM(n, c)
        cbm.SETLFS(15, 8, 15)
        void cbm.OPEN()
        return status()
    }

    sub dos_ok() -> bool {
        cbm.SETNAM(0, 0)
        cbm.SETLFS(15, 8, 15)
        void cbm.OPEN()
        return status()
    }

    ; read the drive's status from channel 15 (open), then close it
    sub status() -> bool {
        void cbm.CHKIN(15)
        ubyte a = cbm.CHRIN()
        while cbm.READST() == 0
            void cbm.CHRIN()
        cbm.CLRCHN()
        cbm.CLOSE(15)
        return a == iso:'0'
    }
}
