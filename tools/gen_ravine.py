"""Paints the east mountains and the red-clay ravine, grows the map east to make room for it,
and writes the walls (data/mountains.json), the minimap and the cleared props list.

    python3 tools/gen_ravine.py

How it works (plain version):
  - Two curved lines (FUNNEL / RAVINE settings below) mark where you can walk: they start in the
    desert, bend toward the road and then run east side by side as the ravine.
    Everything outside them is mountain.
  - The mountain gets a height: low right at the edge, higher further in, with bumpy peaks.
    Heights come in steps (terraces), so the rock is drawn as stacked ledges.
  - It is drawn like a 3/4 view: higher ground is shifted up the screen, so the south-facing
    sides of each step show as cliff faces (layered rock) and the tops as rocky plateaus.
  - Whatever ends up looking like flat floor is walkable; everything else becomes a wall tile.
  - Land the camera can never see (well away from the ravine) is left unpainted, and those
    ground squares aren't stored at all.
Run it again after changing the settings: it always starts from the desert as it was before the
ravine (kept in art/ground_src/east_before_ravine.png), so re-running is safe.
"""
import json
import math
import os
import re
import sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ground_tiles import assemble, split, ORIGIN, VOID   # noqa: E402

SEED = 21
X0, X1 = 2400, 4720          # world x of the part this works on (east edge = new map edge)
Y0, Y1 = -992, 1696          # world y (the whole height of the map)
OLD_EDGE = 3120              # the old east edge of the map
ROAD_Y = 256                 # middle of the east-west road
FUNNEL_TOP_X = 2500          # where the north mountain line leaves the top of the map
FUNNEL_BOTTOM_X = 2520       # where the south mountain line leaves the bottom of the map
RAVINE_X = 3060              # where the funnel has narrowed into the ravine
RAVINE_END = 4470            # the ravine ends in a rounded dead end here
BEFORE = "art/ground_src/east_before_ravine.png"   # the desert as it was (each run starts from it)
STEP = 36                    # art px of cliff per terrace step (18 world px)
VIEW_HALF = (180, 110)       # world px the camera can see around the player (plus a margin)

# colours
OUT = (50, 30, 27)
FACE = np.array([(50, 30, 27), (82, 50, 40), (108, 68, 50), (136, 90, 64), (162, 114, 80), (190, 144, 104)], np.uint8)
TOP = np.array([(98, 66, 50), (126, 88, 64), (148, 106, 76), (170, 128, 92), (194, 154, 112)], np.uint8)
GRASS = np.array([(92, 92, 48), (112, 112, 58), (134, 132, 72)], np.uint8)
CLAY = np.array([(96, 44, 34), (112, 54, 41), (128, 64, 47), (146, 78, 56)], np.uint8)
CRACK = (78, 36, 29)

rng = np.random.default_rng(SEED)
W, H = (X1 - X0) * 2, (Y1 - Y0) * 2          # art size of the part
AX0 = (X0 - ORIGIN[0]) * 2                    # its art x in the whole painting


def smooth_noise(w, h, cell, octaves=3):
    out = np.zeros((h, w), np.float32)
    amp = total = 0.0
    amp = 1.0
    for o in range(octaves):
        c = max(int(cell / (2 ** o)), 4)
        gw, gh = w // c + 3, h // c + 3
        grid = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
        out += np.asarray(grid.resize((gw * c, gh * c), Image.BICUBIC), np.float32)[:h, :w] / 255.0 * amp
        total += amp
        amp *= 0.5
    return out / total


def wave(x, parts):
    return sum(a * np.sin(x / p + ph) for a, p, ph in parts)


def walls_y(wx):
    """World y of the north and south edges of the walkable ground, for world x values."""
    half = 96 + wave(wx, [(28, 170, 0.0), (14, 63, 1.0)])
    mid = ROAD_Y + wave(wx, [(26, 240, 0.5), (8, 90, 2.0)])
    end = np.clip((wx - RAVINE_END) / 110.0, 0.0, 1.0)
    half = half * np.sqrt(np.clip(1.0 - end ** 2, 0.0, 1.0))             # rounded dead end
    top = mid - half
    bottom = mid + half + 40           # the south wall's rim leans north over its foot
    top = np.where(wx > RAVINE_END + 110, 1e5, top)
    bottom = np.where(wx > RAVINE_END + 110, -1e5, bottom)
    # the funnel: the lines come down from the top / up from the bottom of the map
    t = np.clip((wx - FUNNEL_TOP_X) / (RAVINE_X - FUNNEL_TOP_X), 0.0, 1.0)
    top = np.where(wx < FUNNEL_TOP_X, -1e5, top - (top - (Y0 - 60)) * (1 - t) ** 2)
    t = np.clip((wx - FUNNEL_BOTTOM_X) / (RAVINE_X - FUNNEL_BOTTOM_X), 0.0, 1.0)
    bottom = np.where(wx < FUNNEL_BOTTOM_X, 1e5, bottom + ((Y1 + 60) - bottom) * (1 - t) ** 2)
    return top, bottom


