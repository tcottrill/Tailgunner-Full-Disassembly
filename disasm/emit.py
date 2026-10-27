"""Write tailgunner_program_rom.asm, the listing of the 8K program ROM.

Inputs: build/tailg_8k.bin (romset.py), build/analysis.json (analyze.py),
names.py (names and descriptions written for this disassembly).

Every line of code or data starts with its address label Lxxxx:, as in the
Tempest and Space Duel listings; verify.py re-encodes each line and
compares it with the ROM.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import romset, ccpu, names, hwinfo, tables

LISTING = os.path.join(HERE, "tailgunner_program_rom.asm")
REFS = os.path.join(romset.BUILD, "program_refs.json")
COMMENT_COL = 36


def wrap(first, text, width=79):
    """Comment lines: 'first' then text, continued under it with ';   '."""
    out, line = [], first
    for word in text.split():
        if len(line) + len(word) + 1 > width and line.strip(" ;-") and line != first:
            out.append(line.rstrip())
            line = ";   "
        line += ("" if line.endswith((" ", "- ")) else " ") + word
    out.append(line.rstrip())
    return out


def bank(a):
    return a & 0x1000


def t4k_bank(p):
    return (((p & 3) - 1) << 12) & 0x1000


class Listing:
    def __init__(self):
        self.img = romset.load_image()
        an = json.load(open(os.path.join(romset.BUILD, "analysis.json")))
        self.an = an
        self.ins = {int(a): v for a, v in an["insn"].items()}
        ik = lambda d: {int(k): v for k, v in d.items()}
        self.jumps_taken = ik(an["jumps_taken"])
        self.jvals = ik(an["jvals"])
        self.lkp = ik(an["lkp"])
        self.calls = ik(an["calls"])
        self.out = ik(an["out"])
        self.inp = ik(an["inp"])
        self.xfer = ik(an["xfer"])
        img = self.img
        # a repeated FRM is fetched but skipped by the CPU: list it as an instruction
        self.dup_frm = set()
        for a in an["skipped"]:
            if img[a] in ccpu.FRAME and img[a - 1] == img[a] and a - 1 in self.ins:
                if a not in self.ins:
                    self.ins[a] = {"len": 1, "src": "skip", "p": [], "acc": 1, "exec": 0}
                self.dup_frm.add(a)
        self.owner = {}
        for a, v in self.ins.items():
            for k in range(v["len"]):
                self.owner[a + k] = a
        self.resolve_lpai()
        self.find_routines()
        self.data_tables()
        # decoded table records (tables.py); only where every byte is data
        self.segs = {}
        for a, (n, c, lab) in tables.segments(img).items():
            if all(x not in self.owner for x in range(a, a + n)):
                self.segs[a] = (n, c, lab)
            else:
                print("!! table record at $%04X overlaps code; printed as plain bytes" % a)
        self.simulate()
        self.call_params()

    # ------------------------------------------------------------ analysis
    def jumps_using(self, a):
        """The jumps that use the J an LPAI at a loads: J survives conditional
        jumps (on fall-through) until the next LPAI / LPAP or an unconditional
        transfer."""
        sites = []
        pc = a + self.ins[a]["len"]
        for _ in range(200):
            if pc not in self.ins:
                break
            op = self.img[pc]
            if op in ccpu.COND or op in ccpu.UNCOND:
                sites.append(pc)
                if op in ccpu.UNCOND:
                    break
            elif op >> 4 == 4 or op == 0xE1:
                break
            pc += self.ins[pc]["len"]
        return sites

    def resolve_lpai(self):
        self.lpai = {}        # lpai addr -> (targets, first jump site using it)
        self.site_lpai = {}   # jump site -> lpai addr
        for a, v in self.ins.items():
            if self.img[a] >> 4 != 4:
                continue
            j = ccpu.lpai_target(self.img[a], self.img[a + 1])
            sites = self.jumps_using(a)
            targets = set()
            for site in sites:
                self.site_lpai.setdefault(site, a)
                if self.img[site] == 0x50:
                    ps = self.ins[site]["p"]
                    t = {t4k_bank(p) + j for p in ps}
                    if not t:
                        t = {d for d in self.jumps_taken.get(site, []) if d & 0xFFF == j}
                    targets |= t
                else:
                    targets.add(bank(site) + j)
            if not sites:
                targets.add(bank(a) + j)
            t4k = next((s for s in sites if self.img[s] == 0x50), None)
            self.lpai[a] = (sorted(targets), t4k if t4k is not None else (sites[0] if sites else None))

    def find_routines(self):
        img = self.img
        self.entry = {0x0000: []}       # routine entry -> call sites
        self.ret_points = {}            # return address -> call site
        for site, c in self.calls.items():
            if site < c["ret"] <= site + 16:
                self.ret_points[c["ret"]] = site
                for t in c["to"]:
                    self.entry.setdefault(t, []).append(site)
        # indirect jumps: J came from RAM (LPAP), not from an LPAI
        self.indirect = {}
        for site in self.jvals:
            if site in self.site_lpai:
                continue
            dests = set(self.jumps_taken.get(site, []))
            self.indirect[site] = sorted(dests)
        self.dispatch = {}
        for site, dests in self.indirect.items():
            for d in dests:
                if d not in self.ret_points:
                    self.dispatch.setdefault(d, []).append(site)
        for d, sites in self.dispatch.items():
            self.entry.setdefault(d, [])
        # T4K destinations cross into the other bank: entries too
        for a, (targets, site) in self.lpai.items():
            if site is not None and img[site] == 0x50:
                for t in targets:
                    if t not in self.ret_points:
                        self.entry.setdefault(t, [])
        for a in names.LABELS:
            if a in self.ins and names.LABELS[a][1]:
                self.entry.setdefault(a, [])

    def data_tables(self):
        """Who reads which data byte, and where tables start."""
        self.readers = {}
        for site, addrs in self.lkp.items():
            if len(addrs) >= 1024:
                continue         # the star field's random numbers: read all over the ROM
            for t in addrs:
                self.readers.setdefault(t, set()).add(site)
        # a data region (a run of bytes that are not code) gets one label at
        # its start when some LKP reads it
        self.table_starts = set()
        a = 0
        while a < 0x2000:
            if a in self.owner:
                a += 1
                continue
            b = a
            while b < 0x2000 and b not in self.owner and not (b == 0x1000 and b != a):
                b += 1
            if any(x in self.readers for x in range(a, b)):
                self.table_starts.add(a)
            a = b

    # ------------------------------------------------------------ naming
    def name(self, a):
        if a in names.LABELS:
            return names.LABELS[a][0]
        return "L%04X" % a

    def ram_name(self, r):
        if r in names.RAM:
            return names.RAM[r][0]
        return "RAM_%02X" % r

    def needed_labels(self):
        need = set(self.entry) | set(self.ret_points) | set(names.LABELS) | self.table_starts
        for a, (targets, site) in self.lpai.items():
            need |= set(targets)
        for site, dests in self.jumps_taken.items():
            need |= set(dests)
        return {a for a in need if 0 <= a < 0x2000}

    # ------------------------------------------------------------ simulation
    def simulate(self):
        """Explain each line mechanically from what the straight-line code
        before it did: the condition of every conditional jump, the RAM word
        an indirect (I register) operation touches, and the target of every
        return address stored. State (A, B, I and the compare flags, as
        ccpu.cpp sets them) restarts at every place something jumps to.

        Flags after an accumulator op: cmpacc = the accumulator before it,
        cmpval = the operand; JEQ jumps if cmpval = cmpacc, JLT if cmpval <
        cmpacc, JCZ if the 13-bit result had no carry (for a subtract or TST:
        cmpacc < cmpval), JOS if bit 0 of A was set before the op.
        """
        img = self.img
        self.auto = {}
        dests = set(self.entry) | set(self.ret_points)
        for targets, site in self.lpai.values():
            dests |= set(targets)
        for d in self.jumps_taken.values():
            dests |= set(d)
        vias = {}
        for site, c in self.calls.items():
            if c["via"] is not None and site < c["ret"] <= site + 16:
                vias[(c["via"], c["ret"] & 0xFFF)] = c["ret"]
        ret_words = {c["via"] for c in self.calls.values() if c["via"] is not None}

        def show(x, accname):
            if x is None:
                return accname
            if isinstance(x, int):
                return "%d" % x if x < 10 else "$%X" % x
            return x

        def add(x, n):
            if isinstance(x, int):
                return (x + n) & 0xFFF
            if isinstance(x, str) and len(x) < 20:
                return "%s%s%s" % (x, "+" if n >= 0 else "-", show(abs(n), ""))
            return None

        def expr(x, opc, y):
            """x op y as text, when both are known and the text stays short."""
            if x is None or y is None:
                return None
            s = "%s %s %s" % (show(x, ""), opc, show(y, ""))
            return s if len(s) <= 28 else None

        st = None
        prev_end = None
        fall_in = {}
        for a in sorted(self.ins):
            v = self.ins[a]
            if st is not None and a == prev_end:
                fall_in[a] = dict(st)          # the state falling into a, kept for delay loops
            if st is None or a in dests or a != prev_end:
                st = {"A": None, "B": None, "I": None, "flags": None}
            prev_end = a + v["len"]
            note = self.auto.setdefault(a, [])
            op = img[a]
            m, kind, val, n = ccpu.decode(img, a)
            accsel = {1: "A", 2: "B"}.get(v["acc"])
            ps = v["p"]
            ram = (ps[0] << 4 | val) if kind == ccpu.RAM and len(ps) == 1 else None
            rname = self.ram_name(ram) if ram is not None else None
            iname = st["I"] if isinstance(st["I"], str) else (self.ram_name(st["I"]) if st["I"] is not None else None)
            if m == "OUT" and accsel == "A" and isinstance(st["A"], int) and val in (5, 6, 7):
                bit = st["A"] & 1        # the latch gets the inverse of bit 0
                note.append({6: "dim" if bit == 0 else "bright",
                             7: "the stick's x axis" if bit == 0 else "the stick's y axis",
                             5: "latch input high" if bit == 0 else "latch input low (a later high clears the coin)"}[val])
            if accsel is None and m not in ccpu.JUMPS and m not in ("SETP", "LPAI", "IV", "OUT", "FRM", "FRMF"):
                st = None
                continue
            acc = st[accsel] if accsel else None

            def flags(kindf, operand):
                st["flags"] = (kindf, acc, operand, accsel)

            if m == "LDAI":
                flags("load", val); st[accsel] = val
            elif m == "INP":
                flags("load", "the input")
                st[accsel] = (hwinfo.SWITCHES[val & 7][0] if accsel == "B" else hwinfo.INPUTS.get(val, ("input %d" % val,))[0])
            elif m in ("A4I", "A8I"):
                flags("add", val); st[accsel] = add(acc, val)
            elif m in ("S4I", "S8I"):
                flags("sub", val); st[accsel] = add(acc, -val)
            elif kind == ccpu.RAM:
                st["I"] = ram
                operand = rname
                if m == "LDA":
                    flags("load", operand); st[accsel] = operand
                elif m == "TST":
                    flags("sub", operand)
                elif m == "ADD":
                    flags("add", operand); st[accsel] = expr(acc, "+", operand)
                elif m == "SUB":
                    flags("sub", operand); st[accsel] = expr(acc, "-", operand)
                elif m == "WS":
                    st["I"] = "[%s]" % rname if rname else None
                    note.append("I = the address in %s" % rname if rname else "I = the address in that word")
                elif m == "STA":
                    if isinstance(acc, int) and ram is not None:
                        r = vias.get((ram, acc))
                        if r is not None:
                            note.append("return address: %s" % self.name(r))
                        elif ram in ret_words:
                            pass
                    st[accsel] = acc
            elif m in ("LDAP", "LDAPF", "ADDP", "SUBP", "SUBPF", "ANDP", "ANDPF", "STAP", "STAPF", "CST", "LPAP"):
                if iname:
                    word = {"STAP": "store to", "STAPF": "store to", "LPAP": "J = "}.get(m, "")
                    note.append(("%s %s" % (word, iname)).strip() if m != "LPAP" else "J = the address in %s" % iname)
                if m in ("LDAP", "LDAPF"):
                    flags("load", iname); st[accsel] = iname
                elif m in ("ADDP", "CST"):
                    flags("add", iname); st[accsel] = expr(acc, "+", iname)
                elif m in ("SUBP", "SUBPF"):
                    flags("sub", iname); st[accsel] = expr(acc, "-", iname)
                elif m in ("ANDP", "ANDPF"):
                    flags("and", iname); st[accsel] = expr(iname, "&", acc)
            elif m in ("LKP", "LKPF"):
                flags("load", "the table byte"); st[accsel] = None
            elif m in ("SHR", "SHRF", "SHL", "SHLF", "ASR", "ASRF", "SHRB", "SHRBF", "SHLB", "SHLBF"):
                st["flags"] = ("shift", None, None, accsel)
                st[accsel] = None
                if m.startswith(("SHRB", "SHLB")):
                    st["A"] = st["B"] = None
            elif m in ("MUL", "MULF", "NV", "NVF", "DV", "WSP"):
                st["flags"] = None
                st["A"] = st["B"] = None
                if m == "WSP":
                    st["I"] = None
            elif op in ccpu.COND:
                f = st["flags"]
                cond = None
                if f:
                    k, old, operand, fa = f
                    o, p = show(old, fa or "acc"), show(operand, "?")
                    base = m[:-1] if m.endswith("B") and m not in ("JOS",) and len(m) == 4 else m
                    if base == "JEQ" and k != "shift":
                        cond = ("if %s = 0" % p if old == 0 else "if %s = 0" % o if operand == 0
                                else "if %s = %s" % (o, p))
                    elif base == "JLT" and k != "shift":
                        cond = "if %s < %s" % (p, o)
                    elif base == "JCZ":
                        if k == "sub":
                            cond = "if %s > 0" % p if old == 0 else "if %s < %s" % (o, p)
                        elif k == "add" and operand == 1 and isinstance(old, int) and old >= 0x800:
                            cond = "count up to 0 (a delay of $%X loops)" % (0x1000 - old)
                        elif k == "add" and operand == 1:
                            s = self.site_lpai.get(a)
                            tg = self.lpai[s][0] if s is not None else []
                            loop = len(tg) == 1 and a - 4 <= tg[0] < a and img[tg[0]] == 0x21
                            start = fall_in.get(tg[0], {}).get(fa) if loop else None
                            if isinstance(start, int) and start >= 0x800:
                                cond = "count up to 0 (a delay of $%X loops)" % (0x1000 - start)
                            else:
                                cond = "until %s + 1 carries (reaches $1000)" % o
                        elif k == "add":
                            cond = "if %s + %s < $1000 (no carry)" % (o, p)
                        elif k in ("load", "and"):
                            cond = "always (this op cannot carry)"
                    elif base == "JOS":
                        cond = ("if the bit shifted out of A was 1" if k == "shift" and fa == "A"
                                else "if bit 0 of A was 1")
                if cond is None and m.startswith("JOS"):
                    cond = "if bit 0 of A was 1"
                if m.startswith("JVN"):
                    cond = "while the vector generator is busy"
                if cond and (" = 1" in cond) and any(cond.startswith("if %s = 1" % nm) for nm, _ in hwinfo.INPUTS.values()):
                    cond += " (not pressed)"
                if cond:
                    tgt = None
                    s = self.site_lpai.get(a)
                    if s is not None:
                        t = self.lpai[s][0]
                        tgt = self.name(t[0]) if len(t) == 1 else None
                    note.append(cond + (" -> %s" % tgt if tgt else ""))

    def call_params(self):
        """At each call, note the stores to the called routine's parameters."""
        img = self.img
        dests = set(self.entry) | set(self.ret_points)
        for targets, site in self.lpai.values():
            dests |= set(targets)
        prev_of = {a + v["len"]: a for a, v in self.ins.items()}
        for site, c in self.calls.items():
            for t in c["to"]:
                params = names.CALL_PARAMS.get(t)
                if not params:
                    continue
                seen, b = set(), site
                for _ in range(80):
                    if b in dests or b not in prev_of:
                        break
                    b = prev_of[b]
                    if img[b] in ccpu.UNCOND:
                        break
                    v = self.ins[b]
                    if img[b] >> 4 == 0xD and len(v["p"]) == 1:
                        r = v["p"][0] << 4 | (img[b] & 15)
                        if r in params and r not in seen:
                            seen.add(r)
                            self.auto.setdefault(b, []).insert(0, params[r])

    def ram_users(self):
        """RAM word -> the routines (by header) whose code touches it directly."""
        img = self.img
        users = {}
        current = None
        for a in sorted(self.ins):
            if a in self.entry:
                current = self.name(a)
            v = self.ins[a]
            if img[a] >> 4 in (6, 7, 0xA, 0xB, 0xC, 0xD) and len(v["p"]) == 1 and current:
                users.setdefault(v["p"][0] << 4 | (img[a] & 15), []).append(current)
        return {r: sorted(set(u), key=u.index) for r, u in users.items()}

    def sound_note(self, a):
        """Decode the sound command an OUT OUT_SND_DATA at a starts.

        The value v in A is shifted out: OUT 3 (data) = ~v bit 0, OUT 0-2
        (address) = ~v bits 1-3, then two strobes; the board sets sound bit
        'address' to 'data', and a sound plays while its bit is 0.
        """
        img = self.img
        prev = [x for x in (a - 1, a - 2) if x in self.ins and x + self.ins[x]["len"] == a]
        if not prev:
            return None
        p = prev[0]
        m, kind, v, n = ccpu.decode(img, p)
        if m not in ("A8I", "A4I"):
            return None
        pp = [x for x in (p - 1, p - 2) if x in self.ins and x + self.ins[x]["len"] == p]
        known = pp and img[pp[0]] == 0x00          # LDAI #$000 before it: v is the constant
        bit = (~v >> 1) & 7
        name = hwinfo.SOUND_BITS.get(bit, "bit %d" % bit)
        if known:
            return "sound: %s %s" % (name, "on" if v & 1 else "off")
        return "sound: %s on or off (bit 0 of A)" % name

    # ------------------------------------------------------------ rendering
    def render_insn(self, a):
        img = self.img
        v = self.ins[a]
        op = img[a]
        m, kind, val, n = ccpu.decode(img, a)
        accb = v["acc"] == 2
        both = v["acc"] == 3
        bpre = "B," if accb else ""
        notes = []
        if both:
            notes.append("runs with A and with B")
        operand = ""
        if a in self.dup_frm:
            notes.append("repeated FRM: fetched and skipped, no second wait")
        if kind == ccpu.IMM_HI:
            operand = bpre + "#$%03X" % val
        elif kind in (ccpu.IMM4, ccpu.IMM8):
            operand = bpre + "#$%X" % val if kind == ccpu.IMM4 else bpre + "#$%02X" % val
        elif kind == ccpu.PAGE:
            operand = "$%X" % val
        elif kind == ccpu.PORT:
            if m == "INP" and accb:
                operand = bpre + hwinfo.SWITCHES[val & 7][0] if val < 8 else bpre + "$%X" % val
            elif m == "INP" and not both and val in hwinfo.INPUTS:
                operand = hwinfo.INPUTS[val][0]
            elif m == "OUT" and val < 8:
                operand = bpre + hwinfo.OUTPUTS[val][0]
            else:
                operand = bpre + "$%X" % val
            if m == "INP":
                for acc in ([2] if accb else [1, 2] if both else [1]):
                    notes.append(hwinfo.inp_note(val, acc))
            elif val == 3:
                notes.append(self.sound_note(a) or hwinfo.out_note(val))
            elif val in (0, 1, 2, 4):
                pass        # the rest of a sound command: see its OUT_SND_DATA line
            elif not self.auto.get(a):
                notes.append(hwinfo.out_note(val))
        elif kind == ccpu.RAM:
            ps = v["p"]
            if len(ps) == 1:
                operand = bpre + self.ram_name(ps[0] << 4 | val)
            else:
                operand = bpre + "P:$%X" % val
                if ps:
                    notes.append("P=" + ",".join("$%X" % p for p in ps))
                else:
                    notes.append("P unknown")
        elif kind == ccpu.TARGET:
            targets, site = self.lpai[a]
            if len(targets) == 1:
                operand = self.name(targets[0])
                if site is not None and img[site] == 0x50:
                    notes.append("T4K to bank %d" % (targets[0] >> 12))
            else:
                operand = "#$%03X" % val
                notes.append("J for " + (", ".join(self.name(t) for t in targets) if targets else "an unknown bank"))
        elif kind == ccpu.SKIP:
            if val != 0x5F:
                operand = "$%02X" % val
            r = self.lkp.get(a)
            if r:
                if len(r) >= 1024:
                    notes.append("reads bytes all over the ROM (random numbers)")
                else:
                    notes.append("table read $%04X-$%04X" % (r[0], r[-1]))
        elif kind == ccpu.IMP:
            if accb and m not in ccpu.JUMPS:
                operand = "B"
        if op in ccpu.COND or op in ccpu.UNCOND:
            if a in self.indirect:
                d = self.indirect[a]
                if d:
                    notes.append("J from RAM -> " + ", ".join(self.name(t) for t in d[:8]) + (" ..." if len(d) > 8 else ""))
                else:
                    notes.append("J from RAM (never taken in the traces)")
            if op == 0x59 or op == 0x51:
                notes.append("taken if the stick is past the X register (MUX axis)")
        if a in self.calls and a in self.ret_points.values():
            c = self.calls[a]
            if c["via"] is not None:
                notes.append("call; returns to %s via %s" % (self.name(c["ret"]), self.ram_name(c["via"])))
            else:
                notes.append("call; returns to %s" % self.name(c["ret"]))
        notes = self.auto.get(a, []) + notes
        if a in names.NOTES:
            notes.insert(0, names.NOTES[a])
        return m, operand, notes

    def header(self, a):
        lines = []
        nm, desc = names.LABELS.get(a, (self.name(a), ""))
        lines.append(";" + "-" * 78)
        lines += wrap("; %s - " % nm, desc or "(not yet described)")
        sites = sorted(set(self.entry.get(a, [])))
        if sites:
            vias = sorted({self.calls[s]["via"] for s in sites if self.calls[s]["via"] is not None})
            lines += wrap(";   ", "Called from %s%s." % (", ".join(self.name(s) for s in sites),
                          (" (return address in %s)" % ", ".join(self.ram_name(r) for r in vias)) if vias else ""))
        if a in self.dispatch:
            lines += wrap(";   ", "Reached by the jump through RAM at %s." %
                          ", ".join(self.name(s) for s in sorted(set(self.dispatch[a]))))
        lines.append(";" + "-" * 78)
        return lines

    @staticmethod
    def line(label, text, notes):
        s = "%s:  %s" % (label, text)
        if notes:
            s = (s.ljust(COMMENT_COL) if len(s) < COMMENT_COL else s + "  ") + ";" + "  ".join(notes)
        return s.rstrip()

    def write(self):
        img = self.img
        need = self.needed_labels()
        out = []
        out += [
            ";Tailgunner (Cinematronics, 1979) - annotated disassembly of the program ROM $0000-$1FFF.",
            ";MAME set 'tailg': tgunner.t70/.p70 (bank 0, $0000-$0FFF) and tgunner.t71/.p71",
            ";(bank 1, $1000-$1FFF); the t chips hold the even bytes, the p chips the odd ones.",
            ";The CPU is the Cinematronics CCPU, a TTL processor with 12-bit registers",
            ";and 8-bit opcodes; see README.md for the instruction set and this syntax.",
            ";No source code is known to survive. Code and data were separated by running",
            ";the ROM (trace/tgtrace.exe, the AAE ccpu.cpp core) and following its jumps",
            ";(analyze.py); every name and description was written for this disassembly.",
            ";Every line below was re-encoded and byte-compared with the ROM (verify.py).",
            ";Syntax: .alias, .byte, .org; $ = hex; # = immediate; B, = the instruction",
            ";uses the B accumulator; P:$x = RAM word $x of the page the P register selects",
            ";(the page is known statically wherever a full address or name is shown).",
            "",
            ".org $0000",
            "",
            '.include "tailgunner_defines.asm"',
            "",
        ]
        a = 0
        in_static = False
        while a < 0x2000:
            if a in (0x0000, 0x1000):
                b = a >> 12
                out += ["", ";" + "=" * 78,
                        "; BANK %d   $%04X-$%04X   tgunner.t7%d (even bytes) + tgunner.p7%d (odd bytes)" % (b, a, a + 0xFFF, b, b),
                        ";" + "=" * 78, ""]
            if a in names.BLOCKS:
                out += [";" + s if s else ";" for s in names.BLOCKS[a]]
            if a in self.ins:
                v = self.ins[a]
                if a in self.entry:
                    out.append("")
                    out += self.header(a)
                if a in names.LABELS:
                    out.append(self.name(a) + ":")
                static = v["src"] == "static" and a not in self.dup_frm
                if static and not in_static:
                    out.append(";[static] not executed in the traces; reached by following the jumps")
                in_static = static
                m, operand, notes = self.render_insn(a)
                text = ("%-5s%s" % (m, operand)).rstrip() if operand else m
                out.append(self.line("L%04X" % a, text, notes))
                for k in range(1, v["len"]):
                    if a + k in need:
                        out.append(".alias %s $%04X" % ("L%04X" % (a + k), a + k))
                if img[a] in ccpu.UNCOND or (a in self.indirect and img[a] in ccpu.UNCOND):
                    out.append("")
                a += v["len"]
                continue
            # data run
            in_static = False
            start = a
            buf = []
            seg = self.segs.get(a)
            if seg:
                # a decoded table record: one line, the record explained
                buf = list(img[a:a + seg[0]])
                a += seg[0]
            else:
                while a < 0x2000 and a not in self.ins and len(buf) < 8:
                    if buf and (a in need or a == 0x1000 or a in self.segs):
                        break
                    buf.append(img[a])
                    a += 1
            notes = [seg[1]] if seg else []
            if start - 1 in self.owner or start == 0x1000:
                # first line of a data region: who reads it
                rd = set()
                b = start
                while b < 0x2000 and b not in self.owner and not (b == 0x1000 and b != start):
                    rd |= self.readers.get(b, set())
                    b += 1
                if rd:
                    region = ("$%04X-$%04X, read by LKP at " % (start, b - 1) +
                              ", ".join(self.name(s) for s in sorted(rd)[:6]) + (" ..." if len(rd) > 6 else ""))
                else:
                    region = "$%04X-$%04X, not read in the traces" % (start, b - 1)
                if seg:
                    out.append(";" + region)       # keep the record's own comment on its line
                else:
                    notes.append(region)
            if start in names.NOTES:
                notes.insert(0, names.NOTES[start])
            if start in names.LABELS:
                out.append(self.name(start) + ":")
            if seg and seg[2] and seg[2] != self.name(start):
                out.append(seg[2] + ":")
            out.append(self.line("L%04X" % start, ".byte " + ", ".join("$%02X" % x for x in buf), notes))
        out.append("")
        out.append(";End of ROM. The CCPU has no vectors: it starts at $0000 on reset and on a")
        out.append(";watchdog timeout.")
        with open(LISTING, "w", newline="\n") as f:
            f.write("\n".join(out) + "\n")
        refs = {"ram": sorted({self.ram_name((p << 4) | (img[a] & 15)) for a, v in self.ins.items()
                               if img[a] >> 4 in (6, 7, 0xA, 0xB, 0xC, 0xD) and len(v["p"]) == 1 for p in v["p"]}),
                "entries": sorted(self.entry),
                "ram_users": {"%d" % r: u for r, u in self.ram_users().items()}}
        with open(REFS, "w") as f:
            json.dump(refs, f, indent=0)
        return out


def main():
    L = Listing()
    out = L.write()
    code = sum(v["len"] for v in L.ins.values())
    print("wrote %s: %d lines, %d instructions (%d code bytes), %d routine headers"
          % (LISTING, len(out), len(L.ins), code, len(L.entry)))


if __name__ == "__main__":
    main()
