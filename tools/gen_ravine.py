"""Paints the east mountains and the red-clay ravine (a pass through the mountains), the wide
grey rocky valley it opens into (with rock outcrops scattered over it), and writes the walls
(data/mountains.json), the minimap and the props.

    python3 tools/gen_ravine.py

How it works (plain version):
  - Two curved lines (FUNNEL / RAVINE settings below) mark where you can walk: they start in the
    desert, bend toward the road, run east side by side as the ravine, then open out
    into a wide valley that runs to the map's east edge (VALLEY_TOP / VALLEY_BOTTOM).
    Everything outside them is mountain; OUTCROPS are islands of mountain inside the valley.
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
X0, X1 = 2400, 6512          # world x: the mountains start at X0; X1 is the map's east edge
XM = X1                      # world x where the mountain work ends (the map's east edge)
Y0, Y1 = -992, 1696          # world y (the whole height of the map)
OLD_EDGE = 3120              # the old east edge of the map
ROAD_Y = 256                 # middle of the east-west road
FUNNEL_TOP_X = 2500          # where the north mountain line leaves the top of the map
FUNNEL_BOTTOM_X = 2520       # where the south mountain line leaves the bottom of the map
RAVINE_X = 3060              # where the funnel has narrowed into the ravine
RAVINE_END = 4470            # the ravine starts opening out again here (east funnel)
# the east valley past the ravine: where its walls are drawn (world x, world y of the visible
# edge), traced from Rex's sketch; the walls bend smoothly through these points
VALLEY_TOP = [(4726, 65), (5100, -55), (5566, -163), (6024, -213), (6600, -171)]
VALLEY_BOTTOM = [(4601, 468), (5026, 605), (5500, 668), (5982, 696), (6600, 522)]
VALLEY_FROM = 4470           # the ravine starts widening into the valley here
VALLEY_WIGGLE = 55           # world px the valley walls wander (random bends)
GREY_FROM = 4760             # world x where the red clay turns into grey cracked ground
# rock outcrops in the valley ("mountains" for trolls): world centre and the size Rex drew them
# (visible width, height, world px). Their cliff faces are drawn like the ravine's.
OUTCROPS = [(5138, 231, 145, 166), (5408, 285, 75, 58), (5932, 148, 208, 145), (5845, 451, 160, 150),
            (5616, -34, 100, 104), (6423, 7, 83, 120), (5290, 520, 120, 110), (6230, 330, 130, 120),
            (6350, 600, 95, 90), (5000, 405, 70, 60)]
OUTCROP_MAX_LEVEL = 2        # outcrops stay low (one or two ledges), not full mountains
BEFORE = "art/ground_src/east_before_ravine.png"   # the desert as it was (each run starts from it)
STEP = 64                    # (old fixed step; heights are now LEVEL_Z)
# how high each terrace is drawn, in art px: one tall cliff first, then smaller steps behind it
LEVEL_Z = np.array([0, 120, 196, 256, 316, 372, 428, 484, 540, 596, 652], np.int32)
WIGGLE = 110                 # world px the funnel's mountain lines wander (random bends)
VIEW_HALF = (180, 110)       # world px the camera can see around the player (plus a margin)

# colours, picked from Rex's reference pictures (flat shading, no speckle)
ROCK = {
    "crack": (52, 45, 40),        # gaps between blocks, outlines
    "dark": (84, 69, 57),         # shaded sides (right / underneath)
    "body": (108, 92, 78),        # front of a block
    "body2": (98, 83, 69),        # a slightly darker block, for variety
    "body_hi": (121, 105, 90),    # a block standing out a little
    "light": (141, 127, 113),     # upward-facing planes
    "shine": (164, 150, 135),     # the brightest edge
    "top": (152, 139, 121),       # flat mountain top
    "top2": (160, 149, 132),
    "top_shadow": (128, 115, 99),
    "top_crack": (112, 99, 85),
    "rim": (170, 160, 144),
}
CLAY = np.array([(96, 44, 34), (112, 54, 41), (128, 64, 47), (146, 78, 56)], np.uint8)
CRACK = (78, 36, 29)
CLAY_FROM = 2560             # world x where the sand turns to clay (the funnel into the ravine)
GREY = np.array([(88, 90, 95), (99, 101, 106), (110, 112, 117), (122, 124, 128)], np.uint8)
GREY_CRACK = (66, 68, 74)

rng = np.random.default_rng(SEED)
W, H = (XM - X0) * 2, (Y1 - Y0) * 2          # art size of the mountain part
AX0 = (X0 - ORIGIN[0]) * 2                    # its art x in the whole painting


OLD_W = (4720 - X0) * 2      # art width the mountains had when the ravine was a dead end
_rng_ext = np.random.default_rng(SEED + 9)
SPLIT = True                 # keep the old part's random shapes exactly (see smooth_noise)


def smooth_noise(w, h, cell, octaves=3):
    """Blobby noise 0..1. The part of the picture that existed before the map grew east
    (OLD_W) gets exactly the random numbers it always had, so the west funnel and the
    ravine keep their shapes; the new east part gets its own, faded in over a short overlap."""
    w_old = round(w * OLD_W / W)
    if not SPLIT or w_old >= w:
        return _smooth_noise(w, h, cell, octaves, rng)
    a = _smooth_noise(w_old, h, cell, octaves, rng)
    out = _smooth_noise(w, h, cell, octaves, _rng_ext)
    ov = max(w_old // 16, 4)
    t = np.clip((np.arange(w_old) - (w_old - ov)) / ov, 0.0, 1.0).astype(np.float32)[None, :]
    out[:, :w_old] = a * (1 - t) + out[:, :w_old] * t
    return out


def split_random(h, w):
    """rng.random((h, w)) with the same old-part / new-part split as smooth_noise."""
    w_old = min(OLD_W, w)
    a = rng.random((h, w_old)).astype(np.float32)
    if w_old >= w:
        return a
    return np.concatenate([a, _rng_ext.random((h, w - w_old), dtype=np.float32)], axis=1)


def _smooth_noise(w, h, cell, octaves, rng):
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
    top = mid - half
    bottom = mid + half + 88           # the south wall's rim leans north over its foot
    # the funnel: the lines come down from the top / up from the bottom of the map
    t = np.clip((wx - FUNNEL_TOP_X) / (RAVINE_X - FUNNEL_TOP_X), 0.0, 1.0)
    top = np.where(wx < FUNNEL_TOP_X, -1e5, top - (top - (Y0 - 60)) * (1 - t) ** 2)
    t = np.clip((wx - FUNNEL_BOTTOM_X) / (RAVINE_X - FUNNEL_BOTTOM_X), 0.0, 1.0)
    bottom = np.where(wx < FUNNEL_BOTTOM_X, 1e5, bottom + ((Y1 + 60) - bottom) * (1 - t) ** 2)
    # ...and at the east end the ravine widens into the valley, whose walls follow Rex's sketch
    # (the south wall's foot sits 88 px further south, like the ravine's, so its drawn rim lands
    # on the line)
    k = np.clip((wx - VALLEY_FROM) / 330.0, 0.0, 1.0)
    k = k * k * (3 - 2 * k)
    top = top * (1 - k) + _valley(VALLEY_TOP, wx) * k
    bottom = bottom * (1 - k) + (_valley(VALLEY_BOTTOM, wx) + 88) * k
    return top, bottom


def _valley(points, wx):
    """A smooth curve through (x, y) points (flat beyond the ends), starting from the ravine."""
    from scipy.interpolate import PchipInterpolator
    xs = [VALLEY_FROM] + [p[0] for p in points]
    ys = [None] + [p[1] for p in points]
    ys[0] = ys[1]                                          # (blended in from the ravine anyway)
    f = PchipInterpolator(xs, ys, extrapolate=False)
    out = f(np.clip(wx, xs[0], xs[-1]))
    return np.nan_to_num(out, nan=ys[-1])


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
    """Same as _voronoi, done in pieces so big pictures fit in memory."""
    shape = np.broadcast_shapes(np.shape(x), np.shape(y))
    if len(shape) == 2:                       # a whole picture: go a band of rows at a time
        outs, seeds = [], []
        for i in range(0, shape[0], 256):
            xs = np.broadcast_to(x, shape)[i:i + 256].astype(np.float32)
            ys = np.broadcast_to(y, shape)[i:i + 256].astype(np.float32)
            outs.append(_voronoi(xs, ys, cw, ch))
            seeds.append(_voronoi.seeds)
        voronoi.seeds = np.concatenate(seeds)
        return tuple(np.concatenate([o[k] for o in outs]) for k in range(3))
    n = shape[0]
    if n <= 2_000_000:
        r = _voronoi(x, y, cw, ch)
        voronoi.seeds = _voronoi.seeds
        return r
    outs, seeds = [], []
    for i in range(0, n, 2_000_000):
        outs.append(_voronoi(x[i:i + 2_000_000], y[i:i + 2_000_000], cw, ch))
        seeds.append(_voronoi.seeds)
    voronoi.seeds = np.concatenate(seeds)
    return tuple(np.concatenate([o[k] for o in outs]) for k in range(3))


def _voronoi(x, y, cw, ch):
    """Rock chunks: for points (x, y) in art px, returns (edge, rx, ry): edge = how far from the
    border with the next chunk (px), rx / ry = position inside its own chunk (-1..1)."""
    gx, gy = x / cw, y / ch
    ix, iy = np.floor(gx).astype(np.int64), np.floor(gy).astype(np.int64)
    best = np.full(x.shape, 1e9, np.float32)
    second = np.full(x.shape, 1e9, np.float32)
    bx = np.zeros(x.shape, np.float32)
    by = np.zeros(x.shape, np.float32)
    seeds = np.zeros(x.shape + (2,), np.float32)
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
            seeds = np.where(closer[..., None], np.stack([sx, sy], axis=-1), seeds)
            bx = np.where(closer, ddx, bx)
            by = np.where(closer, ddy, by)
            best = np.where(closer, dist, best)
    _voronoi.seeds = seeds
    return second - best, bx * 2.0, by * 2.0


def h01(a, b, salt):
    """Repeatable random number 0..1 for integer arrays a, b."""
    n = (a.astype(np.int64) * 73856093) ^ (b.astype(np.int64) * 19349663) ^ (salt * 83492791 + SEED)
    n = (n ^ (n >> 13)) * 1274126177
    return ((n >> 8) & 0xffff) / 65535.0


def boulder_colours(bx, by, edge):
    """Chunky boulder like the reference: light top plane, mid front, dark right side, dark rim.
    bx, by: position inside the boulder (-1..1); edge: distance to the next boulder (px)."""
    c = np.empty(bx.shape + (3,), np.uint8)
    c[:] = ROCK["body"]
    c[by < -0.1 + 0.15 * bx] = ROCK["light"]
    c[(by < -0.45) & (bx < -0.1)] = ROCK["shine"]
    c[(bx > 0.35) & (by >= -0.2)] = ROCK["dark"]
    c[(by > 0.6)] = ROCK["dark"]
    c[edge < 2.0] = ROCK["crack"]
    return c


def cliff_blocks(x, v, hh, key):
    """Colours for cliff-face pixels, after the reference cliffs: tall rock pillars of very
    different widths that run the height of the cliff, shaded round (lit left, dark right, darker
    low down), with rounded tops at different heights, deep gaps between them, and the odd
    crack down or across a pillar.
    x: screen column, v: px below the top of this tier of cliff, hh: the tier's height,
    key: which tier (so each tier gets its own pillars)."""
    # pillar edges wobble a little so they aren't ruler-straight
    xw = x + np.round(1.2 * np.sin(v / 13.0 + h01(x // 64, key, 12) * 6.3)).astype(np.int64)
    cw = 30
    c0 = xw // cw
    jit = lambda c: c * cw + ((h01(c, key, 2) - 0.5) * 0.8 * cw).astype(np.int64)
    col = np.where(xw < jit(c0), c0 - 1, c0)
    col = np.where(xw >= jit(col + 1), col + 1, col)
    # now and then two neighbours are one wide pillar
    merge = h01(col, key, 13) < 0.3
    left = np.where(h01(col - 1, key, 13) < 0.3, jit(col - 1), jit(col))
    right = np.where(merge, jit(col + 2), jit(col + 1))
    u, w = xw - left, np.maximum(right - left, 4)
    pid = left                                               # one id per pillar
    a, b, d = h01(pid, key, 3), h01(pid, key, 8), h01(pid, key, 9)
    # the pillar's own top: some reach the rim, others stop lower down
    o = np.where(a < 0.35, 0, (b * hh * 0.45).astype(np.int64))
    t = v - o
    r = np.minimum(np.maximum(w // 3, 3), 9)
    cx = np.where(u < r, r - u, np.where(u > w - 1 - r, u - (w - 1 - r), 0))
    cy = np.where(t < r, r - t, 0)
    behind = (t < 0) | ((cx * cx + cy * cy) > r * r)
    # round shading across the pillar: 0 dark .. 5 shine
    fr = u / w
    tone = np.select([fr < 0.16, fr < 0.42, fr < 0.7, fr < 0.88], [4, 3, 2, 1], 0)
    tone = tone + np.where(d > 0.7, 1, 0) - np.where(d < 0.25, 1, 0)         # standing out / set back
    tone = tone - (v > hh * 0.62) - (v > hh * 0.85)                          # darker low down
    # a crack across some pillars: the part below starts again with a lit top
    s1 = o + 16 + (h01(pid, key, 4) * (hh - o) * 0.6).astype(np.int64)
    across = (h01(pid, key, 7) < 0.35) & (v >= s1) & (s1 < hh - 12)
    tb = np.where(across, v - s1, t)
    tone = np.where(tb <= 2, np.maximum(tone, 4), tone)
    tone = np.where((tb == 0) & (fr < 0.6), 5, tone)
    tone = np.clip(tone, 0, 5)
    pal = np.array([ROCK["dark"], ROCK["body2"], ROCK["body"], ROCK["body_hi"], ROCK["light"], ROCK["shine"]], np.uint8)
    c = pal[tone]
    # a crack down some of the wider pillars (dark, with a lit edge on its right)
    sx = 4 + (h01(pid, key, 10) * np.maximum(w - 10, 1)).astype(np.int64)
    st = (h01(pid, key, 11) * hh * 0.5).astype(np.int64)
    down = (w > 18) & (h01(pid, key, 14) < 0.6) & (t > st) & (v < hh - 2)
    c[down & (u == sx)] = ROCK["crack"]
    c[down & (u == sx + 1)] = ROCK["body_hi"]
    c[across & (tb == 0) & (fr >= 0.6)] = ROCK["crack"]
    c[across & (v == s1 - 1)] = ROCK["crack"]
    # gaps between pillars: dark, wider where a pillar is set back
    gw = (h01(pid, key, 15) * 3.2).astype(np.int64)                      # 0..3 extra px of gap
    gap = (u == 0) | (u <= gw) & (d < 0.5) | ((u >= w - 1) & (a > 0.5))
    c[(u == gw + 1) & (gw > 0) & (d < 0.5) & ~behind] = ROCK["dark"]      # shadow inside a deep gap
    c[gap & ~behind] = ROCK["crack"]
    c[behind] = ROCK["dark"]
    c[behind & ((cx * cx + cy * cy) <= (r + 1.5) ** 2) & (t >= -1)] = ROCK["crack"]    # outline of the rounded top
    c[v >= hh - 1] = ROCK["crack"]                                                       # foot of the tier
    return c


SAND = np.array([(220, 188, 133), (233, 207, 155), (242, 223, 179)], np.uint8)   # same as the west desert
SAND_DEEP = (209, 174, 120)
SAND_SPECKS = [((192, 154, 108), 0.010), ((250, 236, 200), 0.004), ((214, 128, 84), 0.0012), ((150, 118, 84), 0.0015)]


def desert(w, h, wx0):
    """Sand like tools/gen_desert.py (flat tones, soft dunes, specks) for an area w x h art px
    whose left edge is at world x wx0. Uses its own random numbers, so the mountains come out
    the same as before."""
    global rng, SPLIT
    keep, rng = rng, np.random.default_rng(SEED + 5)
    SPLIT = False
    world_x = wx0 + np.arange(w)[None, :] / 2.0
    world_y = Y0 + np.arange(h)[:, None] / 2.0
    sand = SAND[np.digitize(smooth_noise(w, h, 90, 3), [0.44, 0.58])]
    warp = smooth_noise(w, h, 260, 2)
    ridge = np.sin((world_y + warp * 140.0 + np.sin(world_x / 130.0) * 24.0) / 21.0)
    del warp
    dune_zone = smooth_noise(w, h, 300, 2) > 0.58
    sand[dune_zone & (ridge < -0.62) & (ridge > -0.78)] = SAND_DEEP
    sand[dune_zone & (ridge > 0.96)] = SAND[2]
    del ridge, dune_zone
    spk = rng.random((h, w), dtype=np.float32)
    acc = 0.0
    for col, p in SAND_SPECKS:
        sand[(spk >= acc) & (spk < acc + p)] = col
        acc += p
    rng = keep
    SPLIT = True
    return sand



def main():
    whole = assemble()
    if not os.path.exists(BEFORE):
        os.makedirs(os.path.dirname(BEFORE), exist_ok=True)
        whole.crop((AX0, 0, AX0 + (OLD_EDGE - X0) * 2, H)).save(BEFORE, optimize=True)
    out = np.zeros((H, W, 3), np.uint8)
    out[:] = VOID
    out[:, :(OLD_EDGE - X0) * 2] = np.asarray(Image.open(BEFORE).convert("RGB"))

    # ---- where you can walk, before the 3/4 view: a 4-world-px grid
    G = 4
    gx = X0 + (np.arange(W // (2 * G)) + 0.5) * G
    gy = Y0 + (np.arange(H // (2 * G)) + 0.5) * G
    # bend the lines at random (strongly in the funnel, gently along the ravine so it stays open)
    gh_, gw_ = len(gy), len(gx)
    amp = np.interp(gx, [2950, 3150, RAVINE_END - 90, RAVINE_END + 110],
                    [WIGGLE, WIGGLE * 0.25, WIGGLE * 0.25, VALLEY_WIGGLE])[None, :]
    wx_ = gx[None, :] + (smooth_noise(gw_, gh_, 70, 3) - 0.5) * 2 * amp
    wy_ = gy[:, None] + (smooth_noise(gw_, gh_, 70, 3) - 0.5) * 2 * amp
    top, bottom = walls_y(wx_)
    floor = (wy_ > top) & (wy_ < bottom)
    del wx_
    # outcrops: islands of rock in the valley. Footprint = the drawn size minus the part the 3/4
    # view lifts up the screen; edges made lumpy with noise so they aren't plain ovals. (Own
    # random numbers, so everything else comes out as it always did.)
    lump = _smooth_noise(gw_, gh_, 14, 2, np.random.default_rng(SEED + 11))
    crop = np.zeros_like(floor)
    crop_cap = np.zeros(floor.shape, np.uint8)            # how many ledges each outcrop may have
    for cx, cy, vw, vh in OUTCROPS:
        lift = 60 if vh < 100 else 98                     # small ones: one ledge; big ones: two
        fh = max(vh * 0.95 - lift + 20, 34)
        fw = vw * 1.1
        fcy = cy + vh / 2 - fh / 2                         # foot of the drawing = foot of the rock
        e = ((gx[None, :] - cx) / (fw / 2)) ** 2 + ((gy[:, None] - fcy) / (fh / 2)) ** 2
        here = e < 0.55 + 0.9 * lump
        crop |= here
        crop_cap[here] = 1 if vh < 100 else OUTCROP_MAX_LEVEL
    del lump
    floor &= ~crop
    grow = lambda a: np.asarray(Image.fromarray(a).resize((W, H), Image.NEAREST).filter(ImageFilter.MaxFilter(9)))
    crop_art = grow(crop_cap)
    sd = np.array(upscale(distance(floor, G) - distance(~floor, G), W, H))      # >0 in the mountain

    # all the random patterns for the whole picture, in the order they were always made (so the
    # old part keeps its exact shapes); kept small (float16) and painted in strips below
    f16 = lambda a: a             # (kept full precision: the old part then matches exactly)
    P = f16(smooth_noise(W, H, 300))
    Q = f16(smooth_noise(W, H, 110))
    R = f16(smooth_noise(W, H, 24, 2))
    B = f16(smooth_noise(W, H, 150, 2))
    for r0 in range(0, H, 512):
        sd[r0:r0 + 512] += 10 * (R[r0:r0 + 512].astype(np.float32) - 0.5) + 10 * (Q[r0:r0 + 512].astype(np.float32) - 0.5)
    level = np.zeros((H, W), np.uint8)
    for r0 in range(0, H, 512):
        b = slice(r0, r0 + 512)
        sdb, Pb, Bb, Qb = sd[b], P[b].astype(np.float32), B[b].astype(np.float32), Q[b].astype(np.float32)
        peaks = np.clip((Pb - 0.32) / 0.36, 0, 1)
        E = 1 + 1.4 * np.clip(sdb / 26, 0, 1) + np.clip((sdb - 60) / 200, 0, 1) * 2.6 * peaks \
            + 1.6 * np.clip((sdb - 40) / 60, 0, 1) * np.clip(Bb - 0.42, -0.3, 0.3) + 0.4 * (Qb - 0.5) * np.clip(sdb / 30, 0, 1)
        level[b] = np.where(sdb > 0, np.clip(np.floor(E), 1, None), 0)
    del P, B, E, peaks
    # tidy the terraces: no one-pixel spikes or pinholes (they'd draw as thin towers)
    im = Image.fromarray(level)
    for flt in (ImageFilter.MaxFilter(11), ImageFilter.MinFilter(11), ImageFilter.MinFilter(11), ImageFilter.MaxFilter(11)):
        im = im.filter(flt)
    level = np.where(sd > 0, np.maximum(np.asarray(im), 1), 0).astype(np.uint8)
    del im
    level = np.where(crop_art > 0, np.minimum(level, crop_art), level).astype(np.uint8)
    del crop_art

    grain = split_random(H, W)
    tone = f16(smooth_noise(W, H, 80))
    crack_on = smooth_noise(W, H, 40) > 0.5
    stone_n = f16(smooth_noise(W, H, 9, 1))
    clump = f16(smooth_noise(W, H, 110, 2))
    noise = dict(sd=sd, Q=Q, R=R, grain=grain, tone=tone, crack_on=crack_on, stone_n=stone_n, clump=clump)

    walk = np.zeros((H, W), bool)
    lv_all = np.zeros((H, W), np.uint8)
    STRIP, M = 1024, 16
    for c0 in range(0, W, STRIP):
        c1 = min(c0 + STRIP, W)
        a, b = max(c0 - M, 0), min(c1 + M, W)
        o, wk, lvs = paint_strip(a, b, level, out[:, a:b].copy(), noise)
        out[:, c0:c1] = o[:, c0 - a:c1 - a]
        walk[:, c0:c1] = wk[:, c0 - a:c1 - a]
        lv_all[:, c0:c1] = lvs[:, c0 - a:c1 - a]
        print("strip", c0, "/", W, flush=True)
    del noise, sd, Q, R, grain, tone, crack_on, stone_n, clump, level

    # ---- land the camera never sees: left unpainted (east of the old map edge only)
    near = walk[::2 * G, ::2 * G].copy()
    rx_, ry_ = VIEW_HALF[0] // G, VIEW_HALF[1] // G
    a = near
    for _ in range(rx_):
        a = a | shifted(a, 0, 1, False) | shifted(a, 0, -1, False)
    for _ in range(ry_):
        a = a | shifted(a, 1, 0, False) | shifted(a, -1, 0, False)
    seen = np.repeat(np.repeat(a, 2 * G, axis=0), 2 * G, axis=1)[:H, :W]
    unseen = (~seen) & ((X0 + np.arange(W) / 2.0)[None, :] >= OLD_EDGE)
    del seen
    out[unseen] = VOID

    whole.paste(Image.fromarray(out), (AX0, 0))
    split(whole)
    del whole
    walls(walk)
    minimap(out, lv_all, walk, unseen)
    clear_props(walk)
    add_props(walk)
    print("ravine painted")


def paint_strip(a, b, level_all, out, n):
    """Paints art columns a..b (global art columns; the caller keeps the middle and drops a small
    margin at each side). Returns (colours, walkable, visible terrace level) for the strip."""
    level = level_all[:, a:b].astype(np.int32)
    Wn = b - a
    z = LEVEL_Z[level]
    sl = (slice(None), slice(a, b))
    sd, Q, R = n["sd"][sl], n["Q"][sl].astype(np.float32), n["R"][sl].astype(np.float32)
    grain, tone = n["grain"][sl], n["tone"][sl].astype(np.float32)

    # ---- 3/4 view: for each screen pixel, which ground point shows there
    rows = np.arange(H, dtype=np.int32)[:, None]
    topy = rows - z                                        # where each ground point's top is drawn
    sufmin = np.minimum.accumulate(topy[::-1], axis=0)[::-1]
    g = np.empty((H, Wn), np.int32)
    ys = np.arange(H)
    for c in range(Wn):
        g[:, c] = np.searchsorted(sufmin[:, c], ys, side="right") - 1
    del sufmin
    lc = np.arange(Wn)[None, :]
    cols = lc + a                                          # global art columns
    lv = level[g, lc]                                      # visible terrace level
    f = rows - topy[g, lc]                                 # 0 = on top, >0 = down a cliff face
    del topy
    walk = lv == 0
    wx = (X0 + cols / 2.0).astype(np.float32) + np.zeros((H, 1), np.float32)
    wy = (Y0 + rows / 2.0).astype(np.float32)

    # ---- floor: the grass turns into dark red clay going into the ravine, then grey
    edge, _, _ = voronoi(cols, rows, 34, 25)
    crack_on = n["crack_on"][sl]
    clay = CLAY[np.digitize(tone, [0.36, 0.5, 0.64])].copy()
    clay[(edge < 1.6) & crack_on] = CRACK
    clay[(grain > 0.994)] = CLAY[0]
    clay[(grain < 0.004)] = CLAY[3]
    clay_edge = np.float32(CLAY_FROM) + wave(wy, [(30, 160, 2.0), (12, 71, 0.4)]).astype(np.float32) + 70 * (Q - 0.5)
    clay_t = (wx - clay_edge) / 90.0 + 0.5 + 0.22 * (grain - 0.5) + 1.1 * (R - 0.5)    # grass -> clay: wide, blotchy
    is_west = (clay_t > 0.5) | (wx >= OLD_EDGE - 16)
    del clay_edge, clay_t
    grey_edge = np.float32(GREY_FROM) + wave(wy, [(30, 150, 0.7), (12, 67, 2.4)]).astype(np.float32) + 70 * (Q - 0.5)
    grey_t = (wx - grey_edge) / 90.0 + 0.5 + 0.22 * (grain - 0.5) + 1.1 * (R - 0.5)    # a wide, blotchy blend
    is_grey = walk & is_west & (grey_t > 0.5)
    is_clay = walk & is_west & ~is_grey
    del grey_edge, grey_t, is_west
    out[is_clay] = clay[is_clay]
    # the valley: the same cracked ground, in grey
    clay[:] = GREY[np.digitize(tone, [0.36, 0.5, 0.64])]
    clay[(edge < 1.6) & crack_on] = GREY_CRACK
    clay[(grain > 0.994)] = GREY[0]
    clay[(grain < 0.004)] = GREY[3]
    out[is_grey] = clay[is_grey]
    is_clay |= is_grey                                       # (stones go on both)
    del edge, clay

    # ---- small stones on the clay, mostly near the foot of the cliffs (like the boulders, smaller)
    near_wall = (sd > -40 + 30 * R) & walk
    _, px, py = voronoi(cols, rows, 18, 14)
    lucky = (n["stone_n"][sl].astype(np.float32) > np.where(near_wall, 0.76, 0.92)) & is_clay
    lucky &= ~is_grey | near_wall                            # on the grey ground only by the cliffs
    sz = np.maximum(np.abs(px) * 0.9, np.abs(py))
    stone = lucky & (sz < 0.6)
    out[stone] = boulder_colours(px[stone] / 0.6, py[stone] / 0.6, np.where(sz[stone] > 0.5, 0.0, 9.0))
    del px, py, lucky, stone, near_wall, sz, is_clay, is_grey

    # ---- mountain tops: flat pale rock, a few lumps, and chunky boulders piled along the edges
    m_top = (~walk) & (f == 0)
    ty, tx = np.nonzero(m_top)
    gyy = g[ty, tx]
    txg = tx + a
    col = np.where((tone[ty, tx] > 0.6)[:, None], ROCK["top2"], ROCK["top"]).astype(np.uint8)
    # the same dried-mud cracks as the ravine floor, in the rock's own colours
    ce, _, _ = voronoi(txg.astype(np.float32), gyy.astype(np.float32), 34, 25)
    cracked = (ce < 1.6) & (n["crack_on"][gyy, txg])
    col[cracked] = ROCK["top_crack"]
    del ce, cracked
    e2, bx, by = voronoi(txg.astype(np.float32), gyy.astype(np.float32), 34, 26)
    sx = np.clip(voronoi.seeds[:, 0].astype(np.int64), 0, W - 1)
    sy = np.clip(voronoi.seeds[:, 1].astype(np.int64), 0, H - 1)
    # a whole rock where its middle is near an edge or inside a clump (so rocks are never cut)
    # rocks piled on the edge only where the edge faces the ravine from the south (seen from
    # above); on top of a cliff face the pillars' own rounded tops are the edge
    floor_above = np.zeros(len(ty), bool)
    for k in range(4, 200, 6):
        floor_above |= walk[np.maximum(ty - k, 0), tx]
    boulder = ((n["sd"][sy, sx] < 30) & floor_above) | (n["clump"][sy, sx].astype(np.float32) > 0.68)
    col[boulder] = boulder_colours(bx[boulder], by[boulder], e2[boulder])
    out[ty, tx] = col
    del ty, tx, txg, gyy, col, e2, bx, by, sx, sy, boulder

    # ---- cliff faces: stacked blocks in columns, like the reference cliff
    m_face = (~walk) & (f > 0)
    fy, fx = np.nonzero(m_face)
    L = lv[fy, fx]
    zat = LEVEL_Z[L] - f[fy, fx]                           # height on the cliff of this pixel
    m = np.clip(np.searchsorted(LEVEL_Z, zat, side="left"), 1, len(LEVEL_Z) - 1)   # which tier
    for i in range(0, len(fy), 2_000_000):
        j = slice(i, i + 2_000_000)
        mm = m[j].astype(np.int64)
        out[fy[j], fx[j]] = cliff_blocks((fx[j] + a).astype(np.int64), (LEVEL_Z[mm] - zat[j]).astype(np.int64),
                                         (LEVEL_Z[mm] - LEVEL_Z[mm - 1]).astype(np.int64), mm + L[j].astype(np.int64) * 16)
    del L, zat, m, fy, fx

    # ---- dark cracks where a higher terrace meets lower ground (sides, back edges, cliff feet)
    def lower(dy, dx):
        return shifted(lv, dy, dx, 99) < lv
    line = (~walk) & (lower(1, 0) | lower(-1, 0) | lower(0, 1) | lower(0, -1))
    out[line] = ROCK["crack"]
    soft = line & (f == 0) & (shifted(f, 1, 0, 0) == 0) & ~shifted(walk, -1, 0, False) & ~shifted(walk, 1, 0, False)
    out[soft] = np.where((tone[soft] > 0.6)[:, None], ROCK["top2"], ROCK["top"])   # no line between two rock tops
    # the far (north) edge of a higher terrace: a pale lip just below the line
    back = (~walk) & (f == 0) & shifted(line & (shifted(lv, 1, 0, 99) < lv), 1, 0, False) & ~line
    out[back] = ROCK["rim"]

    # ---- shadow on the floor at the foot of the cliffs (solid, 3 world px)
    shade = np.zeros((H, Wn), bool)
    for k in range(1, 7):
        shade |= shifted(~walk, k, 0, False)
    shade &= walk
    out[shade] = (out[shade].astype(np.float32) * 0.8).astype(np.uint8)
    return out, walk, lv.astype(np.uint8)


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
                c = (140, 127, 110) if l < 2.5 else (120, 105, 90) if l < 4.5 else (156, 144, 126)
                if (tx + ty) % 2 and l >= 1.5 and l < 2.5:
                    c = (132, 118, 102)
                a[ty, X] = (*c, 255)
            elif X0 + tx * 16 >= CLAY_FROM - 60 or a[ty, X, 3] == 0:
                r, gg, b = clay_c[ty, tx]
                a[ty, X] = (int(r), int(gg), int(b), 255)
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
    # the east desert's cacti are gone; the valley gets dead trees, rocks and bones instead
    s = "\n".join(b for b in re.split(r"\n(?=\[)", s) if not re.match(r'\[node name="(DesertE|Valley)\d+"', b))
    kinds = ["dead", "dead2", "dead3"] * 3 + ["cave_rock1", "cave_rock2"] * 5 + ["cave_bones"] * 6
    spots = []
    tries = 0
    while kinds and tries < 20000:
        tries += 1
        x, y = r.uniform(4750, X1 - 40), r.uniform(-260, 760)
        ax, ay = int((x - X0) * 2), int((y - Y0) * 2)
        if ax + 30 >= W or not walk[max(ay - 40, 0):ay + 12, max(ax - 30, 0):ax + 30].all():
            continue
        if abs(y - ROAD_Y) < 40 and x < 5000:
            continue                                   # keep the way out of the ravine clear
        if any((x - a) ** 2 + (y - b) ** 2 < 120 ** 2 for a, b, _ in spots):
            continue
        spots.append((x, y, kinds.pop()))
    for i, (x, y, kind) in enumerate(spots):
        res = "4_tree" if kind.startswith("dead") else "50_decor"
        nodes.append('[node name="Valley%d" parent="Entities" instance=ExtResource("%s")]\n'
                     'position = Vector2(%d, %d)\nkind = "%s"\n' % (i + 1, res, x, y, kind))
    open(path, "w").write(s.rstrip("\n") + "\n\n" + "\n".join(nodes))


if __name__ == "__main__":
    main()
