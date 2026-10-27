"""Print every line of the listing that carries a hand-written note from
comments.py (or names.NOTES) in an address range, to check each note sits on
the instruction it describes.

usage: python trace/notecheck.py LO HI
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import names

lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16)
listing = open(os.path.join(os.path.dirname(HERE), "tailgunner_program_rom.asm")).read().split("\n")
lines = {int(m.group(1), 16): s for s in listing for m in [re.match(r"^L([0-9A-F]{4}):", s)] if m}
for a in sorted(names.NOTES):
    if lo <= a <= hi:
        print(lines.get(a, "!! $%04X is not a line start: %s" % (a, names.NOTES[a])))
