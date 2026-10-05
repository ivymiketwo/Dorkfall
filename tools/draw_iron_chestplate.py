"""Draws the iron chestplate as a 4-direction sprite (front, back, left, right), fitted to the
standing pose (first idle frame of each facing in art/player_new.png).

Output: art/gear_src/iron_chestplate_4dir.png (4 frames of 48x48: down, up, left, right).
That file is the kind of thing an artist draws by hand; tools/gen_worn_layer.py then fits it
onto every frame of the character. This script just paints one programmatically: it re-shades
the body's own pixels as steel inside the plate's outline, then adds trim, rivets and a belt.
"""
import numpy as np
from PIL import Image

SRC = "art/player_new.png"
OUT = "art/gear_src/iron_chestplate_4dir.png"

OUTLINE = (34, 36, 46)
STEEL = [(62, 68, 84), (98, 106, 124), (136, 145, 162), (178, 186, 200)]   # dark .. light
TRIM = (220, 226, 236)
BELT = (92, 60, 36)
BELT_DARK = (62, 40, 24)
BUCKLE = (214, 178, 84)
RIVET = (236, 240, 246)


def lum(p):
    return 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]


# plate area per facing: rows it spans, and from which row on only the torso columns
# (below that the arms hang free and stay bare)
SPEC = {
    "down":  dict(top=17, bottom=31, arms_from=23, torso=(20, 29)),
    "up":    dict(top=16, bottom=31, arms_from=21, torso=(20, 30)),
    "left":  dict(top=17, bottom=31, arms_from=21, torso=(23, 28)),
    "right": dict(top=17, bottom=31, arms_from=21, torso=(21, 26)),
}


def paint(frame, facing):
    a = np.array(frame)
    out = np.zeros_like(a)
    sp = SPEC[facing]
    body = a[..., 3] > 0
    for y in range(sp["top"], sp["bottom"] + 1):
        for x in range(48):
            if not body[y, x]:
                continue
            if y >= sp["arms_from"] and not (sp["torso"][0] <= x <= sp["torso"][1]):
                continue
            p = a[y, x]
            L = lum(p)
            if L < 70:
                col = OUTLINE
            elif L < 150:
                col = STEEL[0]
            elif L < 170:
                col = STEEL[1]
            elif L < 192:
                col = STEEL[2]
            else:
                col = STEEL[3]
            out[y, x] = (*col, 255)
    # outline the plate where it meets bare skin, so it reads as a separate piece
    plate = out[..., 3] > 0
    edge = []
    for y in range(48):
        for x in range(48):
            if not plate[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 48 and 0 <= ny < 48 and body[ny, nx] and not plate[ny, nx]:
                    edge.append((x, y))
                    break
    for x, y in edge:
        out[y, x] = (*OUTLINE, 255)
    # bottom edge: an outline under the plate, then a leather belt with a buckle
    by = sp["bottom"]
    for x in range(48):
        if out[by, x, 3]:
            out[by, x] = (*BELT, 255) if a[by, x, 3] and lum(a[by, x]) >= 70 else (*OUTLINE, 255)
            if by - 1 >= 0 and out[by - 1, x, 3] and lum(a[by - 1, x]) >= 70:
                out[by - 1, x] = (*BELT_DARK, 255)
    xs = [x for x in range(48) if out[by, x, 3] and tuple(out[by, x, :3]) == BELT]
    cx = (sp["torso"][0] + sp["torso"][1] + 1) // 2
    if facing == "down" and xs:
        out[by, cx - 1] = (*BUCKLE, 255)
        out[by, cx] = (*BUCKLE, 255)
    # front: a raised ridge down the middle and a band across the belly
    if facing == "down":
        for y in range(sp["top"] + 3, by - 1):
            if out[y, cx, 3]:
                out[y, cx] = (*TRIM, 255)
                if out[y, cx - 1, 3]:
                    out[y, cx - 1] = (*STEEL[1], 255)
        for x in range(sp["torso"][0] + 1, sp["torso"][1]):
            if out[27, x, 3]:
                out[27, x] = (*STEEL[0], 255)
    if facing == "up":
        for y in range(sp["top"] + 2, by - 1):
            if out[y, cx, 3]:
                out[y, cx] = (*STEEL[0], 255)          # back seam
    # shoulder caps: a bright rim and a rivet on each pauldron
    for x in range(48):
        for y in range(sp["top"], sp["top"] + 4):
            if out[y, x, 3] and (y == 0 or not out[y - 1, x, 3]):
                if tuple(out[y, x, :3]) != OUTLINE:
                    out[y, x] = (*TRIM, 255)
                break
    rivets = {"down": [(18, 20), (30, 20)], "up": [(19, 19), (30, 19)], "left": [(24, 19)], "right": [(23, 19)]}[facing]
    for x, y in rivets:
        if out[y, x, 3]:
            out[y, x] = (*RIVET, 255)
    return Image.fromarray(out)


if __name__ == "__main__":
    sheet = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", (48 * 4, 48))
    for i, facing in enumerate(["down", "up", "left", "right"]):
        out.paste(paint(sheet.crop((0, i * 48, 48, i * 48 + 48)), facing), (i * 48, 0))
    out.save(OUT)
    print("wrote", OUT)
