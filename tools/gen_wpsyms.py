#!/usr/bin/env python3
"""Generate wpsyms.p8: the bank-62 cloud library's view of X16 Write's main-RAM routines.

The cloud UI (x16wpcl.p8) is a separate bank library, so it cannot link against x16wp.prg.
This script reads the WP build's symbol list (x16wp.vice-mon-list) and assembly (x16wp.asm) and
emits, for every routine the library needs:
  * an `extsub @bank 62 $addr` (JSRFAR: the callee may switch RAM banks, JSRFAR maps bank 62
    back before returning into the library), and
  * for multi-parameter Prog8 subs, a wrapper that stores the arguments into the callee's
    static parameter variables first (single int parameters travel in A / AY instead).
CHECK = address of vid.text; the WP passes its own value at init and the library refuses to run
if the two builds don't match.

A sub can name its own bank (7th field): load_raw59 is diskio.load_raw called through JSRFAR with RAM
bank 59 mapped, so X16WPCL.BIN (bank 62) can load X16WPSA.BIN into bank 59.

Bank 57 is the tables library (x16wptb.p8): it gets its own lists, TB_SUBS / TB_VARS; bank 54 is the
pictures library (x16wppi.p8) and bank 56 its loading library (x16wppl.p8): PI_SUBS / PI_VARS.

usage: gen_wpsyms.py <build-dir> <out.p8> [program-name, default x16wp] [bank, default 62]
"""
import re
import sys
from pathlib import Path

BANK = 62

# (alias, block, sub, [(param, type)], return type or None)
SUBS = [
    ("vid_text", "vid", "text", [("col", "ubyte"), ("row", "ubyte"), ("s", "uword"), ("sty", "ubyte"), ("fg", "ubyte"), ("bg", "ubyte")], None),
    ("vid_fill", "vid", "fill", [("col", "ubyte"), ("row", "ubyte"), ("n", "ubyte"), ("fg", "ubyte"), ("bg", "ubyte")], None),
    ("draw_box", "view", "draw_box", [("x", "ubyte"), ("y", "ubyte"), ("w", "ubyte"), ("h", "ubyte")], None),
    ("put", "view", "put", [("col", "ubyte"), ("row", "ubyte"), ("s", "uword"), ("fg", "ubyte"), ("bg", "ubyte")], None),
    ("num", "view", "num", [("col", "ubyte"), ("row", "ubyte"), ("n", "uword"), ("fg", "ubyte"), ("bg", "ubyte")], None),
    ("poll_mouse", "view", "poll_mouse", [], None),
    ("set_status", "view", "set_status", [("s", "uword")], None),
    ("draw_status", "view", "draw_status", [], None),
    ("redraw_everything", "view", "redraw_everything", [], None),
    ("dialog_input", "view", "dialog_input", [("title", "uword"), ("buf", "uword"), ("maxlen", "ubyte")], "bool"),
    ("dialog_yesno", "view", "dialog_yesno", [("msg", "uword")], "bool"),
    ("ensure_ext", "view", "ensure_ext", [], None),
    ("copy_name_to_buf", "view", "copy_name_to_buf", [], None),
    ("set_filename", "view", "set_filename", [("s", "uword")], None),
    ("rtf_import", "rtf", "import", [("name", "uword")], "bool"),
    ("rtf_export", "rtf", "export", [("name", "uword")], "bool"),
    ("disk_delete", "diskio", "delete", [("filenameptr", "uword")], None),
    ("load_raw59", "diskio", "load_raw", [("filenameptr", "uword"), ("startaddress", "uword")], "uword", 59),
]
# (alias, block, var, kind)  kind: ubyte/byte/uword/bool/addr, "?" suffix = optional
VARS = [
    ("mouse_btn", "view", "mouse_btn", "ubyte"),
    ("mouse_cx", "view", "mouse_cx", "ubyte"),
    ("mouse_cy", "view", "mouse_cy", "ubyte"),
    ("mouse_wheel", "view", "mouse_wheel", "byte"),
    ("vtop", "view", "vtop", "uword"),
    ("modified", "doc", "modified", "bool"),
    ("nbuf", "view", "nbuf", "addr"),
    # Quill's hop counter: = 32 is theme.cheer() (inlined in the WP). Optional ("?"): a test program
    # that never calls theme.cheer() has no such variable; the library then gets a dummy one.
    ("theme_hop", "theme", "hop", "ubyte?"),
]

