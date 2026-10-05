"""Makes a FIRST DRAFT of the body-part map: art/gear_src/body_parts.png.

    python3 tools/gen_part_map.py            (never overwrites an existing map; --force to redo)

The map has the same layout as art/player_new.png (9 x 12 frames of 48x48). Every pixel of the
body is painted a flat colour saying which piece of the body it is, and which quarter of that
piece (top-left, top-right, bottom-left, bottom-right, as seen on screen in that frame):

    piece   top-left        top-right       bottom-left     bottom-right
    head    255,  80,  80   255, 160,  80   190,  40,  40   190, 110,  40
    chest    60, 210,  60    60, 210, 210    20, 120,  20    20, 120, 120
    arms    255, 120, 210   210, 150, 255   180,  50, 140   130,  80, 200
    legs     80, 120, 255   150, 100, 255    40,  60, 170    90,  50, 170
    feet    255, 230,  60   255, 255, 170   190, 170,  30   190, 190, 110

The draft is automatic and imperfect. Fix it by hand (any paint program, pencil tool, no
smoothing): paint each pixel with the colour of the piece and quarter it should get. Gear is then
copied quarter by quarter: whatever is in the chest's top-left quarter of the standing frame
lands in the chest's top-left quarter of every other frame, stretched to fit.
A legend is written to art/gear_src/body_parts_legend.png.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_body_sheet import BASE, CELL, FRAMES, FACINGS, frame, fit, components, lum, DARK   # noqa: E402

OUT = "art/gear_src/body_parts.png"
PARTS = ["head", "chest", "arms", "legs", "feet"]
COLORS = {
    "head":  [(255, 80, 80), (255, 160, 80), (190, 40, 40), (190, 110, 40)],
    "chest": [(60, 210, 60), (60, 210, 210), (20, 120, 20), (20, 120, 120)],
    "arms":  [(255, 120, 210), (210, 150, 255), (180, 50, 140), (130, 80, 200)],
    "legs":  [(80, 120, 255), (150, 100, 255), (40, 60, 170), (90, 50, 170)],
    "feet":  [(255, 230, 60), (255, 255, 170), (190, 170, 30), (190, 190, 110)],
}

# Standing pose of each facing (first idle frame), read off the art:
#   neck = last head row, waist = last chest row, ankle = last leg row,
#   chest columns below the shoulders; anything else at chest height is arm.
STAND = {
    "down":  dict(neck=16, shoulders=22, waist=31, ankle=41, chest=(19, 30), chest_low=(20, 29)),
    "up":    dict(neck=15, shoulders=20, waist=31, ankle=40, chest=(18, 31), chest_low=(20, 30)),
    "left":  dict(neck=16, shoulders=20, waist=32, ankle=41, chest=(20, 28), chest_low=(23, 28)),
    "right": dict(neck=16, shoulders=20, waist=32, ankle=41, chest=(19, 27), chest_low=(21, 26)),
}


def stand_labels(img, facing):
    sp = STAND[facing]
    lab = np.full((CELL, CELL), -1, dtype=np.int32)
    body = img[..., 3] > 0
    for y in range(CELL):
        for x in range(CELL):
            if not body[y, x]:
                continue
            if y <= sp["neck"]:
                p = "head"
            elif y <= sp["waist"]:
                lo, hi = sp["chest"] if y <= sp["shoulders"] else sp["chest_low"]
                p = "chest" if lo <= x <= hi else "arms"
            elif y <= sp["ankle"]:
                p = "legs"
            else:
                p = "feet"
            lab[y, x] = PARTS.index(p)
    return lab


def label_frame(target, stand, stand_lab, dx, dy, s, anchor, facing):
    body = target[..., 3] > 0
    lab = np.full((CELL, CELL), -1, dtype=np.int32)
    # each pixel: the label of the matching spot in the standing pose (nearest labelled pixel)
    sl_y, sl_x = np.where(stand_lab >= 0)
    for y in range(CELL):
        for x in range(CELL):
            if not body[y, x]:
                continue
            sy = anchor + (y - dy - anchor) / s
            sx = x - dx
            d = (sl_y - sy) ** 2 + (sl_x - sx) ** 2
            lab[y, x] = stand_lab[sl_y[d.argmin()], sl_x[d.argmin()]]
    # body parts split along the inner lines vote: a clear majority claims the whole part
    skin = body & (lum(target) >= DARK)
    comp, n = components(skin)
    for k in range(1, n + 1):
        part = comp == k
        votes = np.bincount(lab[part][lab[part] >= 0], minlength=len(PARTS))
        if votes.sum() and votes.max() >= 0.7 * votes.sum():
            lab[part] = votes.argmax()
    # sanity rules: below the waist is legs; at head height but wider than the head is an arm
    sp = STAND[facing]
    head_cols = np.where((stand_lab == PARTS.index("head")).any(axis=0))[0]
    for y in range(CELL):
        sy = anchor + (y - dy - anchor) / s
        for x in range(CELL):
            if lab[y, x] < 0:
                continue
            sx = x - dx
            if sy > sp["waist"] + 1 and lab[y, x] in (PARTS.index("chest"), PARTS.index("arms"), PARTS.index("head")):
                lab[y, x] = PARTS.index("legs")
            elif lab[y, x] == PARTS.index("head") and (sx < head_cols.min() - 1 or sx > head_cols.max() + 1 or sy > sp["neck"] + 1):
                lab[y, x] = PARTS.index("arms")
    # feet: the lowest few rows of each leg
    legs = lab == PARTS.index("legs")
    lcomp, ln = components(legs)
    for k in range(1, ln + 1):
        ys = np.where((lcomp == k).any(axis=1))[0]
        if len(ys) >= 6:
            low = ys.max() - 2
            lab[(lcomp == k) & (np.arange(CELL)[:, None] >= low)] = PARTS.index("feet")
    return lab


def paint(lab):
    out = np.zeros((CELL, CELL, 4), dtype=np.uint8)
    for pi, p in enumerate(PARTS):
        m = lab == pi
        if not m.any():
            continue
        ys, xs = np.where(m)
        my, mx = np.median(ys), np.median(xs)
        for y, x in zip(ys, xs):
            q = (0 if y < my else 2) + (0 if x < mx else 1)
            out[y, x] = (*COLORS[p][q], 255)
    return out


def legend():
    img = Image.new("RGB", (5 * 70 + 10, 90), (30, 30, 36))
    d = ImageDraw.Draw(img)
    for i, p in enumerate(PARTS):
        x = 10 + i * 70
        d.text((x, 6), p, fill=(230, 230, 230))
        for q in range(4):
            qx, qy = x + (q % 2) * 28, 22 + (q // 2) * 28
            d.rectangle((qx, qy, qx + 24, qy + 24), fill=COLORS[p][q])
        d.text((x, 78), "TL TR / BL BR", fill=(160, 160, 160))
    img.save("art/gear_src/body_parts_legend.png")


def main():
    if os.path.exists(OUT) and "--force" not in sys.argv:
        sys.exit("%s already exists (hand edits!). Use --force to overwrite it." % OUT)
    sheet = Image.open(BASE).convert("RGBA")
    out = Image.new("RGBA", sheet.size)
    for fi, facing in enumerate(FACINGS):
        stand = frame(sheet, fi, 0)
        slab = stand_labels(stand, facing)
        anchor = STAND[facing]["waist"]
        fit_mask = stand[..., 3] > 0
        fit_mask[anchor + 1:] = False
        for anim, count in enumerate(FRAMES):
            row = anim * 4 + fi
            for col in range(count):
                target = frame(sheet, row, col)
                if not (target[..., 3] > 0).any():
                    continue
                if anim == 0 and col == 0:
                    lab = slab
                else:
                    _, dx, dy, s = fit(stand, fit_mask, target, anchor)
                    lab = label_frame(target, stand, slab, dx, dy, s, anchor, facing)
                out.paste(Image.fromarray(paint(lab)), (col * CELL, row * CELL))
    out.save(OUT)
    legend()
    print("wrote", OUT)


if __name__ == "__main__":
    main()
