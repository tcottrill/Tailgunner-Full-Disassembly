"""Separate code from data in the Tailgunner ROM and work out, for every
instruction, the P register (RAM page) and accumulator it runs with.

Two sources, in this order of trust:
  1. the traces of the running ROM (build/trace_*.json, written by
     trace/tgtrace.exe): bytes executed as opcodes, P and A/B at each one,
     jumps taken, LKP table reads, RAM reads/writes, OUT/INP ports;
  2. a static walk from everything the traces executed, following
     LPAI targets into the jumps that use them, conditional fall-through,
     and the return addresses that the CCPU call idiom stores in RAM
     (LDAI hi / A8I lo / STA ret / LPAI sub / JMP-or-T4K).

Writes build/analysis.json, which emit.py, emit_defines.py and the docs read.
"""
import glob, json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import romset, ccpu

OUT = os.path.join(romset.BUILD, "analysis.json")


def load_traces():
    tr = {"exec": {}, "operand": set(), "skipped": set(), "frames": 0, "files": []}
    for key in ("jumps", "falls", "jvals", "lkp", "ram_r", "ram_w", "out", "inp"):
        tr[key] = {}
    files = sorted(glob.glob(os.path.join(romset.BUILD, "trace_*.json")))
    if not files:
        raise SystemExit("!! no build/trace_*.json -- run trace/run_traces.py first")
    for fn in files:
        t = json.load(open(fn))
        tr["files"].append(os.path.basename(fn))
        tr["frames"] += t["frames"]
        for a, pm, am, c in t["exec"]:
            e = tr["exec"].setdefault(a, [0, 0, 0])
            e[0] |= pm; e[1] |= am; e[2] += c
        tr["operand"] |= set(t["operand"])
        tr["skipped"] |= set(t["skipped"])
        for key in ("jumps", "falls", "jvals", "lkp", "ram_r", "ram_w", "out", "inp"):
            for k, v in t[key].items():
                tr[key].setdefault(int(k), set()).update(v)
        if t["anomalies"]:
            print("!! %s: PC outside the ROM at %s" % (fn, t["anomalies"]))
    return tr


def bank(a):
    return a & 0x1000


def t4k_bank(p):
    """Bank a T4K selects in an 8K machine (ccpu.cpp: ((P&3)-1)<<12)."""
    return (((p & 3) - 1) << 12) & 0x1000


