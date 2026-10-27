"""Draw tgtrace's frame SVGs onto one contact-sheet PNG (needs Pillow).

usage: python svg2png.py <svgdir> <out.png> [name ...]
"""
import os, re, sys
from PIL import Image, ImageDraw

LINE = re.compile(r"x1='(-?\d+)' y1='(-?\d+)' x2='(-?\d+)' y2='(-?\d+)' stroke='(#\w+)' stroke-width='([\d.]+)'")
W, H, SCALE = 1024, 800, 0.5


def render(path):
    im = Image.new("RGB", (int(W * SCALE), int(H * SCALE) + 16), "black")
    d = ImageDraw.Draw(im)
    for m in LINE.finditer(open(path).read()):
        x1, y1, x2, y2 = (int(v) * SCALE for v in m.groups()[:4])
        w = max(1, int(float(m.group(6)) * SCALE + 0.5))
        d.line((x1, y1 + 16, x2, y2 + 16), fill=m.group(5), width=w)
    d.text((4, 2), os.path.basename(path)[:-4], fill="#0f0")
    return im


def main():
    svgdir, out = sys.argv[1], sys.argv[2]
    names = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(svgdir) if f.endswith(".svg"))
    tiles = [render(os.path.join(svgdir, n + ".svg")) for n in names]
    cols = 4
    tw, th = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tw + 4), rows * (th + 4)), "#333")
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * (tw + 4), (i // cols) * (th + 4)))
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
