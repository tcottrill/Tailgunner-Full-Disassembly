"""Read back tailgunner_program_rom.asm (+ tailgunner_defines.asm) and prove it
reproduces the 8K program ROM byte for byte.

Independent of emit.py: it parses only the two text files. Every Lxxxx line is
re-encoded at the address its label states (operands are evaluated from the
.alias equates and the labels in the files) and compared with the ROM image;
the Lxxxx lines must cover $0000-$1FFF exactly once.

It also checks the RAM pages the listing claims: where an operand names a full
RAM address, the page must match the last SETP on the straight-line path to it
(the path restarts at every label something jumps to).

Exit status 1 on any mismatch.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import romset, ccpu

LISTING = os.path.join(HERE, "tailgunner_program_rom.asm")
DEFINES = os.path.join(HERE, "tailgunner_defines.asm")

LINE = re.compile(r"^L([0-9A-F]{4}):\s+(\S+)\s*(.*)$")
LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(;.*)?$")
ALIAS = re.compile(r"^\.alias\s+([A-Za-z_][A-Za-z0-9_]*)\s+\$([0-9A-Fa-f]+)\s*(;.*)?$")


def strip_comment(s):
    return s.split(";", 1)[0].strip()


def value(tok, syms):
    tok = tok.strip()
    if tok.startswith("$"):
        return int(tok[1:], 16)
    if tok.isdigit():
        return int(tok)
    if tok in syms:
        return syms[tok]
    raise KeyError(tok)


def main():
    rom = romset.load_image()
    syms = {}
    for path in (DEFINES, LISTING):
        for s in open(path):
            m = ALIAS.match(s.strip())
            if m:
                syms[m.group(1)] = int(m.group(2), 16)
    lines = open(LISTING).read().split("\n")
    pending = []
    parsed = []
    for n, s in enumerate(lines, 1):
        m = LABEL.match(s)
        if m:
            pending.append(m.group(1))
            continue
        m = LINE.match(s)
        if not m:
            continue
        addr = int(m.group(1), 16)
        syms["L%04X" % addr] = addr
        for p in pending:
            if p in syms and syms[p] != addr:
                print("!! line %d: label %s defined twice" % (n, p))
            syms[p] = addr
        parsed.append((n, addr, m.group(2), strip_comment(m.group(3)), bool(pending)))
        pending = []

    errors = 0
    covered = bytearray(0x2000)
    jump_targets = set()
    encoded = []
    for n, addr, mnem, ops, named in parsed:
        try:
            if mnem == ".byte":
                data = bytes(value(t, syms) for t in ops.split(","))
                operand_page = None
            else:
                if mnem not in ccpu.OPS:
                    raise ValueError("unknown mnemonic " + mnem)
                kind = ccpu.OPS[mnem][0]
                o = ops
                if o.startswith("B,"):
                    o = o[2:]
                elif o == "B":
                    o = ""
                operand_page = None
                v = None
                if o.startswith("#"):
                    o = o[1:]
                if o.startswith("P:"):
                    v = value(o[2:], syms)
                elif o:
                    v = value(o, syms)
                    if kind == ccpu.RAM:
                        operand_page = v >> 4
                    if kind == ccpu.TARGET:
                        jump_targets.add(v)
                if kind == ccpu.SKIP and v is None:
                    v = 0x5F
                data = ccpu.encode(mnem, v)
        except (KeyError, ValueError) as e:
            print("!! line %d L%04X: %s" % (n, addr, e))
            errors += 1
            continue
        for k, b in enumerate(data):
            a = addr + k
            if a >= 0x2000 or covered[a]:
                print("!! line %d: $%04X covered twice or outside the ROM" % (n, a))
                errors += 1
                continue
            covered[a] = 1
            if rom[a] != b:
                print("!! line %d L%04X: listing gives $%02X, ROM has $%02X" % (n, addr, b, rom[a]))
                errors += 1
        encoded.append((addr, mnem, operand_page, len(data)))

    gaps = [a for a in range(0x2000) if not covered[a]]
    if gaps:
        print("!! %d ROM bytes not covered, first at $%04X" % (len(gaps), gaps[0]))
        errors += len(gaps)

    # RAM page check along straight-line code
    page_errors = 0
    page = None
    prev_end = None
    for addr, mnem, operand_page, ln in encoded:
        if addr in jump_targets or addr != prev_end or mnem == ".byte":
            page = None
        if mnem == "SETP":
            page = rom[addr] & 0x0F
        elif operand_page is not None and page is not None and operand_page != page:
            print("!! L%04X %s: operand is in page $%X but P = $%X" % (addr, mnem, operand_page, page))
            page_errors += 1
        prev_end = addr + ln
    print("lines checked : %d" % len(encoded))
    print("ROM bytes     : %d / 8192 covered" % (8192 - len(gaps)))
    print("MISMATCHES    : %d" % errors)
    print("PAGE ERRORS   : %d" % page_errors)
    return 1 if errors or page_errors else 0


if __name__ == "__main__":
    sys.exit(main())
