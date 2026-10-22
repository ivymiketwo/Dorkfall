"""Turns Rex's coin piles (art/coin_src/coins_0.png .. coins_9.png, 64x64, smallest pile first)
into the coin icons: frames 0-9 of art/items.png / art/items_small.png (one per step of
items/coins.tres stack_thresholds: 1, 2, 3, 4, 5, 25, 100, 250, 1000, 10000 coins).

    python3 tools/coin_icons.py

Each picture is halved to 32x32 by averaging each 2x2 block and snapping the result back to the
nearest colour of the picture's own palette, so it stays crisp and adds no new colours.
"""
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from new_gear import put_icon   # noqa: E402


def shrink(im):
    pal = sorted({p[:3] for p in im.get_flattened_data() if p[3] > 0}) if hasattr(im, "get_flattened_data") else sorted({p[:3] for p in im.getdata() if p[3] > 0})
    small = im.resize((im.width // 2, im.height // 2), Image.BOX)
    px = small.load()
    for y in range(small.height):
        for x in range(small.width):
            r, g, b, a = px[x, y]
            if a < 110:
                px[x, y] = (0, 0, 0, 0)
                continue
            best = min(pal, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
            px[x, y] = best + (255,)
    return small


def main():
    for i in range(10):
        im = Image.open("art/coin_src/coins_%d.png" % i).convert("RGBA")
        put_icon(shrink(im) if im.width > 32 else im, i)
    print("wrote coin icons 0-9")


if __name__ == "__main__":
    main()