# the tables library (x16wptb.p8, bank 57) needs the document model and the RTF reader/writer
TB_SUBS = [s for s in SUBS if s[0] in ("vid_text", "vid_fill", "draw_box", "put", "num", "poll_mouse",
                                         "set_status", "draw_status", "redraw_everything", "dialog_input")] + [
    ("ld", "doc", "ld", [("idx", "uword"), ("dst", "uword")], None),
    ("st", "doc", "st", [("idx", "uword"), ("src", "uword")], None),
    ("meta", "doc", "meta", [("idx", "uword"), ("off", "ubyte")], "ubyte"),
    ("setmeta", "doc", "setmeta", [("idx", "uword"), ("off", "ubyte"), ("v", "ubyte")], None),
    ("insert_blank", "doc", "insert_blank", [("idx", "uword")], "bool"),
    ("delete_line", "doc", "delete_line", [("idx", "uword")], None),
    ("mark_range", "doc", "mark_range", [("l1", "uword"), ("l2", "uword")], None),
    ("mark_from", "doc", "mark_from", [("l", "uword")], None),
    ("sel_norm", "doc", "sel_norm", [], None),
    ("delsel_plain", "doc", "delsel_plain", [], None),
    ("para_last", "doc", "para_last", [("l", "uword")], "uword"),
    ("clip_get", "doc", "clip_get", [("k", "uword")], None),
    ("flush_para", "rtf", "flush_para", [], None),
    ("put_c", "rtf", "put_c", [("c", "ubyte")], None),
    ("put_n", "rtf", "put_n", [("v", "uword")], None),
    ("put_runs", "rtf", "put_runs", [("b", "uword"), ("a", "ubyte"), ("e", "ubyte")], None),
]
TB_VARS = [v for v in VARS if v[0] in ("mouse_btn", "mouse_cx", "mouse_cy", "modified", "nbuf")] + [
    ("nlines", "doc", "nlines", "uword"),
    ("curline", "doc", "curline", "uword"),
    ("curcol", "doc", "curcol", "ubyte"),
    ("sel_active", "doc", "sel_active", "bool"),
    ("sel_l", "doc", "sel_l", "uword"),
    ("sel_c", "doc", "sel_c", "ubyte"),
    ("sn_l1", "doc", "sn_l1", "uword"),
    ("sn_c1", "doc", "sn_c1", "ubyte"),
    ("sn_l2", "doc", "sn_l2", "uword"),
    ("sn_c2", "doc", "sn_c2", "ubyte"),
    ("need_repag", "doc", "need_repag", "bool"),
    ("full_error", "doc", "full_error", "bool"),
    ("rd_mode", "doc", "rd_mode", "ubyte"),
    ("tsty", "doc", "tsty", "ubyte"),
    ("tfg", "doc", "tfg", "ubyte"),
    ("tbg", "doc", "tbg", "ubyte"),
    ("LB", "doc", "LB", "uword"),
    ("sbch", "doc", "sbch", "uword"),
    ("sbsty", "doc", "sbsty", "uword"),
    ("sbcol", "doc", "sbcol", "uword"),
    ("clip_n", "doc", "clip_n", "uword"),
    ("cg_ch", "doc", "cg_ch", "ubyte"),
    ("cg_sty", "doc", "cg_sty", "ubyte"),
    ("cg_col", "doc", "cg_col", "ubyte"),
    ("wname", "rtf", "wname", "addr"),
    ("pn", "rtf", "pn", "uword"),
    ("para_open", "rtf", "para_open", "bool"),
    ("first_flush", "rtf", "first_flush", "bool"),
    ("in_row", "rtf", "in_row", "bool"),
]

# the pictures library (x16wppi.p8, bank 54): document model, RTF reader/writer, file reading and the
# bank copy helper doc.bxfer (the library can't switch RAM banks itself)
PI_SUBS = [s for s in TB_SUBS if s[0] in ("set_status", "draw_status", "redraw_everything", "dialog_input",
                                            "ld", "st", "meta", "setmeta", "insert_blank", "delete_line",
                                            "mark_from", "sel_norm", "para_last", "flush_para", "put_c")] + [
    ("delete_selection", "doc", "delete_selection", [], None),
    ("bxfer", "doc", "bxfer", [("b", "ubyte"), ("a", "uword"), ("d", "uword"), ("n", "uword"), ("out", "ubyte")], None),
    ("put_hex", "rtf", "put_hex", [("v", "ubyte")], None),
    ("next_byte", "rtf", "next_byte", [], "ubyte"),
    ("f_open", "diskio", "f_open", [("filenameptr", "uword")], "bool"),
    ("f_read", "diskio", "f_read", [("bufferpointer", "uword"), ("num_bytes", "uword")], "uword"),
    ("f_close", "diskio", "f_close", [], None),
    ("disk_delete", "diskio", "delete", [("filenameptr", "uword")], None),
    ("cloud_menu", "cloudx", "menu", [("which", "ubyte")], "ubyte"),
]
PI_VARS = [v for v in TB_VARS if v[0] in ("modified", "nbuf", "nlines", "curline", "curcol", "sel_active",
                                            "sel_l", "sel_c", "sn_l1", "sn_c1", "sn_l2", "sn_c2", "need_repag",
                                            "full_error", "rd_mode", "LB", "sbch", "first_flush", "para_open",
                                            "pn")] + [
    ("LBV", "doc", "LBV", "uword"),
    ("theme_hop", "theme", "hop", "ubyte?"),
]


