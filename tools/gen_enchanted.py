"""Paints the enchanted forest's ground (world x 6512..9456, east of the troll valley) and its part
of the minimap.

    python3 tools/gen_enchanted.py

  - Blue-teal moss in soft patches with little grass tufts and a scattering of glowing flowers.
  - Darker forest floor under the dense forests: the polygons of the nodes named EnchForest* in
    scenes/main.tscn, so move / reshape those in the editor and re-run this to match.
  - A lilac-grey dirt path (PATH) from the troll pass to the middle of the clearing.
  - The minimap gets the forests (dark), the path and the single trees (EnchTree* nodes) as dots.
  - The mountain's cliffs carry on past the pass along Rex's lines (painted by tools/gen_ravine.py,
    run that first): that rock is kept as it is, and the valley's grey ground fades into the moss
    over the first few hundred px past the pass.
Only the ground squares east of x 6512 (columns 16..21) and that part of art/world_map.png are
written; everything west of the pass is left alone. Same picture every run (fixed SEED).
"""
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ground_tiles import ORIGIN, ART_SCALE, TILE_ART, SIZE_ART, tile_path   # noqa: E402

SEED = 7
X0, X1 = 6512, 9456                 # world x of this biome
Y0, Y1 = ORIGIN[1], 1696
COL0 = (X0 - ORIGIN[0]) * ART_SCALE // TILE_ART      # first ground column (16)
W = (X1 - X0) * ART_SCALE
H = SIZE_ART[1]
# the path from the troll pass to the middle of the clearing (world px) and its width
PATH = [(6440, 192), (6512, 192), (6700, 196), (6900, 212), (7100, 236), (7300, 262), (7550, 288),
        (7800, 310), (8050, 330)]
PATH_W = 30
EAST_WALK = "art/ground_src/ravine_east_walk.png"   # written by tools/gen_ravine.py
SEAM = 220                          # world px over which the valley's grey ground fades into moss

MOSS = np.array([(41, 61, 83), (47, 70, 92), (54, 80, 100), (63, 92, 110)], np.float32)
FLOOR = np.array([(28, 38, 58), (33, 45, 66), (38, 52, 74)], np.float32)     # under the forests
TUFT = (34, 50, 72)
TUFT_TIP = (92, 124, 146)
FLOWERS = [((176, 150, 240), 0.0006), ((128, 218, 234), 0.00045), ((226, 152, 222), 0.0003),
           ((236, 236, 255), 0.00015)]        # (only inside flower patches, see main)
DIRT = np.array([(92, 84, 94), (104, 95, 104), (118, 108, 116)], np.float32)
DIRT_EDGE = (66, 58, 72)
PEBBLE = (138, 128, 136)


