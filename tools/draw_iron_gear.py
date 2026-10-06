"""Draws the iron helm and iron greaves as 4-direction sprites (front, back, left, right), fitted
to the standing pose using the body-part map (head / legs areas of each standing frame).

    python3 tools/draw_iron_gear.py

Output: art/gear_src/iron_helm_4dir.png and art/gear_src/iron_greaves_4dir.png (192x48 each).
Like the chestplate (draw_iron_chestplate.py) these are what an artist would draw by hand;
tools/new_gear.py then fits them onto every frame.
"""
import os
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from draw_iron_chestplate import OUTLINE, STEEL, TRIM, RIVET, lum   # noqa: E402
from gen_part_map import COLORS, PLAIN                               # noqa: E402

SRC = "art/player_new.png"
MAP = "art/gear_src/body_parts.png"
FACINGS = ["down", "up", "left", "right"]
LEATHER = (92, 60, 36)


def area(i, part):
    m = np.array(Image.open(MAP).convert("RGBA").crop((0, i * 48, 48, i * 48 + 48))).astype(int)
    hit = np.zeros((48, 48), bool)
    for c in COLORS[part] + [PLAIN[part]]:
        hit |= (m[..., 3] > 0) & (np.abs(m[..., :3] - np.array(c)).sum(axis=2) <= 6)
    return hit


def steel(p):
    L = lum(p)
    if L < 70:
        return OUTLINE
    return STEEL[0] if L < 150 else STEEL[1] if L < 170 else STEEL[2] if L < 192 else STEEL[3]


def helm(frame, facing, head):
    a = np.array(frame)
    out = np.zeros_like(a)
    ys, xs = np.where(head)
    top, bottom = ys.min(), ys.max()
    cx = int(round(xs.mean()))
    # eye line: first row with two or more dark pixels inside the head (front / sides)
    dark = (a[..., 3] > 0) & (np.array([[lum(a[y, x]) for x in range(48)] for y in range(48)]) < 70)
    eye = None
    for y in range(top + 3, bottom):
        inner = [x for x in range(48) if dark[y, x] and head[y, x - 1] and head[y, x + 1]] if 0 < cx < 47 else []
        if len(inner) >= 1:
            eye = y
            break
    if eye is None or facing == "up":
        eye = bottom + 1                              # back view: the whole head is covered
    rows = {}
    for y, x in zip(ys, xs):
        rows.setdefault(y, []).append(x)
    for y, x in zip(ys, xs):
        lo, hi = min(rows[y]), max(rows[y])
        cover = y < eye
        if facing == "down":
            cover |= x <= lo + 1 or x >= hi - 1        # cheek guards
            cover |= x == cx and y <= eye + 1          # nose guard
        elif facing == "left":
            cover |= x >= cx + 1                       # back of the head (face looks left)
        elif facing == "right":
            cover |= x <= cx - 1
        if cover:
            out[y, x] = (*steel(a[y, x]), 255)
    # brow band just above the eyes, with rivets; a bright rim on the crown
    if facing != "up":
        for x in rows.get(eye - 1, []):
            if out[eye - 1, x, 3] and tuple(out[eye - 1, x, :3]) != OUTLINE:
                out[eye - 1, x] = (*STEEL[0], 255)
        for x in (min(rows.get(eye - 1, [cx])) + 1, max(rows.get(eye - 1, [cx])) - 1):
            if out[eye - 1, x, 3]:
                out[eye - 1, x] = (*RIVET, 255)
    for x in range(48):
        col = [y for y in range(48) if out[y, x, 3] and tuple(out[y, x, :3]) != OUTLINE]
        if col:
            out[col[0], x] = (*TRIM, 255)
    if facing == "up":
        for y in range(top + 2, bottom):              # a ridge down the back of the helm
            if out[y, cx, 3] and tuple(out[y, cx, :3]) != OUTLINE:
                out[y, cx] = (*STEEL[0], 255)
    return Image.fromarray(out)


def greaves(frame, facing, legs):
    a = np.array(frame)
    out = np.zeros_like(a)
    ys, xs = np.where(legs)
    top, bottom = ys.min(), ys.max()
    knee = top + (bottom - top) * 2 // 3
    for y, x in zip(ys, xs):
        out[y, x] = (*steel(a[y, x]), 255)
        if y == top:
            out[y, x] = (*LEATHER, 255)               # a leather strap at the top
        elif y == bottom:
            out[y, x] = (*OUTLINE, 255) if lum(a[y, x]) < 70 else (*STEEL[0], 255)   # rim over the feet
        elif (y - top) % 4 == 0 and y < knee - 1:
            if tuple(out[y, x, :3]) != OUTLINE:
                out[y, x] = (*STEEL[1], 255)          # plate bands down the thigh
    # knee caps: a bright spot in the middle of each leg at knee height
    for y in (knee, knee + 1):
        row = [x for x in range(48) if legs[y, x]]
        if not row:
            continue
        runs, run = [], [row[0]]
        for x in row[1:]:
            if x == run[-1] + 1:
                run.append(x)
            else:
                runs.append(run)
                run = [x]
        runs.append(run)
        for r in runs:
            mid = r[len(r) // 2]
            if tuple(out[y, mid, :3]) != OUTLINE:
                out[y, mid] = (*(TRIM if y == knee else STEEL[3]), 255)
    return Image.fromarray(out)


def main():
    sheet = Image.open(SRC).convert("RGBA")
    for name, part, fn in (("iron_helm", "head", helm), ("iron_greaves", "legs", greaves)):
        out = Image.new("RGBA", (192, 48))
        for i, facing in enumerate(FACINGS):
            out.paste(fn(sheet.crop((0, i * 48, 48, i * 48 + 48)), facing, area(i, part)), (i * 48, 0))
        path = "art/gear_src/%s_4dir.png" % name
        out.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
