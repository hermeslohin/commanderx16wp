#!/usr/bin/env python3
"""mkthemes.py - writes the X16 Office theme files X16THEME1.BIN .. X16THEME6.BIN.

The same script is in every X16 Office repository (keep the copies identical); theme.p8 there
reads the files (see its header for the layout). Usage: mkthemes.py <output dir>

Each theme keeps the meaning of the 16 colour indexes (0 ink, 1 paper, 2 red, 3 cyan, 4 purple,
5 green, 6 blue, 7 yellow, 8 orange, 9 brown, 10 light red, 11 dark grey, 12 grey, 13 light green,
14 light blue, 15 light grey) so documents look right in all of them; it chooses the actual colours,
which colour each part of the screen uses (the roles), the desk pattern, 16 glyphs and Quill.
"""
import sys
from pathlib import Path

B, W, RED, CYAN, PUR, GRN, BLU, YEL, ORA, BRN, LRED, DGR, GRY, LGRN, LBLU, LGR = range(16)

ROLES = [
    "DESK", "DESK_A", "DESK_B", "BORDER",
    "TTL_CH", "TTL", "TTL_NAME", "TTL_TXT", "TTL_WARN", "QUIT",
    "TOOL", "BTN", "BTN_ON", "BTN_OFF", "BTN_1", "BTN_2", "BTN_3", "BTN_4", "FIELD", "FIELD_HI",
    "STRIP", "SW_T0", "SW_T1", "SW_B0", "SW_B1", "SW_INK",
    "BAR", "BAR_DIM",
    "TAPE", "TAPE_CAP", "TAPE_ALT",
    "PAPER", "PAPER_DIM", "MARG", "MARG_L", "MARG_R", "SHADOW", "PTOP_CH", "PTOP", "PTOP_MASK", "PTOP_LBL",
    "SEL", "SEL_DIM", "HEAD_ON", "HEAD_OFF",
    "STAT", "STAT_LBL", "STAT_HI",
    "SCROLL", "THUMB",
    "DLG", "DLG_TTL", "DLG_WARN", "DLG_BTN", "DLG_EDGE", "FOOT",
    "HDR2", "ROWHDR", "FBAR", "GRID", "CHIP_OK",
]
assert len(ROLES) <= 64


def P(bg, fg):
    """a colour pair: (bg << 4) | fg (buttons: face, glyph)"""
    return (bg << 4) | fg


# Sunset Arcade: the built-in roles in theme.p8 (they must match theme.rl there)
SUNSET = dict(
    DESK=B, DESK_A=7, DESK_B=13, BORDER=B,
    TTL_CH=240, TTL=P(ORA, RED), TTL_NAME=P(B, YEL), TTL_TXT=P(B, W), TTL_WARN=LRED, QUIT=P(RED, B),
    TOOL=DGR, BTN=P(GRY, W), BTN_ON=P(YEL, B), BTN_OFF=P(GRY, DGR), BTN_1=P(RED, B), BTN_2=P(ORA, B),
    BTN_3=P(CYAN, B), BTN_4=P(YEL, B), FIELD=P(W, B), FIELD_HI=BLU,
    STRIP=P(B, W), SW_T0=0, SW_T1=0, SW_B0=0, SW_B1=0, SW_INK=B,
    BAR=P(LGR, B), BAR_DIM=DGR,
    TAPE=P(YEL, B), TAPE_CAP=RED, TAPE_ALT=P(ORA, B),
    PAPER=P(W, B), PAPER_DIM=LGR, MARG=P(B, B), MARG_L=32, MARG_R=32, SHADOW=DGR,
    PTOP_CH=240, PTOP=P(ORA, RED), PTOP_MASK=0, PTOP_LBL=P(B, YEL),
    SEL=P(RED, B), SEL_DIM=P(LGR, B), HEAD_ON=P(RED, B), HEAD_OFF=P(PUR, B),
    STAT=P(B, W), STAT_LBL=YEL, STAT_HI=YEL,
    SCROLL=P(B, RED), THUMB=RED,
    DLG=P(LGR, B), DLG_TTL=P(PUR, B), DLG_WARN=P(RED, W), DLG_BTN=P(YEL, B), DLG_EDGE=B, FOOT=P(LGR, DGR),
    HDR2=P(DGR, W), ROWHDR=P(B, GRY), FBAR=P(B, W), GRID=LGR, CHIP_OK=LGRN,
)

