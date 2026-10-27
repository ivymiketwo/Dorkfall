"""Draws the 16x16 Q-spell icons of the staffs whose special attacks moved to Q, into art/icons.png:
    slot 8  Sun Halo         (a golden ring of light with rays)
    slot 9  Void Hole        (a black hole with a violet swirl)
    slot 10 Clockwork Spider (a brass gear with spider legs)
The sheet grows if needed. Re-run to redraw them.

    python3 tools/add_spell_icons.py
"""
import math
from PIL import Image

OUT = "art/icons.png"


def blank():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))


def ring(px, cx, cy, r0, r1, col):
    for y in range(16):
        for x in range(16):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r0 <= d < r1:
                px[x, y] = col


def sun_halo():
    im = blank()
    px = im.load()
    cx = cy = 8
    for k in range(8):                                 # rays
        a = k * math.pi / 4
        for t in (6.6, 7.4):
            x, y = int(cx + math.cos(a) * t), int(cy + math.sin(a) * t)
            if 0 <= x < 16 and 0 <= y < 16:
                px[x, y] = (255, 214, 90, 255) if t < 7 else (200, 120, 30, 255)
    ring(px, cx, cy, 3.4, 5.6, (170, 96, 24, 255))     # the halo: dark edge, gold, bright core
    ring(px, cx, cy, 3.8, 5.2, (255, 196, 64, 255))
    ring(px, cx, cy, 4.2, 4.8, (255, 246, 190, 255))
    return im


def void_hole():
    im = blank()
    px = im.load()
    cx = cy = 8
    for y in range(16):                                # a violet swirl around a black centre
        for x in range(16):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            if d < 7.2:
                arm = math.sin(a * 2 + d * 0.9)
                if d < 3.0:
                    px[x, y] = (6, 4, 12, 255)
                elif d < 3.8:
                    px[x, y] = (180, 140, 255, 255)
                elif arm > 0.25:
                    px[x, y] = (120, 70, 210, 255) if d < 5.5 else (70, 36, 130, 255)
                elif d < 6.0:
                    px[x, y] = (30, 18, 54, 255)
    return im


def clockwork_spider():
    im = blank()
    px = im.load()
    leg = (90, 56, 30, 255)
    legs = [((5, 8), (2, 5), (1, 8)), ((5, 9), (2, 11), (1, 14)), ((11, 8), (14, 5), (15, 8)),
            ((11, 9), (14, 11), (15, 14)), ((6, 6), (4, 2), (3, 4)), ((10, 6), (12, 2), (13, 4))]
    for a, b, c in legs:                               # bent legs: two straight pieces each
        for p, q in ((a, b), (b, c)):
            n = max(abs(q[0] - p[0]), abs(q[1] - p[1]))
            for i in range(n + 1):
                x = round(p[0] + (q[0] - p[0]) * i / max(n, 1))
                y = round(p[1] + (q[1] - p[1]) * i / max(n, 1))
                if 0 <= x < 16 and 0 <= y < 16:
                    px[x, y] = leg
    cx, cy = 8, 8.5
    for y in range(16):                                # a brass gear for the body
        for x in range(16):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            tooth = 4.6 if math.cos(a * 8) > 0.3 else 3.9
            if d < tooth:
                px[x, y] = (236, 170, 70, 255) if dy < -1 else (196, 120, 40, 255)
            if d < 1.6:
                px[x, y] = (255, 90, 50, 255)          # its glowing eye
    return im


def main():
    icons = {8: sun_halo(), 9: void_hole(), 10: clockwork_spider()}
    im = Image.open(OUT).convert("RGBA")
    need = (max(icons) + 1) * 16
    if im.width < need:
        bigger = Image.new("RGBA", (need, 16), (0, 0, 0, 0))
        bigger.paste(im, (0, 0))
        im = bigger
    for slot, icon in icons.items():
        im.paste(Image.new("RGBA", (16, 16), (0, 0, 0, 0)), (slot * 16, 0))
        im.paste(icon, (slot * 16, 0))
    im.save(OUT)
    print(OUT, im.size)


if __name__ == "__main__":
    main()
