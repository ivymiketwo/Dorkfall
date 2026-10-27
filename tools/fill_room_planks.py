"""Rex's generated rooms sometimes come back with the floor cut out (transparent) and no plank seams
left to follow (tools/fill_room_floor.py needs the seams). This draws a whole wooden plank floor
into every see-through pixel inside the walls, and can fill a counter top too.

  python3 tools/fill_room_planks.py <original.png> <out.png> [--counter x0 y0 x1 y1]
      [--floor R G B] [--top R G B]

Floor = transparent pixels that can't be reached from the picture's edges (so the margin around
the room stays see-through). Planks run left-right, PLANK px tall, in random lengths with staggered
joints, each plank its own slightly different tone with a little grain. Transparent pixels inside
the --counter box (picture px, inclusive) get a lighter counter-top wood instead.
Same picture every run (fixed seed).
"""
import argparse
import random
from collections import deque

from PIL import Image

PLANK = 7


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--counter", type=int, nargs=4)
    ap.add_argument("--floor", type=int, nargs=3, default=(112, 80, 70))
    ap.add_argument("--top", type=int, nargs=3, default=(134, 98, 82))
    a = ap.parse_args()
    im = Image.open(a.src).convert("RGBA")
    W, H = im.size
    px = im.load()

    outside = [[False] * H for _ in range(W)]
    q = deque()
    for x in range(W):
        q.append((x, 0)); q.append((x, H - 1))
    for y in range(H):
        q.append((0, y)); q.append((W - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= W or y >= H or outside[x][y] or px[x, y][3] > 0:
            continue
        outside[x][y] = True
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    rng = random.Random(5)

    def shade(base, t):
        return tuple(max(0, min(255, int(c + t))) for c in base) + (255,)

    # planks: for each row of planks, the x where each plank starts and its tone
    rows = {}
    for r in range(H // PLANK + 1):
        x, cuts = -rng.randint(0, 40), []
        while x < W:
            cuts.append((x, rng.uniform(-8, 8)))
            x += rng.randint(22, 46)
        rows[r] = cuts

    def plank_at(x, y):
        r = y // PLANK
        start, tone = rows[r][0]
        for s, t in rows[r]:
            if s <= x:
                start, tone = s, t
        return r, start, tone

    c = a.counter
    for y in range(H):
        for x in range(W):
            if outside[x][y] or px[x, y][3] > 0:
                continue
            if c and c[0] <= x <= c[2] and c[1] <= y <= c[3]:
                # counter top: long boards, a thin light edge along the front
                t = -6 if (y - c[1]) % 5 == 4 else rng.uniform(-2, 2)
                if y == c[3]:
                    t = 10
                px[x, y] = shade(a.top, t)
                continue
            r, start, tone = plank_at(x, y)
            seam = y % PLANK == PLANK - 1 or x == start
            if seam:
                px[x, y] = shade(a.floor, -34)
                continue
            t = tone + rng.uniform(-2.5, 2.5)
            if (x * 7 + r * 13) % 19 == 0:
                t -= 6                        # a little grain
            if y % PLANK == 0:
                t += 6                        # catch light just under a seam
            px[x, y] = shade(a.floor, t)
    im.save(a.out)


if __name__ == "__main__":
    main()