def distance(inside, step):
    """Distance (world px) from every grid cell to the nearest cell where `inside` is true."""
    d = np.where(inside, 0.0, 1e9).astype(np.float32)
    for _ in range(100):
        p = np.pad(d, 1, constant_values=1e9)
        n = np.minimum.reduce([d, p[:-2, 1:-1] + step, p[2:, 1:-1] + step, p[1:-1, :-2] + step, p[1:-1, 2:] + step,
                               p[:-2, :-2] + step * 1.414, p[:-2, 2:] + step * 1.414,
                               p[2:, :-2] + step * 1.414, p[2:, 2:] + step * 1.414])
        if np.array_equal(n, d):
            break
        d = n
    return np.minimum(d, 400.0)


def shifted(a, dy, dx, fill):
    """a moved down by dy and right by dx; the uncovered edge gets `fill` (no wrapping round)."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def upscale(a, w, h):
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((w, h), Image.BILINEAR))


_TAB = rng.random((2, 512)).astype(np.float32)


def voronoi(x, y, cw, ch):
    """Rock chunks: for points (x, y) in art px, returns (edge, rx, ry): edge = how far from the
    border with the next chunk (px), rx / ry = position inside its own chunk (-1..1)."""
    gx, gy = x / cw, y / ch
    ix, iy = np.floor(gx).astype(np.int64), np.floor(gy).astype(np.int64)
    best = np.full(x.shape, 1e9, np.float32)
    second = np.full(x.shape, 1e9, np.float32)
    bx = np.zeros(x.shape, np.float32)
    by = np.zeros(x.shape, np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = ix + dx, iy + dy
            h = (cx * 73856093 ^ cy * 19349663) & 511
            sx = (cx + 0.15 + 0.7 * _TAB[0][h]) * cw
            sy = (cy + 0.15 + 0.7 * _TAB[1][h]) * ch
            ddx, ddy = (x - sx) / cw, (y - sy) / ch
            dist = np.sqrt(ddx * ddx + ddy * ddy) * min(cw, ch)
            closer = dist < best
            second = np.where(closer, best, np.minimum(second, dist))
            bx = np.where(closer, ddx, bx)
            by = np.where(closer, ddy, by)
            best = np.where(closer, dist, best)
    return second - best, bx * 2.0, by * 2.0


def main():
    whole = assemble()
    if not os.path.exists(BEFORE):
        os.makedirs(os.path.dirname(BEFORE), exist_ok=True)
        whole.crop((AX0, 0, AX0 + (OLD_EDGE - X0) * 2, H)).save(BEFORE, optimize=True)
    art = np.zeros((H, W, 3), np.uint8)
    art[:] = VOID
    art[:, :(OLD_EDGE - X0) * 2] = np.asarray(Image.open(BEFORE).convert("RGB"))

    # ---- where you can walk, before the 3/4 view: a 4-world-px grid
    G = 4
    gx = X0 + (np.arange(W // (2 * G)) + 0.5) * G
    gy = Y0 + (np.arange(H // (2 * G)) + 0.5) * G
    top, bottom = walls_y(gx)
    floor = (gy[:, None] > top[None, :]) & (gy[:, None] < bottom[None, :])
    sd = upscale(distance(floor, G) - distance(~floor, G), W, H)      # >0 in the mountain

    P = smooth_noise(W, H, 300)
    Q = smooth_noise(W, H, 110)
    R = smooth_noise(W, H, 24, 2)
    B = smooth_noise(W, H, 150, 2)
    sd = sd + 10 * (R - 0.5) + 10 * (Q - 0.5)
    peaks = np.clip((P - 0.32) / 0.36, 0, 1)
    E = 1 + 3.4 * np.clip(sd / 22, 0, 1) + np.clip((sd - 30) / 170, 0, 1) * 4.0 * peaks \
        + 2.2 * np.clip((sd - 20) / 50, 0, 1) * np.clip(B - 0.42, -0.3, 0.3) + 0.6 * (Q - 0.5) * np.clip(sd / 30, 0, 1)
    level = np.where(sd > 0, np.clip(np.floor(E), 1, None), 0).astype(np.uint8)
    del P, E, B
    # tidy the terraces: no one-pixel spikes or pinholes (they'd draw as thin towers)
    im = Image.fromarray(level)
    for flt in (ImageFilter.MaxFilter(7), ImageFilter.MinFilter(7), ImageFilter.MinFilter(7), ImageFilter.MaxFilter(7)):
        im = im.filter(flt)
    level = np.where(sd > 0, np.maximum(np.asarray(im), 1), 0).astype(np.int32)
    z = level * STEP

    # ---- 3/4 view: for each screen pixel, which ground point shows there
    rows = np.arange(H)[:, None]
    topy = rows - z                                        # where each ground point's top is drawn
    sufmin = np.minimum.accumulate(topy[::-1], axis=0)[::-1]
    g = np.empty((H, W), np.int32)
    ys = np.arange(H)
    for c in range(W):
        g[:, c] = np.searchsorted(sufmin[:, c], ys, side="right") - 1
    del sufmin
    cols = np.arange(W)[None, :]
    lv = level[g, cols]                                    # visible terrace level
    f = rows - topy[g, cols]                               # 0 = on top, >0 = down a cliff face
    walk = lv == 0
    wx = X0 + cols / 2.0 + np.zeros((H, 1))
    wy = Y0 + rows / 2.0

    out = art.copy()
    grain = rng.random((H, W)).astype(np.float32)
    tone = smooth_noise(W, H, 80)

    # ---- floor: the desert sand turns into dark red clay going into the ravine
    edge, rx, ry = voronoi(cols + np.zeros((H, 1)), rows + np.zeros((1, W)), 34, 25)
    crack_on = smooth_noise(W, H, 40) > 0.5
    clay = CLAY[np.digitize(tone, [0.36, 0.5, 0.64])].copy()
    clay[(edge < 1.6) & crack_on] = CRACK
    clay[(grain > 0.994)] = CLAY[0]
    clay[(grain < 0.004)] = CLAY[3]
    clay_edge = 3010 + wave(wy, [(22, 37, 0.3), (9, 13, 1.1)])
    clay_t = (wx - clay_edge) / 36.0 + 0.5 + 0.45 * (grain - 0.5) + 0.4 * (R - 0.5)
    is_clay = walk & ((clay_t > 0.5) | (wx >= OLD_EDGE - 16))
    out[is_clay] = clay[is_clay]
    del edge, rx, ry, clay

    # ---- pebbles and small stones on the floor, most of them near the foot of the cliffs
    near_wall = (sd > -40 + 30 * R) & walk
    e3, px, py = voronoi(cols + np.zeros((H, 1)), rows + np.zeros((1, W)), 16, 12)
    lucky = (smooth_noise(W, H, 9, 1) > np.where(near_wall, 0.74, 0.9)) & is_clay
    r2 = px * px + py * py
    stone = lucky & (r2 < 0.35)
    ssh = 0.6 - 0.6 * py - 0.3 * px
    out[stone] = FACE[np.clip(np.digitize(ssh[stone], [0.3, 0.6, 0.9]) + 2, 0, 5)]
    out[lucky & (r2 >= 0.35) & (r2 < 0.5)] = OUT
    del e3, px, py, lucky, r2, stone, ssh, near_wall

    # ---- mountain tops: rocky ground in soft patches, clusters of boulders, tufts of dry grass
    m_top = (~walk) & (f == 0)
    ty, tx = np.nonzero(m_top)
    gyy = g[ty, tx]
    lvl = lv[ty, tx]
    patch = tone[ty, tx] + 0.07 * lvl - 0.12 + 0.1 * (grain[ty, tx] - 0.5)
    ti = np.clip(np.digitize(patch, [0.4, 0.55, 0.72]), 0, 3)
    col = TOP[ti + 1]                                       # flat tones (the darkest is for lines)
    e2, bx, by = voronoi(tx.astype(np.float32), gyy.astype(np.float32), 22, 15)
    near_rim = sd[gyy, tx] < 24 + 8 * R[ty, tx]                  # rocks piled along the edges
    boulders = ((smooth_noise(W, H, 70, 2)[ty, tx] > 0.56) | near_rim) & (by * by + bx * bx * 0.7 < 0.9)
    bsh = 0.62 - 0.45 * by - 0.25 * bx - 0.25 * (bx * bx + by * by) + 0.05 * lvl
    bi = np.clip(np.digitize(bsh, [0.2, 0.45, 0.72, 0.95]), 0, 4)
    bi = np.where(e2 < 1.4, 0, bi)
    col[boulders] = TOP[bi[boulders]]
    tuft = (smooth_noise(W, H, 16, 2)[ty, tx] > 0.66) & ~boulders
    gi = np.clip(np.digitize(grain[ty, tx] * 0.4 + by * -0.2 + 0.4, [0.35, 0.55]), 0, 2)
    col[tuft] = GRASS[gi[tuft]]
    out[ty, tx] = col
    del tx, ty, gyy, lvl, patch, ti, col, e2, bx, by, boulders, bsh, bi, tuft, gi, near_rim

    # ---- cliff faces: stacked rounded ledges, light on top, dark underneath
    m_face = (~walk) & (f > 0)
    fy, fx = np.nonzero(m_face)
    warp = Q[fy, fx] - 0.5
    e2, bx, by = voronoi(fx + 18 * warp, fy + 10 * (R[fy, fx] - 0.5), 28, 13)
    band = ((f[fy, fx] - 1) % STEP) / float(STEP)          # where in this step's ledge
    sh = 0.55 - 0.5 * by - 0.2 * bx - 0.3 * (bx * bx + by * by) + 0.4 * (0.45 - band) \
        + 0.25 * (tone[fy, fx] - 0.5) + 0.1 * (grain[fy, fx] - 0.5)
    fi = np.clip(np.digitize(sh, [0.05, 0.25, 0.45, 0.68, 0.92]), 0, 5)
    fi = np.where(e2 < 1.25, np.where(sh < 0.55, 0, 1), fi)
    fi = np.where(f[fy, fx] <= 2, 5, fi)                   # bright lip right under the rim
    out[fy, fx] = FACE[fi]
    del fy, fx, e2, bx, by, band, sh, fi, warp

    # ---- outlines where a higher terrace meets lower ground (sides, back rims, cliff feet)
    def lower(dy, dx):
        return shifted(lv, dy, dx, 99) < lv
    line = (~walk) & (lower(1, 0) | lower(-1, 0) | lower(0, 1) | lower(0, -1))
    out[line] = OUT
    soft = line & (f == 0) & (shifted(f, 1, 0, 0) == 0) & ~shifted(walk, -1, 0, False) & ~shifted(walk, 1, 0, False)
    out[soft] = TOP[0]                      # between two rock tops: a softer line
    # the rim at the top of a cliff face: brightest
    rim = (~walk) & (f == 0) & (shifted(f, -1, 0, 0) > 0) & ~line
    out[rim] = FACE[5]
    # the far (north) edge of a higher terrace: a lit lip just below its outline
    back = (~walk) & (f == 0) & shifted(line & (shifted(lv, 1, 0, 99) < lv), 1, 0, False)
    out[back & ~line] = TOP[4]
    out[shifted(back, 1, 0, False) & (f == 0) & ~walk & ~line] = TOP[3]

    # ---- a soft shadow on the floor at the foot of the cliffs
    shade = np.zeros((H, W), bool)
    for k in range(1, 6):
        shade |= shifted(~walk, k, 0, False) & (grain > (k - 1) * 0.2)
    shade &= walk
    out[shade] = (out[shade].astype(np.float32) * 0.82).astype(np.uint8)

    # ---- land the camera never sees: left unpainted (east of the old map edge only)
    near = walk[::2 * G, ::2 * G].copy()
    rx_, ry_ = VIEW_HALF[0] // G, VIEW_HALF[1] // G
    a = near
    for _ in range(rx_):
        a = a | shifted(a, 0, 1, False) | shifted(a, 0, -1, False)
    for _ in range(ry_):
        a = a | shifted(a, 1, 0, False) | shifted(a, -1, 0, False)
    seen = np.repeat(np.repeat(a, 2 * G, axis=0), 2 * G, axis=1)[:H, :W]
    unseen = (~seen) & (wx >= OLD_EDGE)
    out[unseen] = VOID

    whole.paste(Image.fromarray(out), (AX0, 0))
    split(whole)
    walls(walk)
    minimap(out, lv, walk, unseen)
    clear_props(walk)
    add_props(walk)
    print("ravine painted")


def walls(walk):
    """data/mountains.json: wall tiles (16 world px) where less than half the tile looks walkable."""
    T = 32
    th, tw = H // T, W // T
    frac = walk[:th * T, :tw * T].reshape(th, T, tw, T).mean(axis=(1, 3))
    rows = ["".join("#" if v < 0.5 else "." for v in r) for r in frac]
    json.dump({"x0": X0 // 16, "y0": Y0 // 16, "rows": rows}, open("data/mountains.json", "w"), indent=0)


def minimap(out, lv, walk, unseen):
    m = Image.open("art/world_map.png").convert("RGBA")
    old = np.asarray(m)
    new_w = (X1 - ORIGIN[0]) // 16
    a = np.zeros((old.shape[0], new_w, 4), np.uint8)
    a[:, :old.shape[1]] = old
    T = 32
    th, tw = H // T, W // T
    tx0 = (X0 - ORIGIN[0]) // 16
    blk = lambda arr: arr[:th * T, :tw * T].reshape(th, T, tw, T, *arr.shape[2:])
    mean_lv = blk(lv.astype(np.float32)).mean(axis=(1, 3))
    walk_f = blk(walk.astype(np.float32)).mean(axis=(1, 3))
    void_f = blk(unseen.astype(np.float32)).mean(axis=(1, 3))
    clay_c = blk(out.astype(np.float32)).mean(axis=(1, 3))
    for ty in range(th):
        for tx in range(tw):
            X = tx0 + tx
            if void_f[ty, tx] > 0.5:
                a[ty, X] = (20, 16, 24, 255)
            elif walk_f[ty, tx] < 0.5:
                l = mean_lv[ty, tx]
                c = (150, 104, 74) if l < 2.5 else (128, 88, 64) if l < 4.5 else (176, 132, 96)
                if (tx + ty) % 2 and l >= 1.5 and l < 2.5:
                    c = (140, 96, 70)
                a[ty, X] = (*c, 255)
            elif X0 + tx * 16 >= 3000 or a[ty, X, 3] == 0:
                r, gg, b = clay_c[ty, tx]
                a[ty, X] = (int(r), int(gg), int(b), 255)
    # the old east border wall column (now open ground or rock)
    Image.fromarray(a).save("art/world_map.png")


def clear_props(walk):
    """Removes desert props and trees that now stand inside the mountain."""
    path = "scenes/main.tscn"
    s = open(path).read()
    blocks = re.split(r"\n(?=\[)", s)
    keep, gone = [], []
    for b in blocks:
        h = re.match(r'\[node name="((?:Desert|TreeN)\d+)" parent="Entities"', b)
        p = re.search(r"\nposition = Vector2\(([-\d.e]+), ([-\d.e]+)\)", b)
        if h and p:
            x, y = float(p.group(1)), float(p.group(2))
            ax, ay = int((x - X0) * 2), int((y - Y0) * 2)
            if 0 <= ax < W and 0 <= ay < H:
                box = walk[max(ay - 12, 0):ay + 4, max(ax - 14, 0):ax + 14]
                if not box.all():
                    gone.append(h.group(1))
                    continue
        keep.append(b)
    open(path, "w").write("\n".join(keep))
    print("removed props:", " ".join(gone) or "none")



def add_props(walk):
    """A few dead trees and bones along the ravine floor (nodes RavineN in scenes/main.tscn)."""
    path = "scenes/main.tscn"
    s = open(path).read()
    s = "\n".join(b for b in re.split(r"\n(?=\[)", s) if not re.match(r'\[node name="Ravine\d+"', b))
    r = np.random.default_rng(SEED + 1)
    placed = [(2960, 300)]
    nodes = ['[node name="Ravine1" parent="Entities" instance=ExtResource("50_decor")]\n'
             'position = Vector2(2985, 214)\nkind = "warn_sign_skull"\n']
    want = ["dead", "dead2", "dead3"] * 3 + ["cave_bones"] * 8
    tries = 0
    while want and tries < 5000:
        tries += 1
        x, y = r.uniform(3150, 4450), r.uniform(100, 420)
        ax, ay = int((x - X0) * 2), int((y - Y0) * 2)
        if not walk[ay - 30:ay + 12, ax - 30:ax + 30].all():
            continue
        if any((x - a) ** 2 + (y - b) ** 2 < 110 ** 2 for a, b in placed):
            continue
        if abs(y - ROAD_Y) < 24:
            continue                                   # keep the middle of the way clear
        kind = want.pop()
        placed.append((x, y))
        n = len(nodes) + 1
        res = "50_decor" if kind == "cave_bones" else "4_tree"
        nodes.append('[node name="Ravine%d" parent="Entities" instance=ExtResource("%s")]\n'
                     'position = Vector2(%d, %d)\nkind = "%s"\n' % (n, res, x, y, kind))
    open(path, "w").write(s.rstrip("\n") + "\n\n" + "\n".join(nodes))


if __name__ == "__main__":
    main()
