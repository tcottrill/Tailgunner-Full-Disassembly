"""Write shapes_preview.html: every picture the Tailgunner ROM draws from a
table, decoded from the ROM and drawn in the page.

  * the four fighter models and the test-pattern figure (DRAWMODEL format:
    2-byte edge-list pointer, x/y/z vertices with $80 = 0 ending in $FF,
    edges as two vertex-number nibbles ending in $FF), turning in 3D;
  * the four title-letter models (DRAWMODEL3D: vertex and edge lists named
    by the code at TITLE3D);
  * the vector font (PRINTCHR: CHRINDEX -> CHRSTROKES, each stroke joins two
    of the 15 CHRGRID points) and the four strings;
  * the crosshair (XHAIRDRAW: x,y pairs from $80, $FF = move);
  * the formation table (FORMTAB / FORMDATA).

The decoding is written in Python here; the page only draws the lists.
Also writes build/shapes.json.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import romset, tables
from tables import vertices, edges, string, STRINGS

HTML = os.path.join(HERE, "shapes_preview.html")
JSON = os.path.join(romset.BUILD, "shapes.json")


def regroup_letters(letters):
    """The title's strokes are not stored letter by letter (the R of GUNNER
    takes its upright from Letters 2). For the single-model cards, a stroke
    that lies outside its own model's area and inside another's is shown with
    that other one ("borrowed"), marked with where it is stored."""
    def box(points, pad=4):
        xs, ys = [p[0] for p in points], [p[1] for p in points]
        return min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad

    def inside(b, p):
        return b[0] <= p[0] <= b[1] and b[2] <= p[1] <= b[3]

    for m in letters:
        m["borrowed"] = []
    for i, m in enumerate(letters):
        keep = []
        for e in m["edges"]:
            p, q = m["verts"][e[0]], m["verts"][e[1]]
            others = [x for x in m["edges"] if x is not e]
            own = box([m["verts"][k] for x in others for k in x]) if others else None
            if own and (inside(own, p) or inside(own, q)):
                keep.append(e)
                continue
            fits = [n for n in letters if n is not m and inside(box(n["verts"]), p) and inside(box(n["verts"]), q)]
            # the smallest area that holds it: a word of letters, not the frame around the title
            dest = min(fits, key=lambda n: (lambda b: (b[1] - b[0]) * (b[3] - b[2]))(box(n["verts"])), default=None)
            if dest is None:
                keep.append(e)
                continue
            dest["borrowed"].append({"from": m["name"], "edge": e, "p": p, "q": q})
        m["shown_edges"] = keep


def model(img, verts, edge_list, name, addr):
    v, vend = vertices(img, verts)
    e, eend = edges(img, edge_list)
    bad = [x for x in e if x[0] >= len(v) or x[1] >= len(v)]
    assert not bad, (name, bad)
    return {"name": name, "addr": "$%04X" % addr, "verts": v, "edges": e,
            "range": "$%04X-$%04X" % (addr, eend)}

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tailgunner ROM Pictures</title>
<style>
:root{--bg:#0b0d10;--panel:#151a20;--ink:#d8dee6;--dim:#8a96a3;--beam:#e8f4ff;--accent:#6fd3ff;--line:#2a323c}
@media (prefers-color-scheme: light){:root:not([data-theme="dark"]){--bg:#f4f6f8;--panel:#ffffff;--ink:#1d232a;--dim:#5b6673;--beam:#0d1a26;--accent:#0067a3;--line:#d5dbe1}}
:root[data-theme="light"]{--bg:#f4f6f8;--panel:#ffffff;--ink:#1d232a;--dim:#5b6673;--beam:#0d1a26;--accent:#0067a3;--line:#d5dbe1}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:32px 0 8px}
p{color:var(--dim);margin:4px 0 12px;max-width:75ch}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px}
.card canvas{width:100%;aspect-ratio:1/1;display:block;background:#000;border-radius:4px}
.card .t{font-weight:600}.card .s{color:var(--dim);font-size:12px;font-family:ui-monospace,Consolas,monospace}
.font{display:flex;flex-wrap:wrap;gap:6px}
.font .card{padding:6px;width:72px}.font canvas{aspect-ratio:3/4}
.strings canvas{width:100%;height:auto;aspect-ratio:auto}
code{font-family:ui-monospace,Consolas,monospace}
label{color:var(--dim)}
</style></head><body><main>
<h1>Tailgunner: every picture in the ROM</h1>
<p>Decoded from the program ROM by <code>disasm/emit_shapes.py</code>; the names are the labels of
<code>tailgunner_program_rom.asm</code>. The models turn here for viewing only; in the game the
fighters bank by their velocity.</p>
<label><input type="checkbox" id="spin" checked> turn the models</label>
<h2>Fighter models (MODELS)</h2>
<p>Vertex lists of x, y, z bytes ($80 = 0, $FF ends) and edge lists of two vertex numbers per byte.
NEWWAVE puts one of the four in each fighter's FTRn_MODEL.</p>
<div class="grid" id="fighters"></div>
<h2>Title letters (LETTERS)</h2>
<p>The 3D models TITLE3D flies in during attract mode, same format. The four are drawn together from
one origin, and the strokes are not split by letter: the R of GUNNER takes its upright from Letters 2
(vertices 14-15, $1A6A-$1A6D) and its bowl and leg from Letters 3. The single models below keep
their place in that shared frame.</p>
<div class="grid" id="title"></div>
<div class="grid" id="letters" style="margin-top:12px"></div>
<h2>Test pattern (TESTFIG)</h2>
<p>Drawn by TESTMODE when the game is powered on with START held.</p>
<div class="grid" id="test"></div>
<h2>Crosshair (XHAIRSHP) and shield (SHIELDPTS)</h2>
<p>The shield is one path from the screen centre through the 12 points (screen positions, byte x 4):
a lattice of diamonds across the whole screen. In the game each segment's brightness changes from frame
to frame.</p>
<div class="grid" id="xhair"></div>
<h2>Vector font (CHRGRID / CHRSTROKES / CHRINDEX)</h2>
<p>Each stroke joins two of 15 grid points (5 across, 3 down). PRINT maps '0'-'9', 'A'-'Z' and $5B (space).</p>
<div class="font" id="font"></div>
<h2>Strings</h2>
<div class="grid strings" id="strings"></div>
<script>
const D = __DATA__;
const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
function card(parent, title, sub, ratio){
  const c = document.createElement('div'); c.className = 'card';
  const cv = document.createElement('canvas'); c.appendChild(cv);
  const t = document.createElement('div'); t.className = 't'; t.textContent = title; c.appendChild(t);
  const s = document.createElement('div'); s.className = 's'; s.textContent = sub; c.appendChild(s);
  parent.appendChild(c); return cv;
}
function setup(cv, w, h){
  const r = window.devicePixelRatio || 1;
  const cw = cv.clientWidth || 240, ch = h ? cw * h / w : cw;
  cv.width = cw * r; cv.height = ch * r; const g = cv.getContext('2d'); g.scale(r, r);
  return [g, cw, ch];
}
const models = [];
const PART_COLORS = ['#ffd166', '#6fd3ff', '#ff7aa8', '#9be38f'];
// parts: [{m, color}] drawn in one frame. frame: the models whose vertices set
// the shared centre and scale (so models meant to be seen together keep
// their real positions relative to one another).
function addModel(parent, title, sub, parts, sway, frame){
  const cv = card(parent, title, sub);
  const all = (frame || parts.map(p => p.m)).flatMap(m => m.verts);
  const c = [0, 1, 2].map(k => (Math.min(...all.map(v => v[k])) + Math.max(...all.map(v => v[k]))) / 2);
  let R = 1; for (const v of all) R = Math.max(R, Math.hypot(v[0] - c[0], v[1] - c[1], v[2] - c[2]));
  models.push({cv, parts, R, c, sway});
}
function drawModel(o, t){
  const [g, w, h] = setup(o.cv);
  g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
  const a = o.sway ? 0.5 * Math.sin(t * 0.0007) : t * 0.0006, b = 0.35 * Math.sin(t * 0.0004);
  const ca = Math.cos(a), sa = Math.sin(a), cb = Math.cos(b), sb = Math.sin(b);
  const proj = ([x, y, z]) => {
    x -= o.c[0]; y -= o.c[1]; z -= o.c[2];
    let X = x * ca - z * sa, Z = x * sa + z * ca; let Y = y * cb - Z * sb; Z = y * sb + Z * cb;
    const s = (w * 0.42) / o.R * (3 / (3 + Z / o.R));
    return [w / 2 + X * s, h / 2 - Y * s];
  };
  for (const {m, color, edges, lines, dashed} of o.parts){
    g.strokeStyle = color || '#e8f4ff'; g.lineWidth = 1.2; g.setLineDash(dashed ? [4, 3] : []); g.beginPath();
    if (m){ const P = m.verts.map(proj); for (const [i, j] of (edges || m.edges)){ g.moveTo(...P[i]); g.lineTo(...P[j]); } }
    for (const [p, q] of lines || []){ g.moveTo(...proj(p)); g.lineTo(...proj(q)); }
    g.stroke();
  }
  g.setLineDash([]);
}
const info = m => m.addr + '  ' + m.verts.length + ' vertices, ' + m.edges.length + ' edges';
D.fighters.forEach(m => addModel(document.getElementById('fighters'), m.name, info(m), [{m}]));
addModel(document.getElementById('title'), 'TITLE3D: all four models',
         'each model in its own colour: Letters 1 yellow, 2 blue, 3 pink, 4 green',
         D.letters.map((m, n) => ({m, color: PART_COLORS[n]})), true);
D.letters.forEach(m => {
  const parts = [{m, edges: m.shown_edges}];
  let sub = info(m);
  if (m.borrowed.length){
    parts.push({lines: m.borrowed.map(b => [b.p, b.q]), dashed: true, color: '#ffd166'});
    sub += '; dashed: ' + m.borrowed.map(b => b.from + ' edge ' + b.edge.join('-')).join(', ') + ' (stored there)';
  }
  const moved = D.letters.flatMap(n => n.borrowed.filter(b => b.from === m.name));
  if (moved.length) sub += '; ' + moved.length + ' stroke(s) stored here are drawn with ' +
    D.letters.filter(n => n.borrowed.some(b => b.from === m.name)).map(n => n.name).join(', ');
  addModel(document.getElementById('letters'), m.name, sub, parts, true, D.letters);
});
addModel(document.getElementById('test'), 'TESTFIG', info(D.testfig), [{m: D.testfig}], true);
let t0 = 0;
function frame(t){ if (document.getElementById('spin').checked) t0 = t; models.forEach(o => drawModel(o, t0)); requestAnimationFrame(frame); }
requestAnimationFrame(frame);
{ // crosshair
  const cv = card(document.getElementById('xhair'), 'XHAIRSHP', '$0617  ' + D.xhair.length + ' lines');
  const [g, w, h] = setup(cv); g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
  g.strokeStyle = '#e8f4ff'; g.lineWidth = 1.5; g.beginPath(); const s = w / 80;
  for (const [x1, y1, x2, y2] of D.xhair){ g.moveTo(w/2 + x1*s, h/2 - y1*s); g.lineTo(w/2 + x2*s, h/2 - y2*s); }
  g.stroke();
}
{ // shield: screen coordinates, 1024 x 780 visible, y up
  const cv = card(document.getElementById('xhair'), 'SHIELDPTS', '$03CD  ' + D.shield.length + ' points, from the centre ($200, $180)');
  const [g, w, h] = setup(cv); g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
  const s = w / 1024, oy = (h - 780 * s) / 2;
  g.strokeStyle = '#e8f4ff'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(0x200 * s, h - oy - 0x180 * s);
  for (const [x, y] of D.shield) g.lineTo(x * s, h - oy - y * s);
  g.stroke();
}
function drawChar(g, ch, x0, y0, s){
  for (const [i, j] of D.font.chars[ch] || []){
    const a = D.font.grid[i], b = D.font.grid[j];
    g.moveTo(x0 + a[0]*s, y0 - a[1]*s); g.lineTo(x0 + b[0]*s, y0 - b[1]*s);
  }
}
for (const ch of Object.keys(D.font.chars)){
  const cv = card(document.getElementById('font'), ch === ' ' ? 'space' : ch, '');
  const [g, w, h] = setup(cv, 3, 4); g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
  g.strokeStyle = '#e8f4ff'; g.lineWidth = 1.5; g.beginPath(); const s = w / 26;
  drawChar(g, ch, 5*s, h - 6*s, s); g.stroke();
}
for (const st of D.strings){
  const cv = card(document.getElementById('strings'), st.name, st.addr + '  "' + st.text + '"');
  const [g, w, h] = setup(cv, 4, 1); g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
  g.strokeStyle = '#e8f4ff'; g.lineWidth = 1.3; g.beginPath();
  const s = Math.min(w / (st.text.length * 24 + 8), h / 34);
  [...st.text].forEach((ch, n) => drawChar(g, ch, 6*s + n * 24 * s, h/2 + 12*s, s)); g.stroke();
}
</script></main></body></html>
"""


