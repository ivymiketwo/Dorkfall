"""Dresses the player in a piece of clothing / armour drawn in 4 directions, baking it INTO every
frame of the body like the robe sheet (art/player_new_robe.png), so it looks worn, not pasted on.

    python3 tools/gen_body_sheet.py art/gear_src/iron_chestplate_4dir.png art/player_iron_chestplate.png

INPUT: 192x48 PNG, four 48x48 frames: down (front), up (back), left, right, each drawn over the
first idle frame of that facing in art/player_new.png (the standing pose).

OUTPUT: a full player sheet (same layout as art/player_new.png) with the gear painted in. In game
the chest item's `body_sheet` replaces the body texture, exactly as the robe does.
A preview is written to <input name>_preview.png (red = frames worth checking).

How each frame is dressed:
  1. The standing head + torso is found in the frame (shift, plus a squash for crouches), which
     says where every gear pixel would land.
  2. The frame's own body is split into parts along its dark inner lines (arms, torso, legs are
     separated by outlines in the art). Parts that lie mostly under the gear are "covered";
     an arm swinging across the chest is its own part, so it stays bare and in front.
  3. Covered pixels are repainted with the gear's colour from the matching spot, keeping this
     frame's light and shadow (brighter or darker than the standing pose), and the body's own
     outline is kept, so the gear follows the silhouette of every pose.
Fix single frames with <input name>_fix.json: {"row,col": [dx, dy, squash]} or "skip".
"""
import json
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

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


def dress(target, stand, gear, gear_mask, dx, dy, s, anchor):
    """Returns the target frame with the gear painted in."""
    out = target.copy()
    body = target[..., 3] > 0
    L = lum(target)
    dark = body & (L < DARK)
    skin = body & ~dark
    # where the gear lands in this frame
    m = shift(squash(gear_mask[..., None].astype(np.float64), s, anchor), dx, dy)[..., 0] > 0
    # body parts: covered if mostly under the gear
    lab, n = components(skin)
    covered = np.zeros_like(skin)
    overlaps = [((lab == k) & m).sum() for k in range(1, n + 1)]
    torso = 1 + int(np.argmax(overlaps)) if overlaps and max(overlaps) > 0 else 0
    for k in range(1, n + 1):
        part = lab == k
        inside = overlaps[k - 1]
        # the torso (the part most under the gear) always; other parts only if they sit mostly
        # under it (a shoulder, a hip). An arm or leg crossing in front sticks out, so stays bare.
        if k == torso or (inside >= 4 and inside >= 0.6 * part.sum()):
            covered |= part & m
    # inner lines inside the covered area (abs, chest lines) are painted over too;
    # lines between covered and bare parts (an arm in front, the body's edge) stay
    inner = np.zeros_like(dark)
    for y in range(1, CELL - 1):
        for x in range(1, CELL - 1):
            if dark[y, x] and m[y, x]:
                if (covered[y, x - 1] and covered[y, x + 1]) or (covered[y - 1, x] and covered[y + 1, x]):
                    inner[y, x] = True
    paint = covered | inner
    gl = lum(gear)
    sl = lum(stand)
    for y in range(CELL):
        for x in range(CELL):
            if not paint[y, x]:
                continue
            # the matching spot in the standing pose
            sy = int(round(anchor + (y - dy - anchor) / s))
            sx = x - dx
            col = None
            for r in range(0, 3):                      # nearest gear pixel
                for oy in range(-r, r + 1):
                    for ox in range(-r, r + 1):
                        qy, qx = sy + oy, sx + ox
                        if 0 <= qy < CELL and 0 <= qx < CELL and gear[qy, qx, 3] > 0:
                            col = (qy, qx)
                            break
                    if col:
                        break
                if col:
                    break
            if col is None:
                continue
            g = gear[col[0], col[1], :3]
            if gl[col] < DARK:                         # the gear's own outlines / seams stay as drawn
                out[y, x, :3] = g
                out[y, x, 3] = 255
                continue
            # keep this frame's light and shadow relative to the standing pose
            ref = sl[col] if stand[col[0], col[1], 3] > 0 and sl[col] >= DARK else L[y, x]
            here = L[y, x] if not inner[y, x] else ref
            ratio = np.clip(here / max(ref, 1.0), 0.8, 1.2)
            out[y, x, :3] = np.clip(g * ratio, 0, 255)
            out[y, x, 3] = 255
    return out


def main(src, dst):
    sheet = Image.open(BASE).convert("RGBA")
    gear_img = Image.open(src).convert("RGBA")
    fix_path = os.path.splitext(src)[0] + "_fix.json"
    fixes = json.load(open(fix_path)) if os.path.exists(fix_path) else {}
    out = sheet.copy()
    preview = Image.new("RGBA", sheet.size, (90, 140, 90, 255))
    draw = ImageDraw.Draw(preview)
    unsure = 0
    for fi, facing in enumerate(FACINGS):
        gear = np.array(gear_img.crop((fi * CELL, 0, fi * CELL + CELL, CELL))).astype(np.float64)
        stand = frame(sheet, fi, 0)
        gear_mask = gear[..., 3] > 0
        rows = np.where((gear_mask & (stand[..., 3] > 0)).any(axis=1))[0]
        anchor = int(rows.max())
        fit_mask = stand[..., 3] > 0
        fit_mask[anchor + 1:] = False                  # head + body down to the gear's lower edge
        for anim, count in enumerate(FRAMES):
            row = anim * 4 + fi
            for col in range(count):
                target = frame(sheet, row, col)
                if not (target[..., 3] > 0).any():
                    continue
                key = "%d,%d" % (row, col)
                if fixes.get(key) == "skip":
                    continue
                if key in fixes:
                    cost, (dx, dy, s) = 0.0, fixes[key]
                elif anim == 0 and col == 0:
                    cost, dx, dy, s = 0.0, 0, 0, 1.0
                else:
                    cost, dx, dy, s = fit(stand, fit_mask, target, anchor)
                dressed = dress(target, stand, gear, gear_mask, int(dx), int(dy), float(s), anchor)
                tile = Image.fromarray(dressed.astype(np.uint8))
                out.paste(tile, (col * CELL, row * CELL))
                preview.alpha_composite(tile, (col * CELL, row * CELL))
                if cost > UNSURE:
                    unsure += 1
                    draw.rectangle((col * CELL, row * CELL, col * CELL + CELL - 1, row * CELL + CELL - 1), outline=(220, 40, 40, 255))
    out.save(dst)
    prev = os.path.splitext(src)[0] + "_preview.png"
    preview.resize((preview.width * 2, preview.height * 2), Image.NEAREST).save(prev)
    print("wrote %s (%d frames worth checking: red in %s)" % (dst, unsure, prev))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
