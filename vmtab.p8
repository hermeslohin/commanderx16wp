; vmtab.p8 - the document's paged line store: memory map shared by doc.p8 (main RAM) and X16WPVM.BIN
; (x16wpvm.p8, the paging library in RAM bank 58).
;
; Line slots (256 bytes each) are virtual: slot s is in section s / 32, and a section is 32 slots = one
; 8 KB RAM bank. The sections that are in RAM sit in frame banks (5..27, and 64..144 on machines with
; more than 512 KB); the others are in swap files on the SD card, one file per section, written only
; when a changed section has to make room for another one. So a document can be longer than the RAM.
;
; RAM bank 58: X16WPVM.BIN's code at $A000-$AFFF, then these tables (main RAM and the library both
; use them):
;   fruse   per bank number: 0 = not a frame, else F_FRAME | F_REF (used lately) | F_DIRTY (changed)
;   frsec   per frame bank: the section it holds
;   secfr   per section: the frame bank it is in, 0 = not in RAM
;   secst   per section: S_DISK = it has a swap file
;   SLOTMAP one bit per line slot: in use
;   PF      first line of every page (uword[MAXPAGES])
;   stat    ST_BROKEN: a swap file could not be written or read (no more new lines)

vmt {
    %option ignore_unused

    const uword MAXLINES = 8192         ; 256 sections; the line order table fills banks 1..4
    const ubyte MAXPAGES = 255
    const ubyte OBANK = 1               ; line order: 4 bytes a line, 2048 lines a bank, banks 1..4
    const ubyte FBANK0 = 5              ; frame banks 5..27 (every X16), 64.. (more than 512 KB)
    const ubyte FBANK1 = 27
    const ubyte VMBANK = 58

    &ubyte[256] fruse = $b000
    &ubyte[256] frsec = $b100
    &ubyte[256] secfr = $b200
    &ubyte[256] secst = $b300
    const uword SLOTMAP = $b400         ; MAXLINES / 8 bytes
    const uword PF = $b800              ; MAXPAGES words
    &ubyte stat = $ba00
    const uword TABLES = $b000          ; all of the above: TABLES .. STATEND
    const uword STATEND = $ba01

    const ubyte F_FRAME = $80
    const ubyte F_REF = 1
    const ubyte F_DIRTY = 2
    const ubyte S_DISK = 1
    const ubyte ST_BROKEN = 1
}
