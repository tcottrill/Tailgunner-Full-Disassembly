"""Tailgunner ROM set: find the four chips and build the 8K program image.

The CCPU fetches 8-bit opcodes from a 16-bit-wide pair of 2K x 8 EPROMs:
the 't' chip holds the even bytes and the 'p' chip the odd bytes
(MAME ROM_LOAD16_BYTE). Bank 0 ($0000-$0FFF) is t70/p70, bank 1
($1000-$1FFF) is t71/p71.

Chips are matched by CRC32, so loose files or a MAME zip both work.
"""
import os, sys, zipfile, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILD = os.path.join(HERE, "build")
IMAGE = os.path.join(BUILD, "tailg_8k.bin")

# (name, crc32, base, odd) -- base = first CPU address, odd = 1 for the odd-byte chip
CHIPS = [
    ("tgunner.t70", 0x21EC9A04, 0x0000, 0),
    ("tgunner.p70", 0x8D7410B3, 0x0000, 1),
    ("tgunner.t71", 0x2C954AB6, 0x1000, 0),
    ("tgunner.p71", 0x8E2C8494, 0x1000, 1),
]
CHIP_SIZE = 0x800
ROM_SIZE = 0x2000


def _candidates(path):
    """Yield (name, bytes) for every file in a directory or zip (recursively)."""
    if os.path.isdir(path):
        for dp, _, fns in os.walk(path):
            for fn in sorted(fns):
                full = os.path.join(dp, fn)
                if fn.lower().endswith(".zip"):
                    yield from _candidates(full)
                elif os.path.getsize(full) == CHIP_SIZE:
                    with open(full, "rb") as f:
                        yield fn, f.read()
    elif path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if info.file_size == CHIP_SIZE:
                    yield info.filename, z.read(info)
    elif os.path.isfile(path):
        with open(path, "rb") as f:
            yield os.path.basename(path), f.read()


def find_chips(path):
    want = {crc: (name, base, odd) for name, crc, base, odd in CHIPS}
    found = {}
    for fn, data in _candidates(path):
        crc = zlib.crc32(data) & 0xFFFFFFFF
        if crc in want and crc not in found:
            found[crc] = data
    missing = [want[c][0] for c in want if c not in found]
    if missing:
        raise SystemExit("!! missing ROM chips (by CRC32): " + ", ".join(missing))
    return found


def build_image(path=None):
    path = path or os.path.join(ROOT, "roms")
    found = find_chips(path)
    img = bytearray(ROM_SIZE)
    for name, crc, base, odd in CHIPS:
        data = found[crc]
        for i, b in enumerate(data):
            img[base + 2 * i + odd] = b
    os.makedirs(BUILD, exist_ok=True)
    with open(IMAGE, "wb") as f:
        f.write(img)
    return bytes(img)


def load_image():
    if not os.path.exists(IMAGE):
        return build_image()
    with open(IMAGE, "rb") as f:
        return f.read()


if __name__ == "__main__":
    img = build_image(sys.argv[1] if len(sys.argv) > 1 else None)
    print("wrote %s (%d bytes, crc32 %08X)" % (IMAGE, len(img), zlib.crc32(img) & 0xFFFFFFFF))
