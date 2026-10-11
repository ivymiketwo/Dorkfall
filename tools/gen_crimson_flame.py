"""Builds art/crimson_flame.png, the Crimson Swarm landing flame, from Rex's drawing
(art/crimson_flame_src/flame_original.png).

The drawing is shrunk to fit one landing circle (each output pixel takes the most common
colour of the pixels it covers, so it stays crisp pixel art), then turned into frames:
  0-2   burst up from the ground
  3-8   flicker loop (tongues lick up and down, shades shimmer, sparks rise)
  9-11  die down
Every frame gets a 1 px half-opacity dark outline.
Run: python3 tools/gen_crimson_flame.py
"""
from collections import Counter
import math
import random
from PIL import Image

SRC = "art/crimson_flame_src/flame_original.png"
OUT = "art/crimson_flame.png"
TARGET_W = 22                      # art px (= 11 world px; a landing circle is 12 across)
FW, FH = 26, 30                    # frame size; flame base sits on the bottom row
rng = random.Random(7)

src = Image.open(SRC).convert("RGBA")
src = src.crop(src.getbbox())
sw, sh = src.size
tw = TARGET_W
th = round(sh * tw / sw)
sp = src.load()


def shrink():
    """Mode downscale: each target pixel = most common colour (or empty) in its box."""
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    op = out.load()
    for y in range(th):
        for x in range(tw):
            x0, x1 = x * sw / tw, (x + 1) * sw / tw
            y0, y1 = y * sh / th, (y + 1) * sh / th
            votes = Counter()
            for yy in range(int(y0), math.ceil(y1)):
                for xx in range(int(x0), math.ceil(x1)):
                    wx = min(xx + 1, x1) - max(xx, x0)
                    wy = min(yy + 1, y1) - max(yy, y0)
                    votes[sp[xx, yy]] += wx * wy
            # empty only wins if it covers most of the box (keeps thin tongues)
            empty = sum(v for c, v in votes.items() if c[3] == 0)
            filled = {c: v for c, v in votes.items() if c[3] > 0}
            if filled and sum(filled.values()) >= empty * 0.8:
                op[x, y] = max(filled, key=filled.get)
    return out


base = shrink()
bp = base.load()
# shades of the drawing, darkest to brightest (for the shimmer)
shades = sorted({bp[x, y] for x in range(tw) for y in range(th) if bp[x, y][3]},
                key=lambda c: c[0] + c[1] + c[2])
shade_i = {c: i for i, c in enumerate(shades)}
bright = shades[-1]
ox = (FW - tw) // 2
oy = FH - th


def blank():
    return Image.new("RGBA", (FW, FH), (0, 0, 0, 0))


def squash(k):
    """The flame squashed down to `k` of its height, base on the ground."""
    h = max(1, round(th * k))
    f = blank()
    f.paste(base.resize((tw, h), Image.NEAREST), (ox, FH - h))
    return f


def flicker(t):
    """One flicker frame; t = 0..1 around the loop. Every pixel looks up where it comes from
    (so nothing tears open): columns stretch up or sink a little, out of step with their
    neighbours, and the upper part sways."""
    f = blank()
    fp = f.load()
    for y in range(-4, th):
        for x in range(tw):
            hf = 1.0 - y / th                                  # 0 at the base, 1 at the tip
            if hf <= 0.2:
                sx, sy = x, y                                  # the base stays put
            else:
                stretch = 1.5 * math.sin(t * math.tau + x * 1.3) + 0.6 * math.sin(t * math.tau * 2 + x * 0.7)
                sy = y + round(stretch * (hf - 0.2) * 1.6)
                sx = x - round(0.8 * hf * hf * math.sin(t * math.tau + y * 0.45))
            if not (0 <= sx < tw and 0 <= sy < th):
                continue
            c = bp[sx, sy]
            if not c[3]:
                continue
            # shimmer: a few pixels step a shade brighter or darker
            n = math.sin(x * 12.9898 + y * 78.233 + t * 40.0) * 43758.5
            n -= math.floor(n)
            i = shade_i[c]
            if n < 0.08:
                i = min(i + 1, len(shades) - 1)
            elif n > 0.95:
                i = max(i - 1, 0)
            px, py = ox + x, oy + y
            if 0 <= py < FH:
                fp[px, py] = shades[i]
    # sparks rising off the top
    for s in range(3):
        life = (t + s / 3.0) % 1.0
        sx = ox + tw // 2 + round((s - 1) * 5 + 2 * math.sin(life * 6 + s))
        sy = oy + round(th * 0.3) - round(life * 9)
        if 0 <= sx < FW and 0 <= sy < FH and life < 0.85:
            fp[sx, sy] = bright
    return f


def die(k):
    """Sinking to `k` of its height, with holes opening up."""
    f = squash(k)
    fp = f.load()
    for y in range(FH):
        for x in range(FW):
            if fp[x, y][3] and rng.random() < (1.0 - k) * 0.45:
                fp[x, y] = (0, 0, 0, 0)
    return f


frames = [squash(0.35), squash(0.7), squash(1.15)]
frames += [flicker(i / 6.0) for i in range(6)]
frames += [die(0.7), die(0.45), die(0.22)]
OUTLINE = (40, 0, 6, 128)          # half-opacity dark outline round every frame


def outline(f):
    """Adds a 1 px half-opacity outline around the flame (and its sparks)."""
    out = f.copy()
    fp, op = f.load(), out.load()
    for y in range(FH):
        for x in range(FW):
            if fp[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < FW and 0 <= ny < FH and fp[nx, ny][3] == 255:
                    op[x, y] = OUTLINE
                    break
    return out


frames = [outline(f) for f in frames]
sheet = Image.new("RGBA", (FW * len(frames), FH), (0, 0, 0, 0))
for i, f in enumerate(frames):
    sheet.paste(f, (FW * i, 0), f)
sheet.save(OUT)
print("frames", len(frames), "frame", FW, FH, "flame", tw, th)
