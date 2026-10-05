"""Dresses the player in gear drawn in 4 directions, using the body-part map, and bakes it into
every frame of the body like the robe sheet (art/player_new_robe.png).

    python3 tools/gen_body_sheet.py art/gear_src/iron_chestplate_4dir.png art/player_iron_chestplate.png [parts]

parts: which body pieces the gear covers, comma separated (default "chest"; e.g. "chest,arms" for
a shirt with sleeves, "head" for a hood). Pieces: head, chest, arms, legs, feet.

INPUT: 192x48 PNG, four 48x48 frames: down (front), up (back), left, right, each drawn over the
first idle frame of that facing in art/player_new.png (the standing pose).
MAP: art/gear_src/body_parts.png (see tools/gen_part_map.py) says, for every pixel of every frame,
which piece of the body it is and which quarter of that piece (top-left, top-right, bottom-left,
bottom-right as seen on screen).

How each pixel is painted: a covered pixel is in some quarter of a piece; its position inside that
quarter (how far across, how far down) is looked up at the same position inside the same quarter
of the standing frame, and gets the gear's colour from there. So each quarter of the gear is
stretched onto the matching quarter of the body in every pose, keeping the gear's own colours.
Pixels where the gear has nothing drawn stay as they are (bare skin).

OUTPUT: a full player sheet, same layout as art/player_new.png. A preview is written to
<input name>_preview.png.
"""
import json
import os
import sys
import numpy as np
from PIL import Image

BASE = "art/player_new.png"
FRAMES = [4, 4, 9]                    # idle, run, jump
FACINGS = ["down", "up", "left", "right"]
CELL = 48
SEARCH = 16
SQUASH = [1.0, 0.9, 0.8]
UNSURE = 0.30
DARK = 70                              # luminance below this is an outline / inner line


def lum(a):
    return 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]


def frame(sheet, row, col):
    return np.array(sheet.crop((col * CELL, row * CELL, col * CELL + CELL, row * CELL + CELL))).astype(np.float64)


def squash(img, s, anchor):
    if s == 1.0:
        return img
    out = np.zeros_like(img)
    for y in range(CELL):
        sy = int(round(anchor + (y - anchor) / s))
        if 0 <= sy < CELL:
            out[y] = img[sy]
    return out


def shift(img, dx, dy):
    out = np.zeros_like(img)
    ys, ye = max(dy, 0), min(CELL, CELL + dy)
    xs, xe = max(dx, 0), min(CELL, CELL + dx)
    out[ys:ye, xs:xe] = img[ys - dy:ye - dy, xs - dx:xe - dx]
    return out


def fit(template, mask, target, anchor):
    t_alpha = target[..., 3] > 0
    best = (9.0, 0, 0, 1.0)
    for s in SQUASH:
        tm = squash(template, s, anchor)
        mm = squash(mask[..., None].astype(np.float64), s, anchor)[..., 0] > 0
        n = mm.sum()
        for dy in range(-SEARCH, SEARCH + 1):
            for dx in range(-SEARCH, SEARCH + 1):
                m2 = shift(mm[..., None].astype(np.float64), dx, dy)[..., 0] > 0
                if m2.sum() < n * 0.9:
                    continue
                t2 = shift(tm, dx, dy)
                diff = np.abs(t2[..., :3] - target[..., :3]).sum(axis=2) / (3 * 255.0)
                cost = np.where(t_alpha, diff, 1.0)[m2].mean() + 0.004 * (abs(dx) + abs(dy)) + (1.0 - s) * 0.3
                if cost < best[0]:
                    best = (cost, dx, dy, s)
    return best


def components(skin):
    """4-connected regions of skin pixels (the dark lines separate them). Returns a label array."""
    lab = np.zeros(skin.shape, dtype=np.int32)
    n = 0
    for y in range(CELL):
        for x in range(CELL):
            if skin[y, x] and not lab[y, x]:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < CELL and 0 <= nx < CELL and skin[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
    return lab, n


MAP = "art/gear_src/body_parts.png"
PARTS = ["head", "chest", "arms", "legs", "feet"]


def read_map(map_img, row, col):
    """Per pixel (part index, quarter) from the map's colours; -1 where empty or unknown."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from gen_part_map import COLORS
    m = frame(map_img, row, col)
    part = np.full((CELL, CELL), -1, dtype=np.int32)
    quarter = np.full((CELL, CELL), -1, dtype=np.int32)
    for pi, p in enumerate(PARTS):
        for q, c in enumerate(COLORS[p]):
            hit = (m[..., 3] > 0) & (np.abs(m[..., :3] - np.array(c)).sum(axis=2) <= 6)
            part[hit] = pi
            quarter[hit] = q
    return part, quarter


def dress(target, gear, tpart, tq, spart, sq, parts):
    out = target.copy()
    for pi in parts:
        for q in range(4):
            here = (tpart == pi) & (tq == q)
            there = (spart == pi) & (sq == q)
            if not here.any() or not there.any():
                continue
            hy, hx = np.where(here)
            ty, tx = np.where(there)
            h0, h1, w0, w1 = hy.min(), hy.max(), hx.min(), hx.max()
            t0, t1, u0, u1 = ty.min(), ty.max(), tx.min(), tx.max()
            for y, x in zip(hy, hx):
                fy = (y - h0) / max(h1 - h0, 1)
                fx = (x - w0) / max(w1 - w0, 1)
                sy = t0 + fy * (t1 - t0)
                sx = u0 + fx * (u1 - u0)
                k = ((ty - sy) ** 2 + (tx - sx) ** 2).argmin()     # nearest pixel of that quarter
                g = gear[ty[k], tx[k]]
                if g[3] > 0:
                    out[y, x] = g
    return out


def main(src, dst, parts=("chest",)):
    sheet = Image.open(BASE).convert("RGBA")
    map_img = Image.open(MAP).convert("RGBA")
    gear_img = Image.open(src).convert("RGBA")
    part_ids = [PARTS.index(p) for p in parts]
    out = sheet.copy()
    preview = Image.new("RGBA", sheet.size, (90, 140, 90, 255))
    for fi, facing in enumerate(FACINGS):
        gear = np.array(gear_img.crop((fi * CELL, 0, fi * CELL + CELL, CELL))).astype(np.float64)
        spart, sq = read_map(map_img, fi, 0)
        for anim, count in enumerate(FRAMES):
            row = anim * 4 + fi
            for col in range(count):
                target = frame(sheet, row, col)
                if not (target[..., 3] > 0).any():
                    continue
                tpart, tq = read_map(map_img, row, col)
                dressed = dress(target, gear, tpart, tq, spart, sq, part_ids)
                tile = Image.fromarray(dressed.astype(np.uint8))
                out.paste(tile, (col * CELL, row * CELL))
                preview.alpha_composite(tile, (col * CELL, row * CELL))
    out.save(dst)
    prev = os.path.splitext(src)[0] + "_preview.png"
    preview.resize((preview.width * 2, preview.height * 2), Image.NEAREST).save(prev)
    print("wrote %s (preview: %s)" % (dst, prev))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], tuple(sys.argv[3].split(",")) if len(sys.argv) == 4 else ("chest",))
