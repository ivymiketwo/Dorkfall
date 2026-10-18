"""Builds art/interior_potion_shop.png: Rex's generated potion shop room
(art/interior_src/potion_shop_generated.png, 256x256, floor left transparent) with the wooden
floorboards of the old potion shop (art/interior_src/potion_shop_old.png) laid under it.

- The floor is rebuilt plank by plank: whole planks are cut out of clean parts of the old floor
  and laid end to end in new rows, so there are no repeating seams.
- A soft shadow is added under the back wall and along the side walls, like the old room.
- A few pixels of the wall trim came out transparent in the generated picture; they are filled
  with the wall colour around them.

Run from the repo root:  python3 tools/gen_potion_interior.py
"""
import random
from collections import Counter
from PIL import Image

GEN = "art/interior_src/potion_shop_generated.png"
OLD = "art/interior_src/potion_shop_old.png"
OUT = "art/interior_potion_shop.png"

# the room in the generated picture (art px)
FLOOR = (16, 14, 239, 231)          # inner floor rectangle, inclusive
DOOR = (108, 232, 147, 255)         # the doorway gap between the door posts (around the mat)
FRAME = (10, 13, 245, 255)          # outer edge of the walls
POSTS = (102, 153)                  # below the bottom wall only the door posts belong to the room
BOTTOM_WALL_END = 244

# the old floor: plank rows are 16 px tall, the dark line between rows at y = 95, 111, ...
OLD_BAND0 = 80
BAND = 16
OLD_BANDS = 6                       # rows 80..175 are clear of the counter and rug
OLD_X = (48, 400)                   # away from the darker edges by the walls
OLD_BLOCKED = [(24, 104, 126, 156), (346, 28, 430, 130)]   # fire pit + logs, potion cabinet


def _lum(c):
    return c[0] + c[1] + c[2]


def planks(old):
    """Whole planks (a joint line on the left, then the board) cut from the old floor."""
    px = old.load()
    out = []
    for b in range(OLD_BANDS):
        y0 = OLD_BAND0 + b * BAND
        mid = range(y0 + 2, y0 + BAND - 2)
        col = [sum(_lum(px[x, y]) for y in mid) / len(mid) for x in range(old.width)]
        joints = [x for x in range(OLD_X[0], OLD_X[1])
                  if col[x] < 0.8 * min(col[x - 2], col[x + 2])]
        for a, z in zip(joints, joints[1:]):
            if z - a < 12:
                continue
            if any(not (z <= bx0 or a >= bx1 or y0 + BAND <= by0 or y0 >= by1)
                   for bx0, by0, bx1, by1 in OLD_BLOCKED):
                continue
            out.append(old.crop((a, y0, z, y0 + BAND)))
    return out


def floor_layer(w, h, top, pieces, seed=7):
    rnd = random.Random(seed)
    floor = Image.new("RGBA", (w, h))
    y = top
    last = None
    while y < h:
        x = FLOOR[0] - rnd.randrange(0, 40)
        while x <= FLOOR[2] + 1:
            p = rnd.choice(pieces)
            while p is last and len(pieces) > 1:
                p = rnd.choice(pieces)
            floor.alpha_composite(p, (x, y)) if x >= 0 else floor.alpha_composite(p.crop((-x, 0, p.width, p.height)), (0, y))
            x += p.width
            last = p
        y += BAND
    return floor


def shade(floor, wall_bottom):
    """Darker near the walls, like the old room: a shadow under the back wall and a soft
    edge along the side walls."""
    px = floor.load()
    for y in range(floor.height):
        for x in range(floor.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            k = 1.0
            d_top = y - wall_bottom
            if d_top < 12:
                k *= 0.55 + 0.45 * max(0, d_top) / 12
            d_side = min(x - FLOOR[0], FLOOR[2] - x)
            if d_side < 10:
                k *= 0.6 + 0.4 * d_side / 10
            px[x, y] = (int(r * k), int(g * k), int(b * k), a)


def fill_holes(img, holes):
    """Fills each hole pixel with the most common colour of its solid neighbours."""
    px = img.load()
    todo = set(holes)
    while todo:
        done = {}
        for (x, y) in todo:
            n = Counter()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                q = (x + dx, y + dy)
                if q not in todo and 0 <= q[0] < img.width and 0 <= q[1] < img.height and px[q][3] == 255:
                    n[px[q]] += 1
            if n:
                done[(x, y)] = n.most_common(1)[0][0]
        if not done:
            break
        for q, c in done.items():
            px[q] = c
        todo -= set(done)


def main():
    gen = Image.open(GEN).convert("RGBA")
    old = Image.open(OLD).convert("RGBA")
    gp = gen.load()

    floor_px, holes = set(), set()
    for y in range(FRAME[1], FRAME[3] + 1):
        for x in range(FRAME[0], FRAME[2] + 1):
            if gp[x, y][3] != 0:
                continue
            in_floor = FLOOR[0] <= x <= FLOOR[2] and FLOOR[1] <= y <= FLOOR[3]
            in_door = DOOR[0] <= x <= DOOR[2] and DOOR[1] <= y <= DOOR[3]
            if in_floor or in_door:
                floor_px.add((x, y))
            elif y <= BOTTOM_WALL_END or POSTS[0] <= x <= POSTS[1]:
                holes.add((x, y))
    fill_holes(gen, holes)

    # where the back wall ends: the first row that is mostly floor under the banner
    wall_bottom = min(y for y in range(FLOOR[1], FLOOR[3])
                      if sum((x, y) in floor_px for x in range(90, 170)) > 60)
    floor = floor_layer(gen.width, gen.height, wall_bottom, planks(old))
    shade(floor, wall_bottom)
    fp = floor.load()
    out = gen.copy()
    op = out.load()
    for q in floor_px:
        op[q] = fp[q]
    out.save(OUT)
    print(f"{OUT}: {out.size}, floor from y {wall_bottom}, {len(holes)} wall pixels filled")


if __name__ == "__main__":
    main()