def analyze(img):
    tr = load_traces()
    executed = tr["exec"]
    insn = {}       # addr -> dict(len, src)
    owner = {}      # byte addr -> insn addr
    calls = {}      # call site (jump addr) -> {"ret": addr, "via": ram addr}
    xfer = {}       # jump addr -> set of static targets
    conflicts = []

    def claim(a, src):
        op = img[a]
        n = ccpu.length(op)
        for k in range(n):
            b = a + k
            if b >= 0x2000:
                return False
            if b in owner and owner[b] != a:
                return False
        if a in insn:
            return False
        insn[a] = {"len": n, "src": src}
        for k in range(n):
            owner[a + k] = a
        return True

    # trace-executed instructions first: these are certain
    for a in sorted(executed):
        if not claim(a, "trace"):
            conflicts.append(a)

    # static walk
    work = list(sorted(executed))
    seen = set()
    # bytes some LKP read as a table. A site that also read executed code
    # (the star field's random numbers, read across the whole ROM; the
    # formation lookups, which at power-on index with a pointer not yet set)
    # says nothing about what a byte is.
    lkp_bytes = set()
    traced = set()
    for a in executed:
        traced |= set(range(a, a + ccpu.length(img[a])))
    for site, addrs in tr["lkp"].items():
        if not set(addrs) & traced:
            lkp_bytes |= set(addrs)

    def push(a, src):
        if a in seen:
            return
        if a not in insn:
            if a in lkp_bytes or a >= 0x2000:
                conflicts.append(a)
                return
            if not claim(a, src):
                conflicts.append(a)
                return
        work.append(a)

    while work:
        a = work.pop()
        if a in seen:
            continue
        seen.add(a)
        # straight-line walk from a, tracking J, P and an acc constant
        j = None
        p = None
        const = None
        stored = stored_at = None
        pc = a
        while True:
            if pc not in insn:
                if pc in lkp_bytes or not claim(pc, "static"):
                    break
            seen.add(pc)
            op = img[pc]
            m, kind, v, n = ccpu.decode(img, pc)
            nxt = pc + n
            hi = op >> 4
            if m == "LPAI":
                j = v
            elif m == "LPAP":
                j = None
            if m == "SETP":
                p = v
            if m == "LDAI":
                const = v
            elif m in ("A4I", "A8I") and const is not None:
                const = (const + v) & 0xFFF
            elif m in ("S4I", "S8I") and const is not None:
                const = (const - v) & 0xFFF
            elif m == "STA" and const is not None:
                stored = const
                stored_at = ((p if p is not None else -1) << 4 | v) if p is not None else None
                const = None
            elif hi in (0x0, 0x1, 0x6, 0x7, 0xA) or op in (0xE7, 0xE8, 0xE9, 0xEA, 0xF7, 0xF8, 0xF9, 0xFA, 0xE2, 0xF2) \
                    or 0xEB <= op <= 0xEF or 0xFB <= op <= 0xFF or op in (0xE0, 0xE3, 0xF3, 0xE4, 0xF4):
                const = None
            if op in ccpu.COND or op in ccpu.UNCOND:
                targets = set(tr["jumps"].get(pc, ()))
                if j is not None:
                    if op == 0x50:
                        ps = [p] if p is not None else [q for q in range(16) if executed.get(pc, [0])[0] >> q & 1]
                        for q in ps:
                            targets.add(t4k_bank(q) + j)
                    else:
                        targets.add(bank(pc) + j)
                xfer.setdefault(pc, set()).update(targets)
                for t in targets:
                    push(t, "static")
                if op in ccpu.UNCOND:
                    if stored is not None:
                        ret = bank(pc) + stored
                        calls[pc] = {"ret": ret, "via": stored_at, "to": sorted(targets)}
                        if pc < ret <= pc + 16:
                            push(ret, "static")
                    break
                stored = None if op not in ccpu.UNCOND else stored
            pc = nxt
            if pc >= 0x2000 or (pc in insn and pc in seen):
                break

    # bytes that are neither code nor (yet) known data
    code_bytes = set(owner)
    data_bytes = set(range(0x2000)) - code_bytes

    # LKP tables: group the addresses each site read into runs
    tables = {}
    for site, addrs in tr["lkp"].items():
        for t in addrs:
            tables.setdefault(t, set()).add(site)

    # P and accumulator per instruction
    pinfo = {}
    for a in insn:
        if a in executed:
            pm, am = executed[a][0], executed[a][1]
            pinfo[a] = {"p": [q for q in range(16) if pm >> q & 1], "acc": am, "exec": executed[a][2]}
    # static propagation of P along straight-line code for unexecuted instructions
    for a in sorted(insn):
        if a in pinfo:
            continue
        # look back along fall-through for a SETP or an executed instruction
        b, ps, acc = a, None, 1
        prev = [x for x in range(max(0, a - 2), a) if x in insn and x + insn[x]["len"] == a]
        if prev and 0x50 <= img[prev[0]] <= 0x57:
            acc = 2
        while True:
            prev = [x for x in range(max(0, b - 2), b) if x in insn and x + insn[x]["len"] == b]
            if not prev:
                break
            b = prev[0]
            if img[b] >> 4 == 0x8:
                ps = [img[b] & 15]
                break
            if b in pinfo:
                ps = pinfo[b]["p"]
                break
            if img[b] in ccpu.UNCOND:
                break
        pinfo[a] = {"p": ps or [], "acc": acc, "exec": 0}
    # the acc of an instruction reached by a B-select jump is B
    for site, targets in xfer.items():
        if 0x50 <= img[site] <= 0x57:
            for t in targets:
                if t in pinfo and not pinfo[t]["exec"]:
                    prev = [x for x in range(max(0, t - 2), t) if x in insn and x + insn[x]["len"] == t]
                    falls_in = prev and img[prev[0]] not in ccpu.UNCOND and not 0x50 <= img[prev[0]] <= 0x57
                    pinfo[t]["acc"] = 3 if falls_in else 2

    result = {
        "frames": tr["frames"],
        "trace_files": tr["files"],
        "insn": {a: dict(insn[a], **pinfo[a]) for a in sorted(insn)},
        "xfer": {a: sorted(v) for a, v in sorted(xfer.items())},
        "calls": calls,
        "jumps_taken": {a: sorted(v) for a, v in sorted(tr["jumps"].items())},
        "jvals": {a: sorted(v) for a, v in sorted(tr["jvals"].items())},
        "lkp": {a: sorted(v) for a, v in sorted(tr["lkp"].items())},
        "lkp_targets": {t: sorted(s) for t, s in sorted(tables.items())},
        "ram_r": {a: sorted(v) for a, v in sorted(tr["ram_r"].items())},
        "ram_w": {a: sorted(v) for a, v in sorted(tr["ram_w"].items())},
        "out": {a: sorted(v) for a, v in sorted(tr["out"].items())},
        "inp": {a: sorted(v) for a, v in sorted(tr["inp"].items())},
        "skipped": sorted(tr["skipped"]),
        "conflicts": sorted(set(conflicts)),
        "data_bytes": len(data_bytes),
    }
    return result


def main():
    img = romset.load_image()
    r = analyze(img)
    with open(OUT, "w") as f:
        json.dump(r, f, indent=0)
    ins = r["insn"]
    ntrace = sum(1 for v in ins.values() if v["src"] == "trace")
    nstat = len(ins) - ntrace
    code = sum(v["len"] for v in ins.values())
    print("instructions: %d from the traces, %d found statically; %d code bytes, %d data bytes"
          % (ntrace, nstat, code, r["data_bytes"]))
    print("calls with a stored return address: %d; LKP sites %d reading %d table bytes"
          % (len(r["calls"]), len(r["lkp"]), len(r["lkp_targets"])))
    if r["conflicts"]:
        print("static walk stopped at %d addresses: %s" % (len(r["conflicts"]),
              " ".join("%04X" % a for a in r["conflicts"][:40])))


if __name__ == "__main__":
    main()
