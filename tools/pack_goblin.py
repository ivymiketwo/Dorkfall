"""Packs Rex's goblin animations (pixellab, 80x80 frames in art/goblin_src/) into art/goblin.png.

    python3 tools/pack_goblin.py

art/goblin_src/<anim>/<south|north|west|east>/frame_000.png ... (walk 6 frames, run 4, punch 6).
The sheet has 64x64 cells (the 80x80 frames cropped evenly on every side, nothing is cut off),
6 columns, 16 rows. Rows = animation * 4 + facing (down, up, left, right):
    0-3   walk  (frame 0 doubles as standing still)
    4-7   run
    8-11  punch
    12-15 the same punch mirrored: down / up are flipped in place, left is the flipped right-facing
          punch and right the flipped left-facing one, so the goblin throws it with the other hand.
The feet are at y 55 of each cell (the scene's sprite offset is -23 to stand them on the spot).
"""
import os

from PIL import Image, ImageOps

SRC = "art/goblin_src"
OUT = "art/goblin.png"
CELL = 64
CROP = 8                      # (80 - 64) / 2 trimmed from each side
COLS = 6
ANIMS = ["walk", "run", "punch"]
FACINGS = ["south", "north", "west", "east"]
MIRROR_OF = {"south": "south", "north": "north", "west": "east", "east": "west"}


def frames(anim, facing):
    d = os.path.join(SRC, anim, facing)
    out = []
    for name in sorted(os.listdir(d)):
        im = Image.open(os.path.join(d, name)).convert("RGBA")
        assert im.size == (80, 80), (anim, facing, name, im.size)
        box = im.getbbox()
        assert box is None or (box[0] >= CROP and box[1] >= CROP and box[2] <= 80 - CROP and box[3] <= 80 - CROP), \
            ("art would be cut off", anim, facing, name, box)
        out.append(im.crop((CROP, CROP, 80 - CROP, 80 - CROP)))
    return out


def main():
    sheet = Image.new("RGBA", (CELL * COLS, CELL * 16), (0, 0, 0, 0))
    for a, anim in enumerate(ANIMS):
        for f, facing in enumerate(FACINGS):
            for c, im in enumerate(frames(anim, facing)[:COLS]):
                sheet.paste(im, (c * CELL, (a * 4 + f) * CELL))
    for f, facing in enumerate(FACINGS):
        for c, im in enumerate(frames("punch", MIRROR_OF[facing])[:COLS]):
            sheet.paste(ImageOps.mirror(im), (c * CELL, (12 + f) * CELL))
    sheet.save(OUT, optimize=True)
    print(OUT, sheet.size)


if __name__ == "__main__":
    main()