# glyphs, 8 rows each, top row first, bit 7 = left pixel
GL = dict(
    stripe=[0xff, 0xff, 0xff, 0xdd, 0xaa, 0x44, 0, 0], star=[0, 0, 0, 8, 0, 0, 0, 0],
    star2=[0, 0x10, 0x10, 0x7c, 0x10, 0x10, 0, 0],
    lcap=[0x0f, 0x3f, 0x7f, 0x7f, 0x7f, 0x7f, 0x3f, 0x0f], rcap=[0xf0, 0xfc, 0xfe, 0xfe, 0xfe, 0xfe, 0xfc, 0xf0],
    grain=[0, 0, 0, 0, 0, 0xff, 0, 0], grain2=[0, 0, 0, 0, 7, 0xf8, 0, 0],
    ring=[0, 0x3c, 0x66, 0x42, 0x42, 0x66, 0x3c, 0], tip=[0, 0xc0, 0xf0, 0xfc, 0xfc, 0xf0, 0xc0, 0],
    half=[0, 0x30, 0x30, 0, 0, 0x03, 0x03, 0], vl=[0xc0] * 8, vr=[0x03] * 8, bot=[0, 0, 0, 0, 0, 0, 0xff, 0xff],
    hut=[0xf0] * 8, pebble=[0, 0, 0, 0, 0, 0x0c, 0x0c, 0], shell=[0, 0, 0, 0x18, 0x3c, 0x5a, 0, 0],
    wave=[0, 0, 0, 0, 0x31, 0x4a, 0x84, 0], buckl=[0, 7, 8, 0x7f, 0x7f, 0x3f, 0x3f, 0x1f],
    buckr=[0, 0xe0, 0x10, 0xfe, 0xfe, 0xfc, 0xfc, 0xf8], towel=[0, 0, 0xff, 0, 0, 0xff, 0, 0],
    chalkl=[0, 0, 0x7f, 0x7f, 0x7f, 0x7f, 0, 0], chalkr=[0, 0, 0xfc, 0xfe, 0xfe, 0xfc, 0, 0], felt=[0, 0, 0, 0, 0, 0xff, 0xff, 0xff],
    smile=[0x3c, 0x42, 0xa5, 0x81, 0xa5, 0x99, 0x42, 0x3c], cstar=[0x10, 0x10, 0xfe, 0x38, 0x6c, 0x44, 0, 0],
    plus=[0, 0x10, 0x10, 0x7c, 0x10, 0x10, 0, 0], house=[0x10, 0x28, 0x44, 0xfe, 0x44, 0x54, 0x7c, 0],
    hole=[0, 0x3c, 0x7e, 0x7e, 0x7e, 0x7e, 0x3c, 0], knot=[0, 0, 0x3c, 0x42, 0x3c, 0, 0, 0],
    flake=[0x10, 0x54, 0x38, 0xfe, 0x38, 0x54, 0x10, 0], plaid=[0x18, 0x18, 0x18, 0xff, 0xff, 0x18, 0x18, 0x18],
    mitten=[0x0c, 0x1e, 0x5e, 0x7e, 0x7e, 0x7e, 0x3c, 0x3c], mug=[0, 0xf8, 0xfe, 0xfa, 0xfe, 0xf8, 0xf0, 0],
    snow=[0xff, 0xff, 0xff, 0xff, 0x7e, 0x66, 0, 0],
)

# Quill: 16x8, one hex digit per pixel = colour index, 0 = transparent, f = the theme's band colour
QUILL = [
    ["0aaf777777771000", "aaaf777777771100", "aaaf77b77b771100", "aaaf77b77b7711c0",
     "aaaf7777777711c0", "aaaf727777271100", "aaaf777222771100", "0aaf777777771000"],
    ["0aaf777777771000", "aaaf777777771100", "aaaf777777771100", "aaaf7bb77bb711c0",
     "aaaf7777777711c0", "aaaf727777271100", "aaaf777222771100", "0aaf777777771000"],
    ["0aaf777777771000", "aaaf77b77b771100", "aaaf7b7bb7b71100", "aaaf7777777711c0",
     "aaaf7277772711c0", "aaaf722222271100", "aaaf777222771100", "0aaf777777771000"],
]


