#!/usr/bin/env python3
"""Run the real X16 Office hub link server (x16-office-hub/hub) on 127.0.0.1:<port> with an in-memory
ownCloud (the hub's FakeOC test double), for X16 Write's Save As test.

usage: fmhub.py <hub-dir> <key-dir> <out-dir> [port]
  * writes <key-dir>/X16LINK.KEY for device x16-wp-test
  * seeds Documents/seed.txt and Documents/Photos/cat.bin
  * runs until <out-dir>/STOP exists, then dumps Documents/ into <out-dir>/Documents (folders included)
"""
import asyncio
import sys
from pathlib import Path

hub, keydir, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
port = int(sys.argv[4]) if len(sys.argv) > 4 else 6502
sys.path[:0] = [str(hub), str(hub / "tests")]

from fake_oc import FakeOC                               # noqa: E402
from x16hub.link import keys as K                        # noqa: E402
from x16hub.link.server import Limits, LinkServer        # noqa: E402

KEY = bytes(range(140, 172))
DEV = "x16-wp-test"
SEED = b"seed from ownCloud\n"
CAT = bytes((i * 7 + 3) & 255 for i in range(1500))


async def main():
    oc = FakeOC()
    oc.ensure_folder("Documents")
    oc.add("Documents/seed.txt", SEED)
    oc.add("Documents/Photos/cat.bin", CAT)
    K.write_sd_keyfile(keydir, f"127.0.0.1:{port}", DEV, KEY)
    srv = LinkServer(keys_loader=lambda: {DEV: KEY}, oc_factory=lambda: oc,
                     limits=Limits(handshake=60, idle=600, partial=30), cal_db_factory=lambda: None)
    s = await srv.start("127.0.0.1", port)
    print("hub up", flush=True)
    out.mkdir(parents=True, exist_ok=True)
    while not (out / "STOP").exists():
        await asyncio.sleep(0.3)
    for d in oc.dirs:
        if d.startswith("Documents"):
            (out / d).mkdir(parents=True, exist_ok=True)
    for p, (data, _e, _t) in oc.files.items():
        (out / p).parent.mkdir(parents=True, exist_ok=True)
        (out / p).write_bytes(data)
    s.close()


asyncio.run(main())