def main():
    img = romset.load_image()
    ms = [model(img, va, ea, name, hdr if hdr is not None else va)
          for name, label, va, ea, hdr in tables.model_ptrs(img)]
    fighters, letters, testfig = ms[:4], ms[4:8], ms[8]
    regroup_letters(letters)
    grid, chars, starts = tables.font(img)
    data = {
        "fighters": fighters, "letters": letters, "testfig": testfig,
        "font": {"grid": grid, "chars": chars},
        "xhair": tables.crosshair(img)[0],
        "shield": tables.shield(img)[0],
        "strings": [{"name": nm, "addr": "$%04X" % a, "text": string(img, a)[0]} for a, nm in STRINGS],
        "formations": [{"pattern": k, "addr": "$%04X" % ptr, "steps": [d for a, d in steps]}
                       for k, ptr, steps in tables.formations(img)],
    }
    with open(JSON, "w") as f:
        json.dump(data, f, indent=1)
    with open(HTML, "w", newline="\n", encoding="utf-8") as f:
        f.write(PAGE.replace("__DATA__", json.dumps(data, separators=(",", ":"))))
    print("wrote %s: %d fighter models, %d letter models, %d characters, %d strings"
          % (HTML, len(fighters), len(letters), len(chars), len(STRINGS)))
    for m in fighters + letters + [testfig]:
        print("  %-10s %s  %2d vertices %2d edges" % (m["name"], m["range"], len(m["verts"]), len(m["edges"])))
    for s in data["strings"]:
        print("  %-14s %s" % (s["name"], s["text"]))


if __name__ == "__main__":
    main()
