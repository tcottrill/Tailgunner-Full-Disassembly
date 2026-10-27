"""Report RAM words: name, writes / changes / distinct values (all traces),
value range and the instructions that read and write them.

usage: python trace/ramreport.py [--unnamed] [ADDR ...]
"""
import glob, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import romset, names


def load():
    vals, rd, wr = {}, {}, {}
    for fn in glob.glob(os.path.join(romset.BUILD, "trace_*.json")):
        t = json.load(open(fn))
        for k, (w, c, v) in t.get("ram_vals", {}).items():
            e = vals.setdefault(int(k), [0, 0, set()])
            e[0] += w; e[1] += c; e[2] |= set(v)
        for k, v in t["ram_r"].items():
            rd.setdefault(int(k), set()).update(v)
        for k, v in t["ram_w"].items():
            wr.setdefault(int(k), set()).update(v)
    return vals, rd, wr


def fmt(v):
    return "$%03X" % v


def main():
    vals, rd, wr = load()
    want = [int(a, 16) for a in sys.argv[1:] if not a.startswith("--")]
    addrs = want or [a for a in range(256) if not ("--unnamed" in sys.argv and a in names.RAM)]
    for a in addrs:
        if a not in vals and a not in rd:
            continue
        nm = names.RAM.get(a, ("RAM_%02X" % a, ""))[0]
        w, c, v = vals.get(a, [0, 0, set()])
        vs = sorted(v)
        shown = " ".join(fmt(x) for x in vs[:12]) + (" ..." if len(vs) > 12 else "")
        print("%02X %-12s writes %7d changes %7d values %4d  %s" % (a, nm, w, c, len(vs), shown))
        print("     r: %s" % " ".join("%04X" % x for x in sorted(rd.get(a, ()))[:16]))
        print("     w: %s" % " ".join("%04X" % x for x in sorted(wr.get(a, ()))[:16]))


if __name__ == "__main__":
    main()
