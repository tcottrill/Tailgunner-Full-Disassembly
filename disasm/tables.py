"""Decoders for the Tailgunner ROM's data tables.

Each decoder reads the table the way the code that uses it does (the routine
is named with each one) and returns its layout as segments, so emit.py can
print one line per record with the record decoded in the comment, and
emit_shapes.py can draw the same data.

segments(img) -> {addr: (length, comment, label or None)}
"""

FIGHTERS = [0x1481, 0x14C7, 0x1503, 0x1539]   # FTRn_MODEL values NEWWAVE sets ($481 $4C7 $503 $539)
TESTFIG = (0x1031, 0x105F)                     # TESTLOOP: OBJ_VERTS = $31, OBJ_EDGES = $31 + $2E
LETTERS = [(0x1A1B, 0x1A35), (0x1A3E, 0x1A70), (0x1A7A, 0x1AAC), (0x1AB8, 0x1AE7)]  # TITLE3D
CHRGRID, CHRSTROKES, CHRINDEX = 0x1BD2, 0x1BF0, 0x1C59   # PRINTCHR: strokes at $1BEF + index + 1
XHAIR = 0x0617                                 # XHAIRDRAW: RAM_16 = $615, +2 before the first read
STRINGS = [(0x1634, "TXT_SCORE"), (0x1804, "TXT_HISCORE"), (0x1870, "TXT_CREDITS"), (0x1918, "TXT_PUSHSTART")]
FORMTAB, FORMS = 0x1C7E, 8                     # NEWWAVE: $C7E + 2 * (RANDOM_LO & 7)
SINTABS = [0x0F4C, 0x15D6]
SHIELDTAB = 0x091C
STARBRT, STARPOS = 0x0267, 0x0276
SHIELDPTS = 0x03CD

CHARS = [chr(c) for c in range(0x30, 0x3A)] + [chr(c) for c in range(0x41, 0x5B)] + [" "]


def s8(b):
    """A byte biased by $80 ($80 = 0)."""
    return b - 0x80


def signed(b):
    """A two's-complement byte."""
    return b - 0x100 if b & 0x80 else b


def vertices(img, a):
    v = []
    while img[a] != 0xFF:
        v.append([s8(img[a]), s8(img[a + 1]), s8(img[a + 2])])
        a += 3
    return v, a


def edges(img, a):
    e = []
    while img[a] != 0xFF:
        e.append([img[a] >> 4, img[a] & 15])
        a += 1
    return e, a


def model_ptrs(img):
    """(name, label, vertex list, edge list) for every model."""
    out = []
    for n, a in enumerate(FIGHTERS):
        out.append(("Fighter %d" % (n + 1), "FTRMODEL%d" % (n + 1), a + 2, 0x1000 | (img[a + 1] << 8 | img[a]), a))
    for n, (v, e) in enumerate(LETTERS):
        out.append(("Letters %d" % (n + 1), "LETTERS%d" % (n + 1), v, e, None))
    out.append(("TESTFIG", "TESTFIG", TESTFIG[0], TESTFIG[1], None))
    return out


def font(img):
    grid = [[img[CHRGRID + 2 * i], img[CHRGRID + 2 * i + 1]] for i in range(15)]
    chars = {}
    starts = {}
    for n, ch in enumerate(CHARS):
        a = CHRSTROKES + img[CHRINDEX + n]
        starts.setdefault(a, []).append(ch)
        strokes = []
        while img[a] != 0xFF:
            strokes.append([img[a] >> 4, img[a] & 15])
            a += 1
        chars[ch] = strokes
    return grid, chars, starts


def string(img, a):
    s = ""
    while img[a] != 0xFF:
        s += " " if img[a] == 0x5B else chr(img[a])
        a += 1
    return s, a


def crosshair(img):
    """XHAIRDRAW: the beam starts at (-$1E, 0); x,y pairs draw, $FF x y moves, $FF $FF ends."""
    a, pen, lines, recs = XHAIR, [-0x1E, 0], [], []
    while True:
        if img[a] == 0xFF:
            if img[a + 1] == 0xFF:
                recs.append((a, 2, "end"))
                break
            pen = [s8(img[a + 1]), s8(img[a + 2])]
            recs.append((a, 3, "move to %+d, %+d" % tuple(pen)))
            a += 3
            continue
        p = [s8(img[a]), s8(img[a + 1])]
        lines.append(pen + p)
        recs.append((a, 2, "line to %+d, %+d" % tuple(p)))
        pen = p
        a += 2
    return lines, recs


def shield(img):
    """SHIELDDRAW: from the screen centre ($200, $180), a vector to each point
    in turn; a point is two bytes, each x 4 = the screen position; $FF ends."""
    a, pts, recs = SHIELDPTS, [], []
    while img[a] != 0xFF:
        p = [img[a] * 4, img[a + 1] * 4]
        pts.append(p)
        recs.append((a, 2, "point %2d: screen x $%03X  y $%03X" % (len(pts) - 1, p[0], p[1])))
        a += 2
    recs.append((a, 1, "end"))
    return pts, recs