def main(build: Path, out: Path, prog: str = "x16wp", bank: str = "62"):
    global BANK, SUBS, VARS
    BANK = int(bank)
    if BANK == 57:
        SUBS, VARS = TB_SUBS, TB_VARS
    elif BANK in (54, 56):
        SUBS, VARS = PI_SUBS, PI_VARS
    syms = {}
    for line in (build / f"{prog}.vice-mon-list").read_text().splitlines():
        m = re.match(r"al ([0-9a-fA-F]+) \.(\S+)", line)
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    asm = (build / f"{prog}.asm").read_text().splitlines()

    def lab(block, *parts):
        for cand in (":".join([f"p8b_{block}"] + [p if p.startswith("p8") else p for p in parts]),
                     ":".join([block] + [p.replace("p8s_", "").replace("p8v_", "") for p in parts])):
            if cand in syms:
                return syms[cand], cand
        raise SystemExit(f"symbol not found: {block} {parts}")

    def reg_params(label):
        """registers used for params if the sub takes 'simple int args via cpu registers'."""
        name = label.split(":")[-1]
        regs = {}
        for i, l in enumerate(asm):
            if re.match(rf"^{re.escape(name)}\s+\.proc", l):
                block = asm[i + 1:i + 8]
                if not any("passed via cpu register" in b for b in block):
                    return None
                for b in block:
                    mm = re.match(r"\s+st([axy])\s+(\S+)", b)
                    if mm:
                        regs[mm.group(2)] = mm.group(1).upper()
                return regs
        raise SystemExit(f"proc not found in asm: {name}")

    o = ["; GENERATED by gen_wpsyms.py from the x16wp build - do not edit.",
         f"; X16 Write main-RAM routines/variables as seen from a bank-{BANK} library.", "", "wp {"]
    check, _ = lab("vid", "p8s_text")
    o.append(f"    const uword CHECK = ${check:04x}")
    for alias, blk, sub, params, ret, *opt in SUBS:
        sbank = opt[0] if opt else BANK
        if opt and BANK != 62:
            continue                        # bank-override helpers are for the bank-62 library only
        addr, label = lab(blk, f"p8s_{sub}")
        regs = reg_params(label)
        retdecl = f" -> {ret} @{'AY' if ret == 'uword' else 'A'}" if ret else ""
        clob = "clobbers(X)" if ret == "uword" else "clobbers(X, Y)" if ret else "clobbers(A, X, Y)"
        if regs is not None:
            # params in registers: A (byte) or AY (word); with 2 byte params A,Y
            ps = []
            for pname, ptype in params:
                r = "".join(v for k, v in regs.items() if k.split("+")[0].endswith(pname))
                r = {"AY": "AY", "A": "A", "Y": "Y", "X": "X"}.get(r, "AY" if ptype == "uword" else "A")
                ps.append(f"{ptype} {pname} @{r}")
            o.append(f"    extsub @bank {sbank} ${addr:04x} = {alias}({', '.join(ps)}) {clob}{retdecl}")
            continue
        o.append(f"    extsub @bank {sbank} ${addr:04x} = x_{alias}() {clob}{retdecl}")
        sig = ", ".join(f"{t} {p}" for p, t in params)
        o.append(f"    sub {alias}({sig}){' -> ' + ret if ret else ''} {{")
        for p, t in params:
            paddr, _ = lab(blk, f"p8s_{sub}", f"p8v_{p}")
            if t == "uword":
                o.append(f"        @(${paddr:04x}) = lsb({p})")
                o.append(f"        @(${paddr + 1:04x}) = msb({p})")
            else:
                o.append(f"        @(${paddr:04x}) = {p}")
        o.append(f"        {'return ' if ret else ''}x_{alias}()")
        o.append("    }")
    def var_addr(blk, var):
        try:
            return lab(blk, f"p8v_{var}")[0]
        except SystemExit:
            # zero-page variable: "p8v_name \t= 51 \t; zp ..." inside the block's .proc
            start = next(i for i, l in enumerate(asm) if re.match(rf"^p8b_{blk}\s+\.proc", l))
            for l in asm[start:]:
                m = re.match(rf"^p8v_{var}\s+=\s+(\d+)\s+;\s+zp", l)
                if m:
                    return int(m.group(1))
                if re.match(r"^\s+\.pend", l) and False:
                    break
            raise SystemExit(f"variable not found: {blk}.{var}")

    for alias, blk, var, kind in VARS:
        if kind.endswith("?"):
            kind = kind[:-1]
            try:
                addr = var_addr(blk, var)
            except (SystemExit, StopIteration):
                o.append(f"    {kind} {alias}")
                continue
        else:
            addr = var_addr(blk, var)
        if kind == "addr":
            o.append(f"    const uword {alias} = ${addr:04x}")
        else:
            o.append(f"    &{kind} {alias} = ${addr:04x}")
    o.append("}")
    out.write_text("\n".join(o) + "\n")
    print(f"wrote {out} (CHECK=${check:04x})")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), *(sys.argv[3:5]))
