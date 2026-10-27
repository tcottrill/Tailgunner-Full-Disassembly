"""Compare RAM snapshots printed by tgtrace's 'ram' command.

usage: python ramdiff.py <tgtrace stdout> NAME1 NAME2 [NAME3 ...]
Prints every RAM word that differs between consecutive named snapshots.
"""
import sys


def load(path):
    snaps, cur, name = {}, None, None
    for line in open(path):
        if line.startswith("RAM "):
            name = line.split()[1]
            cur = snaps[name] = []
        elif cur is not None and len(cur) < 256:
            cur += [int(x, 16) for x in line.split()]
    return snaps


def main():
    snaps = load(sys.argv[1])
    names = sys.argv[2:] or list(snaps)
    for a, b in zip(names, names[1:]):
        x, y = snaps[a], snaps[b]
        d = ["%02X:%03X>%03X" % (r, x[r], y[r]) for r in range(256) if x[r] != y[r]]
        print("%s -> %s (%d): %s" % (a, b, len(d), " ".join(d)))


if __name__ == "__main__":
    main()