def formations(img):
    """FORMATION: each step is 10 bytes, x / y / z for fighters 1-3 (signed bytes,
    each shifted left 4 into FTRn_DESTX/Y/Z) and the frames to the next step;
    a step time of $FF ends the pattern (the last position is held)."""
    pats = []
    for k in range(FORMS):
        ptr = 0x1000 | ((img[FORMTAB + 2 * k + 1] & 0x0F) << 8 | img[FORMTAB + 2 * k])
        steps, a = [], ptr
        while True:
            d = [img[a + i] for i in range(10)]
            steps.append((a, d))
            a += 10
            if d[9] == 0xFF:
                break
        pats.append((k, ptr, steps))
    return pats


def edge_lines(a, e, per=8):
    out = []
    for i in range(0, len(e), per):
        chunk = e[i:i + per]
        out.append((a + i, len(chunk), "edges " + " ".join("%d-%d" % tuple(x) for x in chunk)))
    return out


def segments(img):
    seg = {}

    def put(a, n, comment, label=None):
        seg[a] = (n, comment, label)

    # models
    for name, label, va, ea, hdr in model_ptrs(img):
        if hdr is not None:
            put(hdr, 2, "%s: edge list at $%04X" % (name, ea), label)
            vlabel = None
        else:
            vlabel = label
        v, vend = vertices(img, va)
        for i, (x, y, z) in enumerate(v):
            put(va + 3 * i, 3, "vertex %2d: x %+4d  y %+4d  z %+4d" % (i, x, y, z), vlabel if i == 0 else None)
        put(vend, 1, "end of vertices")
        e, eend = edges(img, ea)
        for k, (a, n, c) in enumerate(edge_lines(ea, e)):
            put(a, n, c, label + "_EDGES" if k == 0 else None)
        put(eend, 1, "end of edges")
    # crosshair and shield
    lines, recs = crosshair(img)
    for a, n, c in recs:
        seg[a] = (n, c, None)
    for a, n, c in shield(img)[1]:
        seg[a] = (n, c, None)
    # font
    grid, chars, starts = font(img)
    for i in range(15):
        put(CHRGRID + 2 * i, 2, ("point %d" % i + (" (%X)" % i if i > 9 else "")).ljust(13) + "x %2d  y %2d" % (grid[i][0], grid[i][1]))
    # stroke lists can overlap: 'Q' is one stroke followed by the strokes of '0'
    order = sorted(starts)
    for k, a in enumerate(order):
        nxt = order[k + 1] if k + 1 < len(order) else None
        b, strokes = a, []
        while img[b] != 0xFF and b != nxt:
            strokes.append("%X-%X" % (img[b] >> 4, img[b] & 15))
            b += 1
        who = "'%s'" % "', '".join(starts[a])
        if img[b] == 0xFF and b != nxt:
            put(a, b - a + 1, "%s: %s, end" % (who, " ".join(strokes)))
        else:
            put(a, b - a, "%s: %s, then the strokes of '%s'" % (who, " ".join(strokes), starts[nxt][0]))
    put(CHRINDEX, 10, "index of '0'-'9'")
    put(CHRINDEX + 10, 13, "index of 'A'-'M'")
    put(CHRINDEX + 23, 13, "index of 'N'-'Z'")
    put(CHRINDEX + 36, 1, "index of $5B (space)")
    # strings
    for a, nm in STRINGS:
        s, end = string(img, a)
        put(a, end - a + 1, "\"%s\", $FF" % s)
    # formations
    for k in range(FORMS):
        lo, hi = img[FORMTAB + 2 * k], img[FORMTAB + 2 * k + 1]
        put(FORMTAB + 2 * k, 2, "pattern %d at $%04X" % (k, 0x1000 | (hi & 15) << 8 | lo))
    for k, ptr, steps in formations(img):
        for n, (a, d) in enumerate(steps):
            pos = "  ".join("%+d,%+d,%+d" % (signed(d[3 * f]), signed(d[3 * f + 1]), signed(d[3 * f + 2])) for f in range(3))
            t = "last" if d[9] == 0xFF else "%d frames" % d[9]
            put(a, 10, "pattern %d step %d: %s  (%s)" % (k, n, pos, t), "FORM%d" % k if n == 0 else None)
    # sine tables
    for base in SINTABS:
        for i in range(0, 33, 8):
            n = min(8, 33 - i)
            put(base + i, n, "sine x 255, entries %d-%d (32 = a quarter turn)" % (i, i + n - 1) if n > 1 else "sine x 255, entry 32: sin 90 degrees")
    # shield points for the DIP setting
    put(SHIELDTAB, 8, "DIP setting 0-7: " + " ".join("%X" % img[SHIELDTAB + i] for i in range(8)) + " shield points (BCD)")
    return seg
