"""Builds art/interior_fishing_shop.png: Rex's generated fishing shop room
(art/interior_src/fishing_shop_generated.png, 256x256) with its floor filled back in.

The background remover took out the light floorboards and left only the dark seams between them,
so the see-through floor is repainted plank by plank: the planks run up and down, 8 px wide, lined
up with the seams that are still there, each stretch a slightly different weathered grey-brown,
darker in the shadow under the back wall.

Also writes art/interior_fishing_counter.png: the front of the counter, drawn over Old Marlow's feet.

Run from the repo root:  python3 tools/gen_fishing_interior.py
"""
import random

from PIL import Image

GEN = "art/interior_src/fishing_shop_generated.png"
OUT = "art/interior_fishing_shop.png"
COUNTER_OUT = "art/interior_fishing_counter.png"
COUNTER = (82, 98, 184, 146)        # the counter's top and front (the part in front of the keeper)
STOOL = (124, 98, 145, 105)         # the stool behind the counter: left out of the counter picture
WALL_BOTTOM = 85                    # first floor row under the back wall
ROOM_BOTTOM = 249                   # rows from here down are outside the room
DOOR = (97, 238, 159)               # the doorway gap in the bottom wall: x from, y from, x to
TONES = [(132, 116, 104), (140, 124, 110), (124, 109, 99), (136, 121, 108)]
PLANK = 8
PLANK_LEN = 40


def outside(img):
    """See-through pixels outside the room: reachable from the picture's edge without going in
    through the doorway."""
    px = img.load()
    w, h = img.size
    todo = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    seen = set()
    while todo:
        x, y = todo.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h) or px[x, y][3]:
            continue
        if DOOR[1] <= y < ROOM_BOTTOM and DOOR[0] < x < DOOR[2]:
            continue
        seen.add((x, y))
        todo += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return seen


def plank_of(x):
    # the seams sit on x = 8n on the left half of the room and x = 8n + 7 on the right half
    return x // PLANK if x < 128 else (x - 7) // PLANK


def main():
    gen = Image.open(GEN).convert("RGBA")
    counter = gen.crop(COUNTER)
    cp = counter.load()
    for y in range(STOOL[1], STOOL[3]):
        for x in range(STOOL[0], STOOL[2]):
            cp[x - COUNTER[0], y - COUNTER[1]] = (0, 0, 0, 0)
    counter.save(COUNTER_OUT)
    px = gen.load()
    out_px = outside(gen)
    rnd = random.Random(3)
    colour = {}
    out = gen.copy()
    op = out.load()
    filled = 0
    for y in range(ROOM_BOTTOM):
        for x in range(gen.width):
            if px[x, y][3] or (x, y) in out_px:
                continue
            p = plank_of(x)
            stretch = (y + (p * 13) % PLANK_LEN) // PLANK_LEN       # plank ends staggered
            if (p, stretch) not in colour:
                colour[(p, stretch)] = rnd.choice(TONES)
            k = 1.0
            d = y - WALL_BOTTOM
            if d < 12:
                k = 0.6 + 0.4 * max(d, 0) / 12                         # shadow under the back wall
            n = rnd.randint(-3, 3)
            op[x, y] = tuple(max(0, min(255, int(c * k) + n)) for c in colour[(p, stretch)]) + (255,)
            filled += 1
    out.save(OUT)
    print(f"{OUT}: {filled} floor pixels painted")


if __name__ == "__main__":
    main()