def noise(w, h, cell, rng, octaves=3):
    out = np.zeros((h, w), np.float32)
    total = 0.0
    amp = 1.0
    for _ in range(octaves):
        gw, gh = max(2, w // cell + 2), max(2, h // cell + 2)
        g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
        out += amp * np.asarray(g.resize((w, h), Image.BICUBIC), np.float32) / 255.0
        total += amp
        amp *= 0.5
        cell = max(2, cell // 2)
    return out / total


def forest_polygons():
    s = open("scenes/main.tscn").read()
    polys = []
    for block in re.split(r"\n(?=\[)", s):
        if not re.match(r'\[node name="EnchForest\w*"', block):
            continue
        pos = re.search(r"\nposition = Vector2\(([-\d.e]+), ([-\d.e]+)\)", block)
        ox, oy = (float(pos.group(1)), float(pos.group(2))) if pos else (0.0, 0.0)
        pts = re.search(r"\npolygon = PackedVector2Array\(([^)]*)\)", block)
        if not pts:
            continue
        v = [float(t) for t in pts.group(1).split(",")]
        polys.append([(v[i] + ox, v[i + 1] + oy) for i in range(0, len(v), 2)])
    return polys


def single_trees():
    s = open("scenes/main.tscn").read()
    out = []
    for block in re.split(r"\n(?=\[)", s):
        if re.match(r'\[node name="EnchTree\d+"', block):
            pos = re.search(r"\nposition = Vector2\(([-\d.e]+), ([-\d.e]+)\)", block)
            if pos:
                out.append((float(pos.group(1)), float(pos.group(2))))
    return out


def to_art(x, y):
    return ((x - X0) * ART_SCALE, (y - Y0) * ART_SCALE)


def rock_mask():
    """True where tools/gen_ravine.py painted the mountain's rock (its cliffs reach past the pass
    along Rex's lines): those pixels are kept as they are. Also returns what was painted there."""
    rock = np.zeros((H, W), bool)
    prev = np.zeros((H, W, 3), np.uint8)
    if not os.path.exists(EAST_WALK):
        return rock, prev
    walk = np.asarray(Image.open(EAST_WALK)) > 127
    w = min(walk.shape[1], W)
    rock[:walk.shape[0], :w] = ~walk[:, :w]
    for c in range(-(-w // TILE_ART)):
        for r in range(-(-H // TILE_ART)):
            p = tile_path(COL0 + c, r)
            if os.path.exists(p):
                t = np.asarray(Image.open(p).convert("RGB"))
                prev[r * TILE_ART:r * TILE_ART + t.shape[0], c * TILE_ART:c * TILE_ART + t.shape[1]] = t
    return rock, prev


def main():
    rng = np.random.default_rng(SEED)
    rock, prev = rock_mask()
    # ---- moss: soft patches in four tones (dithered edges), darker under the forests
    big = noise(W, H, 360, rng)
    mid = noise(W, H, 90, rng)
    fine = rng.random((H, W)).astype(np.float32)
    v = 0.6 * big + 0.4 * mid + (fine - 0.5) * 0.015
    tone = np.digitize(v, [0.40, 0.50, 0.60])
    img = MOSS[tone]
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    for poly in forest_polygons():
        d.polygon([to_art(*p) for p in poly], fill=255)
    forest = np.asarray(mask) > 0
    ftone = np.digitize(mid + (fine - 0.5) * 0.08, [0.45, 0.58])
    img[forest] = FLOOR[ftone[forest]]

    # ---- the path
    pm = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(pm)
    pts = [to_art(*p) for p in PATH]
    wob = noise(W, H, 30, rng, 2)
    d.line(pts, fill=255, width=PATH_W * ART_SCALE, joint="curve")
    for p in pts:
        r = PATH_W * ART_SCALE // 2
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=255)
    end = pts[-1]
    d.ellipse((end[0] - 70, end[1] - 50, end[0] + 70, end[1] + 50), fill=255)     # a little open patch
    path = np.asarray(pm.filter(__import__("PIL.ImageFilter", fromlist=["x"]).GaussianBlur(5)), np.float32) / 255.0
    path = path + (wob - 0.5) * 0.5 > 0.5
    dtone = np.digitize(mid + (fine - 0.5) * 0.12, [0.42, 0.6])
    img[path] = DIRT[dtone[path]]
    edge = path & ~(np.roll(path, 1, 0) & np.roll(path, -1, 0) & np.roll(path, 1, 1) & np.roll(path, -1, 1))
    img[edge] = DIRT_EDGE
    peb = path & (rng.random((H, W)) < 0.004)
    img[peb] = PEBBLE

    img = img.astype(np.uint8)
    # ---- tufts and flowers on the open moss
    open_moss = ~forest & ~path & ~rock
    ys, xs = np.nonzero(open_moss & (rng.random((H, W)) < 0.0018))
    for y, x in zip(ys, xs):
        if 2 <= x < W - 3 and 2 <= y < H - 2:
            img[y, x] = img[y, x + 2] = TUFT
            img[y + 1, x + 1] = TUFT
            img[y - 1, x + 1] = TUFT_TIP
    patches = noise(W, H, 120, rng, 2) > 0.62           # flowers grow in little patches
    for col, dens in FLOWERS:
        ys, xs = np.nonzero(open_moss & patches & (rng.random((H, W)) < dens))
        for y, x in zip(ys, xs):
            img[y:y + 2, x:x + 2] = col

    # ---- the seam: the valley's grey ground (painted on past the pass by gen_ravine.py) fading
    # into the moss; and the mountain's rock kept just as gen_ravine.py painted it
    strip = prev[:, :SEAM * ART_SCALE]
    xs_ = np.arange(SEAM * ART_SCALE)[None, :] / (SEAM * ART_SCALE)
    keep = (noise(SEAM * ART_SCALE, H, 70, rng, 2) * 0.8 + 0.1) > xs_ ** 0.8
    ya = (np.arange(H)[:, None] / ART_SCALE + Y0)
    keep &= (ya > 40) & (ya < 340)                  # only along the way out of the pass
    from scipy.ndimage import binary_fill_holes
    keep = binary_fill_holes(keep)                  # no little moss puddles inside the grey
    keep &= ~forest[:, :SEAM * ART_SCALE]
    seam = img[:, :SEAM * ART_SCALE]
    seam[keep] = strip[keep]
    img[rock] = prev[rock]

    # ---- write the squares
    cols = -(-W // TILE_ART)
    for c in range(cols):
        for r in range(-(-H // TILE_ART)):
            sq = img[r * TILE_ART:(r + 1) * TILE_ART, c * TILE_ART:(c + 1) * TILE_ART]
            Image.fromarray(sq).save(tile_path(COL0 + c, r), optimize=True)
    print("ground squares", COL0, "..", COL0 + cols - 1)

    # ---- minimap: one pixel per 16 world px tile
    m = Image.open("art/world_map.png").convert("RGBA")
    a = np.asarray(m)
    tx0 = (X0 - ORIGIN[0]) // 16
    tw = (X1 - X0) // 16
    th = a.shape[0]
    out = np.zeros((th, tx0 + tw, 4), np.uint8)
    out[:, :min(a.shape[1], tx0)] = a[:, :tx0]
    T = 16 * ART_SCALE
    small = img[:th * T, :tw * T].reshape(th, T, tw, T, 3).mean(axis=(1, 3))
    fsmall = forest[:th * T, :tw * T].reshape(th, T, tw, T).mean(axis=(1, 3)) > 0.5
    col = small.copy()
    col[fsmall] = (30, 34, 72)
    chk = (np.add.outer(np.arange(th), np.arange(tw)) % 2 == 1) & fsmall
    col[chk] = (36, 40, 82)
    for x, y in single_trees():                       # the scattered trees as dark dots
        tx, ty = int((x - X0) // 16), int((y - Y0) // 16)
        if 0 <= tx < tw and 0 <= ty < th:
            col[ty, tx] = (26, 30, 62)
    out[:, tx0:tx0 + tw, :3] = np.clip(col * 1.15, 0, 255).astype(np.uint8)
    out[:, tx0:tx0 + tw, 3] = 255
    # the mountain's tiles past the pass keep the colours gen_ravine.py gave them
    rsmall = rock[:th * T, :tw * T].reshape(th, T, tw, T).mean(axis=(1, 3)) > 0.5
    if a.shape[1] >= tx0 + tw:
        out[:, tx0:tx0 + tw][rsmall] = a[:, tx0:tx0 + tw][rsmall]
    Image.fromarray(out).save("art/world_map.png")
    print("minimap", out.shape[1], "x", th)


if __name__ == "__main__":
    main()
