"""Extends the painted cobblestone village street east (October 2026: +48 world px for the wizard
tower, then +96 for the new potion cottage). Usage, from the repo root:

    python3 tools/extend_village_street.py <world px>

Edits ground squares g_3_2 and g_4_2: the street's last cobbles are copied onto the grass east of it
and its end border is moved to the new end. The street's collision-free path tiles in
scripts/world.gd (`x <= ...`) and the minimap must be extended by hand."""
import sys

from PIL import Image

# the street's end sits on the seam between two ground squares, so both are edited together
SQUARES = ["art/ground/g_3_2.png", "art/ground/g_4_2.png"]
SQ_ORIGIN = (3 * 1024, 2 * 1024)
WORLD_ORIGIN = (-1680, -992)


def grey(c):
    return max(c) - min(c) < 40 and sum(c) < 700


def main():
    extend = int(sys.argv[1]) * 2                 # art px
    sq = Image.new("RGB", (2048, 1024))
    for i, f in enumerate(SQUARES):
        sq.paste(Image.open(f).convert("RGB"), (i * 1024, 0))
    px = sq.load()
    mid_y = (160 - WORLD_ORIGIN[1]) * 2 - SQ_ORIGIN[1]
    x = (380 - WORLD_ORIGIN[0]) * 2 - SQ_ORIGIN[0]
    while grey(px[x + 1, mid_y]):
        x += 1
    end = x                                        # last street column (its border)
    top = mid_y
    while grey(px[end - 20, top - 1]):
        top -= 1
    bot = mid_y
    while grey(px[end - 20, bot + 1]):
        bot += 1
    border = 2
    old = sq.copy()
    body = old.crop((end - border + 1 - extend, top, end - border + 1, bot + 1))
    cap = old.crop((end - border + 1, top, end + 1, bot + 1))
    sq.paste(body, (end - border + 1, top))
    sq.paste(cap, (end - border + 1 + extend, top))
    for i, f in enumerate(SQUARES):
        sq.crop((i * 1024, 0, (i + 1) * 1024, 1024)).save(f, optimize=True)
    print("street end", end, "rows", top, bot)


if __name__ == "__main__":
    main()
