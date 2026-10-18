"""Builds the pet shop art:

- art/interior_pet_shop.png: Rex's generated room (art/interior_src/pet_shop_generated.png,
  256x256) with the old pet shop's floorboards (art/interior_src/pet_shop_old.png) laid under
  its see-through floor, plank by plank (see gen_potion_interior.py).
- art/interior_pet_counter.png: just the counter, drawn in front of the shopkeeper.
- art/pet_fat_dragon.png: the sleeping fat dragon from art/pet_pen.png (4 frames of 72x64)
  without its own straw nest, so it can lie in the big nest painted in the room.
- art/pet_dragon_idle.png: Rex's 10 idle frames of the little dragon (art/pet_dragon_src),
  side by side, 64x64 each.

Run from the repo root:  python3 tools/gen_pet_interior.py
"""
import glob
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from gen_potion_interior import floor_layer, planks, shade  # noqa: E402

GEN = "art/interior_src/pet_shop_generated.png"
OLD = "art/interior_src/pet_shop_old.png"
OUT = "art/interior_pet_shop.png"
COUNTER_OUT = "art/interior_pet_counter.png"
COUNTER = (86, 104, 169, 150)
PEN = "art/pet_pen.png"
FAT_OUT = "art/pet_fat_dragon.png"
IDLE_SRC = "art/pet_dragon_src/idle_*.png"
IDLE_OUT = "art/pet_dragon_idle.png"

FLOOR = (13, 89, 242, 239)
DOOR = (107, 240, 148, 255)


def room():
    gen = Image.open(GEN).convert("RGBA")
    old = Image.open(OLD).convert("RGBA")
    gen.crop(COUNTER).save(COUNTER_OUT)
    gp = gen.load()
    floor_px = set()
    for y in range(FLOOR[1], DOOR[3] + 1):
        for x in range(FLOOR[0], FLOOR[2] + 1):
            if gp[x, y][3] != 0:
                continue
            if y <= FLOOR[3] or DOOR[0] <= x <= DOOR[2]:
                floor_px.add((x, y))
    boards = planks(old, band0=80, bands=6, xr=(48, 400), blocked=[])
    floor = floor_layer(gen.width, gen.height, FLOOR[1], boards, seed=5, x0=FLOOR[0], x1=FLOOR[2])
    shade(floor, FLOOR[1], x0=FLOOR[0], x1=FLOOR[2])
    fp = floor.load()
    for q in floor_px:
        gp[q] = fp[q]
    gen.save(OUT)


def fat_dragon():
    """Keeps the dragon (greens, its dark outline and shadow) and the sleeping z's; drops the
    straw (yellows and browns, where red is well above green)."""
    pen = Image.open(PEN).convert("RGBA")
    px = pen.load()
    for y in range(pen.height):
        for x in range(pen.width):
            r, g, b, a = px[x, y]
            if a and r > g + 6:
                px[x, y] = (0, 0, 0, 0)
    pen.save(FAT_OUT)


def idle_sheet():
    files = sorted(glob.glob(IDLE_SRC))
    sheet = Image.new("RGBA", (64 * len(files), 64))
    for i, f in enumerate(files):
        sheet.alpha_composite(Image.open(f).convert("RGBA"), (i * 64, 0))
    sheet.save(IDLE_OUT)


if __name__ == "__main__":
    room()
    fat_dragon()
    idle_sheet()
    print("pet shop art written")