def desk(default, marks):
    """32-entry desk table: default entry, {index: entry}; an entry is (fg << 4) | glyph slot"""
    t = [default] * 32
    for i, e in marks.items():
        t[i] = e
    return t


THEMES = [
    dict(name="Sunset Arcade",
         pal=["213", "FED", "F48", "4DD", "98F", "4B4", "36E", "FD4", "F93", "A52", "F9B", "326", "659", "BFA", "8CF", "CBF"],
         glyphs={240: "stripe", 241: "star", 242: "star2"},
         desk=desk(P(GRY, 0), {3: P(GRY, 2), 11: P(GRY, 1), 22: P(GRY, 1)}),
         band=LGR, roles={}),
    dict(name="Crayon Desk",
         pal=["223", "FFE", "E54", "4CC", "94A", "4A5", "4AE", "FC3", "C96", "864", "F9A", "532", "B85", "BEB", "8CF", "EDB"],
         glyphs={240: "ring", 241: "grain", 242: "grain2", 245: "tip"},
         desk=desk(P(GRY, 0), {**{i: P(GRY, 1) for i in list(range(7)) + list(range(16, 23))}, 7: P(GRY, 2), 23: P(GRY, 2)}),
         band=GRY,
         roles=dict(DESK=ORA, DESK_A=1, DESK_B=11, BORDER=BRN,
                    TTL_CH=32, TTL=P(BRN, BRN), TTL_NAME=P(RED, W), TTL_TXT=P(BRN, LGR), TTL_WARN=YEL, QUIT=P(B, W),
                    TOOL=RED, BTN=P(W, B), BTN_OFF=P(W, GRY), BTN_1=P(W, B), BTN_2=P(W, B), BTN_3=P(W, B), BTN_4=P(W, B),
                    FIELD_HI=RED, STRIP=P(YEL, B), SW_T1=245, SW_INK=BRN, BAR_DIM=BRN,
                    TAPE=P(LGR, DGR), TAPE_CAP=LGR, TAPE_ALT=P(LRED, B),
                    MARG=P(W, B), SHADOW=BRN, PTOP_CH=240, PTOP=P(W, GRY), PTOP_LBL=P(YEL, B),
                    SEL=P(LBLU, B), HEAD_OFF=P(BRN, LGR), STAT=P(LGR, B), STAT_LBL=BRN, STAT_HI=RED,
                    SCROLL=P(BRN, LGR), THUMB=LGR, DLG_TTL=P(BRN, W), FOOT=P(LGR, BRN),
                    HDR2=P(LGR, B), ROWHDR=P(ORA, DGR), FBAR=P(W, B))),
    dict(name="Comic Book",
         pal=["111", "FFF", "E22", "2BE", "93C", "3A3", "25D", "FE2", "F82", "842", "F9A", "444", "999", "AE8", "9DF", "FE9"],
         glyphs={240: "bot", 241: "half", 245: "vl", 246: "vr"},
         desk=desk(P(LRED, 1), {}),
         band=GRY,
         roles=dict(DESK=LGR, DESK_A=1, DESK_B=1, BORDER=B,
                    TTL_CH=32, TTL=P(RED, RED), TTL_NAME=P(RED, YEL), TTL_TXT=P(RED, W), TTL_WARN=YEL, QUIT=P(B, W),
                    TOOL=CYAN, BTN=P(W, B), BTN_OFF=P(W, GRY), BTN_1=P(W, B), BTN_2=P(W, B), BTN_3=P(W, B), BTN_4=P(W, B),
                    FIELD_HI=RED, STRIP=P(W, B), BAR=P(LGR, B),
                    TAPE=P(W, B), TAPE_CAP=W, TAPE_ALT=P(YEL, B),
                    MARG=P(W, B), MARG_L=245, MARG_R=246, SHADOW=B, PTOP_CH=240, PTOP=P(LGR, B), PTOP_LBL=P(YEL, B),
                    SEL=P(LBLU, B), HEAD_ON=P(RED, W), HEAD_OFF=P(CYAN, B), STAT=P(W, B), STAT_LBL=RED, STAT_HI=BLU,
                    SCROLL=P(W, B), THUMB=B, DLG=P(LGR, B), DLG_TTL=P(YEL, B), DLG_BTN=P(CYAN, B), FOOT=P(W, DGR),
                    HDR2=P(CYAN, B), ROWHDR=P(LGR, B), FBAR=P(W, B), GRID=GRY)),
    dict(name="Beach Hut",
         pal=["234", "FFE", "E55", "2CC", "96C", "3A6", "28C", "FD4", "FA6", "A86", "F9A", "457", "998", "BEC", "AEF", "EDA"],
         glyphs={240: "hut", 241: "pebble", 242: "shell", 245: "wave", 246: "buckl", 247: "buckr", 248: "towel"},
         desk=desk(P(GRY, 0), {5: P(LRED, 2), 14: P(GRY, 1), 27: P(GRY, 1)}),
         band=CYAN,
         roles=dict(DESK=LGR, BORDER=BRN,
                    TTL_CH=240, TTL=P(W, CYAN), TTL_NAME=P(W, B), TTL_TXT=P(W, B), TTL_WARN=RED, QUIT=P(RED, W),
                    TOOL=BLU, BTN=P(LGR, B), BTN_OFF=P(LGR, GRY), BTN_1=P(LGR, B), BTN_2=P(LGR, B), BTN_3=P(LGR, B),
                    BTN_4=P(LGR, B), STRIP=P(LBLU, B), SW_T0=246, SW_T1=247, SW_B0=248, SW_B1=248, SW_INK=W,
                    TAPE=P(W, BLU), TAPE_CAP=W, TAPE_ALT=P(ORA, B),
                    MARG=P(W, B), SHADOW=BRN, PTOP_CH=245, PTOP=P(LBLU, BLU), PTOP_LBL=P(YEL, B),
                    SEL=P(LBLU, B), HEAD_ON=P(CYAN, B), HEAD_OFF=P(LBLU, B), STAT=P(LBLU, B), STAT_LBL=BLU, STAT_HI=BLU,
                    SCROLL=P(BRN, W), THUMB=CYAN, DLG_TTL=P(BLU, W), DLG_EDGE=BRN,
                    HDR2=P(BLU, W), ROWHDR=P(LGR, DGR), FBAR=P(W, B), GRID=LBLU, CHIP_OK=GRN)),
    dict(name="Chalkboard",
         pal=["222", "FFF", "D44", "3BB", "84B", "384", "36C", "FD5", "E83", "964", "F99", "243", "8A9", "ADA", "9CE", "DCA"],
         glyphs={241: "smile", 242: "cstar", 245: "plus", 246: "house", 247: "chalkl", 248: "chalkr", 250: "hole"},
         desk=desk(P(GRY, 0), {3: P(GRY, 1), 17: P(GRY, 2), 26: P(GRY, 6)}),
         band=GRY,
         roles=dict(DESK=DGR, BORDER=BRN,
                    TTL_CH=32, TTL=P(BRN, BRN), TTL_NAME=P(BRN, W), TTL_TXT=P(BRN, LGR), TTL_WARN=YEL, QUIT=P(RED, W),
                    TOOL=LGR, BTN=P(W, B), BTN_OFF=P(W, GRY), BTN_1=P(W, B), BTN_2=P(W, B), BTN_3=P(W, B), BTN_4=P(W, B),
                    FIELD_HI=RED, STRIP=P(LGR, B), SW_T0=247, SW_T1=248, SW_B0=0, SW_B1=0, SW_INK=DGR, BAR_DIM=BRN,
                    TAPE=P(YEL, B), TAPE_CAP=YEL, TAPE_ALT=P(ORA, B),
                    MARG=P(W, B), SHADOW=BRN, PTOP_CH=250, PTOP=P(W, DGR), PTOP_MASK=15, PTOP_LBL=P(YEL, B),
                    SEL=P(LBLU, B), HEAD_ON=P(YEL, B), HEAD_OFF=P(LGR, B), STAT=P(LGR, B), STAT_LBL=BRN, STAT_HI=RED,
                    SCROLL=P(BRN, W), THUMB=LGR, DLG_TTL=P(GRN, W), DLG_EDGE=BRN, FOOT=P(LGR, BRN),
                    HDR2=P(BRN, W), ROWHDR=P(DGR, LGRN), FBAR=P(W, B))),
    dict(name="Winter Cabin",
         pal=["321", "FFE", "C33", "4AA", "849", "364", "46A", "FC5", "E84", "A63", "E99", "354", "DA6", "9C9", "ADF", "EDC"],
         glyphs={240: "plaid", 241: "grain", 242: "knot", 245: "flake", 246: "mitten", 247: "mug", 248: "snow"},
         desk=desk(P(BRN, 0), {**{i: P(BRN, 1) for i in list(range(5)) + list(range(16, 21))}, 9: P(BRN, 2), 26: P(W, 5)}),
         band=RED,
         roles=dict(DESK=GRY, DESK_A=1, DESK_B=11, BORDER=BRN,
                    TTL_CH=240, TTL=P(RED, DGR), TTL_NAME=P(LGR, B), TTL_TXT=P(LGR, B), TTL_WARN=RED, QUIT=P(LGR, RED),
                    TOOL=DGR, BTN=P(LGR, B), BTN_OFF=P(LGR, GRY), BTN_1=P(LGR, B), BTN_2=P(LGR, B), BTN_3=P(LGR, B),
                    BTN_4=P(LGR, B), FIELD_HI=RED, STRIP=P(LGR, B), SW_T0=246, SW_T1=32, SW_B0=247, SW_B1=32, SW_INK=BRN,
                    BAR_DIM=BRN, TAPE=P(LGR, BRN), TAPE_CAP=LGR, TAPE_ALT=P(LRED, B),
                    MARG=P(W, B), SHADOW=BRN, PTOP_CH=248, PTOP=P(LBLU, W), PTOP_LBL=P(YEL, B),
                    SEL=P(YEL, B), HEAD_ON=P(RED, W), HEAD_OFF=P(DGR, LGR), STAT=P(LGR, B), STAT_LBL=GRN, STAT_HI=RED,
                    SCROLL=P(DGR, LGR), THUMB=LGR, DLG_TTL=P(GRN, W), DLG_EDGE=BRN, FOOT=P(LGR, BRN),
                    HDR2=P(DGR, W), ROWHDR=P(GRY, B), FBAR=P(W, B), CHIP_OK=GRN)),
]


