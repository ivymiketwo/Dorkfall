"""Moves the village pond east in the ground painting (Oct 2026: +32 px, then +144 px, to make
room for the new wizard tower and potion cottage). Usage, from the repo root:

    python3 tools/move_pond.py <world px east> <region x0 y0 x1 y1 around the pond now>

The painted water and its sandy bank are lifted out and pasted further east; the grass that was
there is swapped back into the uncovered spot (or grass from even further east where the old and
new spots overlap). Edits ground squares g_3_2..g_5_2 only. The pond's collision ellipse
(scripts/world.gd), its water-shader sprite (WaterPond1 in main.tscn), the ducks (scripts/ducks.gd)
and the minimap must be moved by the same amount by hand."""
import sys

from PIL import Image, ImageFilter

SQUARES = ["art/ground/g_3_2.png", "art/ground/g_4_2.png", "art/ground/g_5_2.png"]
SQ_ORIGIN = (3 * 1024, 2 * 1024)
WORLD_ORIGIN = (-1680, -992)


def to_img(wx, wy):
    return ((wx - WORLD_ORIGIN[0]) * 2 - SQ_ORIGIN[0], (wy - WORLD_ORIGIN[1]) * 2 - SQ_ORIGIN[1])


def main():
    shift = int(sys.argv[1]) * 2
    region = [int(v) for v in sys.argv[2:6]]
    img = Image.new("RGB", (3072, 1024))
    for i, f in enumerate(SQUARES):
        img.paste(Image.open(f).convert("RGB"), (i * 1024, 0))
    x0, y0 = to_img(region[0], region[1])
    x1, y1 = to_img(region[2], region[3])
    px = img.load()
    blue = {(x, y) for y in range(y0, y1) for x in range(x0, x1)
            if px[x, y][2] > px[x, y][0] + 40 and px[x, y][2] > px[x, y][1]}
    # keep only the pond itself (the biggest patch of blue), not blue flower specks
    seen, best = set(), set()
    for p in blue:
        if p in seen:
            continue
        comp, todo = set(), [p]
        seen.add(p)
        while todo:
            cx, cy = todo.pop()
            comp.add((cx, cy))
            for q in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if q in blue and q not in seen:
                    seen.add(q)
                    todo.append(q)
        if len(comp) > len(best):
            best = comp
    water = Image.new("L", img.size)
    wp = water.load()
    for q in best:
        wp[q] = 255
    mask = water.filter(ImageFilter.MaxFilter(19))          # water + bank + outline
    mp = mask.load()
    old = img.copy()
    op = old.load()
    pond = {(x, y) for y in range(y0, y1) for x in range(x0, x1) if mp[x, y]}
    moved = {(x + shift, y) for (x, y) in pond}
    for (x, y) in pond - moved:                              # uncovered: grass from where it goes
        k = 1
        while (x + k * shift, y) in pond:
            k += 1
        px[x, y] = op[x + k * shift, y]
    for (x, y) in pond:
        px[x + shift, y] = op[x, y]
    for i, f in enumerate(SQUARES):
        img.crop((i * 1024, 0, (i + 1) * 1024, 1024)).save(f, optimize=True)
    print(f"moved {len(pond)} pond pixels {shift // 2} px east")


if __name__ == "__main__":
    main()
