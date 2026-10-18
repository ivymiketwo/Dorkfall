"""Builds art/interior_wizard_shop.png: Rex's generated wizard shop room
(art/interior_src/wizard_shop_generated.png, 256x256) with its see-through parts filled in:

- the floor: the old wizard shop's stone bricks (art/interior_src/wizard_shop_old.png), rebuilt
  brick by brick like the potion shop's floorboards (see gen_potion_interior.py);
- the back wall: the same bricks, darker, with a shadow at the top and a stone sill under the
  window;
- the arched window is left see-through: the animated night sky (art/wiz_window.png, the Window
  node in interior_wizard_shop.tscn) shows through it from behind the room.

Also writes art/interior_wizard_counter.png: just the counter, drawn in front of the shopkeeper.

Run from the repo root:  python3 tools/gen_wizard_interior.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from gen_potion_interior import fill_holes, floor_layer, planks, shade  # noqa: E402

GEN = "art/interior_src/wizard_shop_generated.png"
OLD = "art/interior_src/wizard_shop_old.png"
OUT = "art/interior_wizard_shop.png"
COUNTER_OUT = "art/interior_wizard_counter.png"
COUNTER = (80, 98, 177, 157)

INNER_X = (27, 228)
WALL_Y = (27, 95)          # back wall (behind the bookcases)
FLOOR_Y = (96, 209)
DOOR = (110, 210, 145, 240)
WINDOW = (113, 41, 140, 79)   # the arch's opening: stays see-through
SILL_Y = 80
SILL_X = (105, 148)
WALL_DARK = 0.74
WALL_TINT = (0.9, 0.82, 1.08)   # a little more purple than the floor

# old floor: brick rows 16 px tall from y 80; clear of the fire pit and the relic pedestal
OLD_BLOCKED = [(24, 80, 110, 120), (340, 70, 420, 135)]


def main():
    gen = Image.open(GEN).convert("RGBA")
    old = Image.open(OLD).convert("RGBA")
    gen.crop(COUNTER).save(COUNTER_OUT)
    gp = gen.load()

    floor_px, wall_px = set(), set()
    for y in range(WALL_Y[0], DOOR[3] + 1):
        for x in range(INNER_X[0], INNER_X[1] + 1):
            if gp[x, y][3] != 0:
                continue
            if WINDOW[0] <= x <= WINDOW[2] and WINDOW[1] <= y <= WINDOW[3]:
                continue
            if y <= WALL_Y[1]:
                wall_px.add((x, y))
            elif y <= FLOOR_Y[1] or (DOOR[0] <= x <= DOOR[2]):
                floor_px.add((x, y))

    bricks = planks(old, band0=80, bands=6, xr=(40, 410), blocked=OLD_BLOCKED)
    x0, x1 = INNER_X
    floor = floor_layer(gen.width, gen.height, FLOOR_Y[0], bricks, seed=11, x0=x0, x1=x1)
    shade(floor, FLOOR_Y[0], x0=x0, x1=x1)
    wall = floor_layer(gen.width, gen.height, WALL_Y[0] - 5, bricks, seed=23, x0=x0, x1=x1)
    wp = wall.load()
    for y in range(wall.height):
        for x in range(wall.width):
            r, g, b, a = wp[x, y]
            if a:
                k = WALL_DARK * (0.7 + 0.3 * min(1.0, (y - WALL_Y[0]) / 20.0))   # shadow under the ceiling
                wp[x, y] = (int(r * k * WALL_TINT[0]), int(g * k * WALL_TINT[1]), min(255, int(b * k * WALL_TINT[2])), a)
    fp = floor.load()
    for q in floor_px:
        gp[q] = fp[q]
    for q in wall_px:
        gp[q] = wp[q]
    # a stone sill under the window, in the arch's colours
    for x in range(SILL_X[0], SILL_X[1] + 1):
        gp[x, SILL_Y] = (179, 164, 205, 255)
        gp[x, SILL_Y + 1] = (119, 102, 145, 255)
        gp[x, SILL_Y + 2] = (43, 50, 97, 255)
    gen.save(OUT)
    print(f"{OUT}: floor {len(floor_px)} px, wall {len(wall_px)} px")


if __name__ == "__main__":
    main()