def build(t):
    roles = dict(SUNSET)
    for k in t["roles"]:
        assert k in roles, k
    roles.update(t["roles"])
    rl = [roles[r] for r in ROLES] + [0] * (64 - len(ROLES))
    assert all(0 <= v <= 255 for v in rl)
    name = t["name"].encode("latin-1")
    assert len(name) <= 16
    pal = b"".join(bytes([int(h[1:], 16), int(h[0], 16)]) for h in t["pal"])
    glyphs = {243: "lcap", 244: "rcap", **t["glyphs"]}
    gl = b"".join(bytes(GL[glyphs[c]]) if c in glyphs else bytes(8) for c in range(240, 256))
    q = bytearray()
    for frame in QUILL:
        for row in frame:
            row = row.replace("f", "%x" % t["band"])
            q += bytes(int(row[i:i + 2], 16) for i in range(0, 16, 2))
    data = (b"X16T" + bytes([1, 0, 0, 0]) + name.ljust(16, b" ") + pal + bytes(rl) + bytes(t["desk"])
            + gl + bytes(q))
    assert len(pal) == 32 and len(t["desk"]) == 32 and len(gl) == 128 and len(q) == 192
    assert len(data) == 472, len(data)
    return data


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    for i, t in enumerate(THEMES, 1):
        (out / f"X16THEME{i}.BIN").write_bytes(build(t))
    print(f"wrote {len(THEMES)} themes to {out}")


if __name__ == "__main__":
    main()
