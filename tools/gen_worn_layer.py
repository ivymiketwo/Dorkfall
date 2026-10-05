"""Fits a 4-direction gear sprite onto every frame of the player, walk, run and jump included.

    python3 tools/gen_worn_layer.py art/gear_src/iron_chestplate_4dir.png art/worn_iron_chestplate.png

INPUT: a 192x48 PNG with 4 frames of 48x48, in this order: down (front), up (back), left, right.
Draw each one ON TOP OF the first idle frame of that facing in art/player_new.png (the standing
pose), on a transparent background, like a paper-doll cut-out.

OUTPUT: a sheet with the same layout as art/player_new.png (9 x 12 frames). The game draws it
over the body frame by frame (Equipment does this for any item whose worn_texture has that size).
A preview is written next to the input (<name>_preview.png): every frame with the gear on, frames
the fit wasn't sure about outlined in red. Touch those up by hand in the output if needed.

How the fit works: for every frame, the standing body from the top of the head down to the
bottom of the gear is searched for in that frame (same facing), allowing a shift and a little
squash for crouches; the gear is moved the same way and trimmed to the body's outline so it never
floats off the character. Including the head keeps chest pieces from landing on it.

Fixing a frame by hand: create <input name>_fix.json next to the input, e.g.
    {"10,2": [1, 3, 0.9], "11,7": "hide"}
"row,col" -> [move right, move down, squash] (from the standing position), or "hide" to leave
that frame without the gear. Rows and columns count from 0, as in the preview.
"""
import json
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

BASE = "art/player_new.png"
FRAMES = [4, 4, 9]                    # idle, run, jump (columns used per row)
FACINGS = ["down", "up", "left", "right"]
CELL = 48
SEARCH = 16                           # pixels to search in each direction
SQUASH = [1.0, 0.9, 0.8]              # vertical scales tried (crouching jump frames)
UNSURE = 0.30                         # fit cost above this gets a red outline in the preview


def frame(sheet, row, col):
    return np.array(sheet.crop((col * CELL, row * CELL, col * CELL + CELL, row * CELL + CELL))).astype(np.int32)


def squash(img, s, anchor_y):
    """Scales an RGBA array vertically by s around row anchor_y (nearest neighbour)."""
    if s == 1.0:
        return img
    out = np.zeros_like(img)
    for y in range(CELL):
        sy = int(round(anchor_y + (y - anchor_y) / s))
        if 0 <= sy < CELL:
            out[y] = img[sy]
    return out


def shift(img, dx, dy):
    out = np.zeros_like(img)
    ys, ye = max(dy, 0), min(CELL, CELL + dy)
    xs, xe = max(dx, 0), min(CELL, CELL + dx)
    out[ys:ye, xs:xe] = img[ys - dy:ye - dy, xs - dx:xe - dx]
    return out


def fit(template, mask, target):
    """Best (cost, dx, dy, s) moving `template` (where `mask`) onto `target`."""
    t_alpha = target[..., 3] > 0
    best = (9.0, 0, 0, 1.0)
    rows = np.where(mask.any(axis=1))[0]
    anchor = int(rows.max()) if len(rows) else CELL // 2     # squash towards the waist
    for s in SQUASH:
        tm = squash(template, s, anchor)
        mm = squash(mask[..., None].astype(np.int32), s, anchor)[..., 0] > 0
        n = mm.sum()
        if n == 0:
            continue
        for dy in range(-SEARCH, SEARCH + 1):
            for dx in range(-SEARCH, SEARCH + 1):
                m2 = shift(mm[..., None].astype(np.int32), dx, dy)[..., 0] > 0
                if m2.sum() < n * 0.9:
                    continue                      # pushed off the frame
                t2 = shift(tm, dx, dy)
                diff = np.abs(t2[..., :3] - target[..., :3]).sum(axis=2) / (3 * 255.0)
                cost_px = np.where(t_alpha, diff, 1.0)
                cost = cost_px[m2].mean() + 0.004 * (abs(dx) + abs(dy)) + (1.0 - s) * 0.3
                if cost < best[0]:
                    best = (cost, dx, dy, s)
    return best


def main(src, dst):
    sheet = Image.open(BASE).convert("RGBA")
    gear = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", sheet.size)
    preview = Image.new("RGBA", sheet.size, (90, 140, 90, 255))
    draw = ImageDraw.Draw(preview)
    unsure = 0
    fix_path = os.path.splitext(src)[0] + "_fix.json"
    fixes = json.load(open(fix_path)) if os.path.exists(fix_path) else {}
    for fi, facing in enumerate(FACINGS):
        g = np.array(gear.crop((fi * CELL, 0, fi * CELL + CELL, CELL))).astype(np.int32)
        stand = frame(sheet, fi, 0)
        gear_mask = (g[..., 3] > 0) & (stand[..., 3] > 0)
        bottom = int(np.where(gear_mask.any(axis=1))[0].max())
        mask = stand[..., 3] > 0
        mask[bottom + 1:] = False                      # head + body down to the gear's lower edge
        for anim, count in enumerate(FRAMES):
            row = anim * 4 + fi
            for col in range(count):
                target = frame(sheet, row, col)
                if not (target[..., 3] > 0).any():
                    continue
                key = "%d,%d" % (row, col)
                if fixes.get(key) == "hide":
                    continue
                if key in fixes:
                    dx, dy, s = fixes[key]
                    cost = 0.0
                elif anim == 0 and col == 0:
                    cost, dx, dy, s = 0.0, 0, 0, 1.0
                else:
                    cost, dx, dy, s = fit(stand, mask, target)
                anchor = bottom
                placed = shift(squash(g, s, anchor), dx, dy)
                # trim to the body's outline (one pixel of slack so edges still show)
                body = target[..., 3] > 0
                grown = body.copy()
                grown[1:] |= body[:-1]; grown[:-1] |= body[1:]
                grown[:, 1:] |= body[:, :-1]; grown[:, :-1] |= body[:, 1:]
                placed[~grown] = 0
                tile = Image.fromarray(placed.astype(np.uint8))
                out.alpha_composite(tile, (col * CELL, row * CELL))
                body_img = Image.fromarray(target.astype(np.uint8))
                preview.alpha_composite(body_img, (col * CELL, row * CELL))
                preview.alpha_composite(tile, (col * CELL, row * CELL))
                if cost > UNSURE:
                    unsure += 1
                    draw.rectangle((col * CELL, row * CELL, col * CELL + CELL - 1, row * CELL + CELL - 1), outline=(220, 40, 40, 255))
    out.save(dst)
    prev = os.path.splitext(src)[0] + "_preview.png"
    preview.resize((preview.width * 2, preview.height * 2), Image.NEAREST).save(prev)
    print("wrote %s (%d frames to check by eye: red in %s)" % (dst, unsure, prev))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
