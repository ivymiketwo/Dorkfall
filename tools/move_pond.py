"""One-off (October 2026): moved the village pond 32 world px east to make room for the new
wizard tower. Only the ground square g_4_2 is edited: the painted water and its sandy bank are
lifted out, pasted 32 px further east, and the uncovered strip on the west is filled with the
grass just west of it. The pond's collision (scripts/world.gd), its water-shader sprite
(WaterPond1 in main.tscn) and the ducks (scripts/ducks.gd) were moved by the same amount.
Kept for reference; running it again would move the pond again."""
from PIL import Image, ImageFilter

SQUARE = "art/ground/g_4_2.png"
SQ_ORIGIN = (4 * 1024, 2 * 1024)        # art px of this square in the whole painting
WORLD_ORIGIN = (-1680, -992)
SHIFT = 32 * 2                           # art px (32 world px)
REGION = (430, 60, 650, 205)             # world rect around the pond


def to_sq(wx, wy):
    return ((wx - WORLD_ORIGIN[0]) * 2 - SQ_ORIGIN[0], (wy - WORLD_ORIGIN[1]) * 2 - SQ_ORIGIN[1])


def main():
    sq = Image.open(SQUARE).convert("RGB")
    x0, y0 = to_sq(REGION[0], REGION[1])
    x1, y1 = to_sq(REGION[2], REGION[3])
    px = sq.load()
    water = Image.new("L", sq.size)
    wp = water.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if b > r + 40 and b > g:
                wp[x, y] = 255
    # keep only the pond itself (the biggest patch of blue), not blue flower specks
    seen, best = set(), set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if wp[x, y] and (x, y) not in seen:
                comp, todo = set(), [(x, y)]
                seen.add((x, y))
                while todo:
                    cx, cy = todo.pop()
                    comp.add((cx, cy))
                    for q in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if x0 <= q[0] < x1 and y0 <= q[1] < y1 and wp[q] and q not in seen:
                            seen.add(q)
                            todo.append(q)
                if len(comp) > len(best):
                    best = comp
    water = Image.new("L", sq.size)
    wp = water.load()
    for q in best:
        wp[q] = 255
    mask = water.filter(ImageFilter.MaxFilter(19))          # water + bank + outline
    mp = mask.load()
    old = sq.copy()
    op = old.load()
    pond = {(x, y) for y in range(y0, y1) for x in range(x0, x1) if mp[x, y]}
    moved = {(x + SHIFT, y) for (x, y) in pond}
    for (x, y) in pond - moved:                              # uncovered: grass from the west
        px[x, y] = op[x - SHIFT, y]
    for (x, y) in pond:
        px[x + SHIFT, y] = op[x, y]
    sq.save(SQUARE, optimize=True)
    print(f"moved {len(pond)} pond pixels")


if __name__ == "__main__":
    main()
