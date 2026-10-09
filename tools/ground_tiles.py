"""The painted ground, cut into squares for streaming (see scripts/ground_stream.gd).

The ground is one big painting: world x -1680..6512, y -992..1696, at 2 art pixels per world
pixel (16384 x 5376 art pixels). It is stored as squares of 512 world px (1024 art px) in
art/ground/g_<col>_<row>.png so the game only loads the ones near the camera.

    from ground_tiles import assemble, split
    img = assemble()        # the whole painting as one PIL image
    ...edit it...
    split(img)              # write the squares back

Squares that are entirely VOID (the unreachable land around the east ravine that the camera
never sees) are not stored at all; assemble() fills missing squares with VOID.

Run directly to cut the squares from the old four big chunk images:  python3 tools/ground_tiles.py
"""
import os
from PIL import Image

ORIGIN = (-1680, -992)      # world position of the painting's top-left corner
ART_SCALE = 2               # art pixels per world pixel
TILE_WORLD = 512
TILE_ART = TILE_WORLD * ART_SCALE
SIZE_ART = (16384, 5376)
COLS = -(-SIZE_ART[0] // TILE_ART)
ROWS = -(-SIZE_ART[1] // TILE_ART)
DIR = "art/ground"
VOID = (13, 11, 18)          # same as the game's background colour


def tile_path(c, r):
    return os.path.join(DIR, "g_%d_%d.png" % (c, r))


def assemble():
    img = Image.new("RGB", SIZE_ART)
    for r in range(ROWS):
        for c in range(COLS):
            if os.path.exists(tile_path(c, r)):
                img.paste(Image.open(tile_path(c, r)).convert("RGB"), (c * TILE_ART, r * TILE_ART))
            else:
                img.paste(VOID, (c * TILE_ART, r * TILE_ART, (c + 1) * TILE_ART, (r + 1) * TILE_ART))
    return img


def split(img):
    os.makedirs(DIR, exist_ok=True)
    for r in range(ROWS):
        for c in range(COLS):
            box = (c * TILE_ART, r * TILE_ART, min((c + 1) * TILE_ART, SIZE_ART[0]), min((r + 1) * TILE_ART, SIZE_ART[1]))
            square = img.crop(box)
            if square.getcolors(1) == [(square.width * square.height, VOID)]:
                for p in (tile_path(c, r), tile_path(c, r) + ".import"):
                    if os.path.exists(p):
                        os.remove(p)
                continue
            square.save(tile_path(c, r), optimize=True)


def _from_old_chunks():
    img = Image.new("RGB", SIZE_ART)
    for cx, cy in [(0, 0), (1, 0), (0, 1), (1, 1)]:
        img.paste(Image.open("art/ground_%d_%d.png" % (cx, cy)).convert("RGB"), (cx * 4800, cy * 2688))
    return img


if __name__ == "__main__":
    split(_from_old_chunks())
    print("cut into %d x %d squares in %s" % (COLS, ROWS, DIR))
