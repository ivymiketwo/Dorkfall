"""Repaints the village ground (October 2026): the cobblestone streets are taken out and grass grown
back in their place, then winding dirt lanes are painted between the buildings, with rounded
"desire path" corners (worn corners with wagon-wheel ruts) wherever two roads meet at a right angle.

It always starts from art/ground_src/village_before_roads.png (the six ground squares g_2..4_1..2 as
they were, cobblestones and all), so change the LANES / CORNERS below and run it again:

    python3 tools/paint_village_roads.py            (about 20 seconds)

What it does, in order:
  1. Cobblestones: every grey pixel inside the old street boxes is replaced by grass. The three
     grass shades are grown in from the grass around the hole (so the big light / dark patches carry
     on smoothly), with the same little specks and grass tufts as the rest of the meadow.
  2. Lanes: each lane is a smooth curve through its points, LANE_W wide, with slightly wobbly edges.
     The two old dirt roads (north-south through the village, east-west south of it) are kept as
     they were; new dirt is only painted where there wasn't any.
  3. Corners: at every CORNERS entry the inside of the corner is filled in with a rounded curve of dirt,
     and two wheel ruts follow the curve.
  4. Edges: the dirt gets the same edge as the old roads (two lines of darker dirt, then a dark green
     rim on the grass side).

The house positions this was drawn for are in scenes/main.tscn; the minimap is updated by the
same run (the lanes are added to it; building blocks there are drawn by hand).
"""
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "art/ground_src/village_before_roads.png"
SQUARES = [(c, r) for r in (1, 2) for c in (2, 3, 4)]       # ground squares g_c_r in the canvas
CANVAS_WORLD = (-656, -480)                                 # world position of the canvas's corner
MINIMAP = "art/world_map.png"
MINIMAP_ORIGIN = (-105, -62)                                # tile of the minimap's top-left pixel

# --- palette (taken from the existing ground) ---
GRASS = np.array([(86, 152, 79), (110, 175, 88), (134, 194, 98)])
GRASS_SPECKS = [   # per grass shade: (colour, chance)
    [((63, 125, 76), 0.020), ((125, 186, 92), 0.015), ((102, 164, 82), 0.004)],
    [((63, 125, 76), 0.004), ((125, 186, 92), 0.007), ((151, 204, 102), 0.005), ((164, 212, 114), 0.002)],
    [((125, 186, 92), 0.040), ((102, 164, 82), 0.020), ((164, 212, 114), 0.014), ((151, 204, 102), 0.006)],
]
TUFT_COLOUR = (63, 125, 76)
TUFT = ["#...#", "#.#.#", ".###."]                         # a grass tuft, as drawn in the meadow
TUFT_EVERY = 1600                                           # one tuft per this many art pixels
DIRT_BASE, DIRT_LIGHT, DIRT_DARK = (192, 154, 108), (210, 176, 127), (169, 128, 90)
DIRT_DARKEST, DIRT_SHINE = (138, 100, 70), (224, 197, 149)
DIRT = [DIRT_BASE, DIRT_LIGHT, DIRT_DARK, DIRT_DARKEST, DIRT_SHINE]
EDGE_GREEN = (86, 152, 79)

# --- the old cobblestone streets (world boxes x0, y0, x1, y1) ---
COBBLE_BOXES = [(-60, 18, 372, 58), (180, 18, 236, 150), (0, 132, 562, 188)]

# --- roads (world px) ---
MAIN_X, MAIN_HW = 208, 15          # the old north-south road
SOUTH_Y, SOUTH_HW = 255, 15        # the old east-west road
LANE_W = 22
LANES = [
    # the west loop: from the main road west along the top, down the west side, back along the bottom
    [(216, -150), (150, -149), (80, -152), (10, -147), (-60, -153), (-110, -148), (-140, -135),
     (-152, -105), (-150, -60), (-156, -20), (-153, 5), (-149, 40), (-155, 90), (-152, 125),
     (-140, 150), (-110, 160), (-50, 157), (20, 162), (90, 158), (150, 161), (216, 160)],
    # the middle lane on the west side (blacksmith, red house)
    [(-153, 5), (-100, 2), (-40, 8), (30, 4), (100, 7), (160, 4), (216, 5)],
    # from the main road north-east to the fishing shack's door
    [(200, -22), (240, -22), (290, -26), (335, -36), (362, -48), (375, -62)],
    # the bottom lane on the east side (potion shop), turning up to the wizard tower's door
    [(200, 166), (260, 167), (320, 163), (400, 168), (470, 163), (515, 158), (535, 140), (541, 110),
     (540, 78)],
]
# rounded corners: (x, y) where the two roads meet, which corners (dx, dy signs), half widths of
# the vertical and horizontal road, radius of the rounding (world px)
R_LANE, R_MAIN = 20, 24
CORNERS = [
    ((MAIN_X, -150), [(-1, -1), (-1, 1)], MAIN_HW, LANE_W / 2, R_LANE),
    ((MAIN_X, 5), [(-1, -1), (-1, 1)], MAIN_HW, LANE_W / 2, R_LANE),
    ((MAIN_X, -22), [(1, -1), (1, 1)], MAIN_HW, LANE_W / 2, R_LANE),
    ((MAIN_X, 160), [(-1, -1), (-1, 1)], MAIN_HW, LANE_W / 2, R_LANE),
    ((MAIN_X, 166), [(1, -1), (1, 1)], MAIN_HW, LANE_W / 2, R_LANE),
    ((MAIN_X, SOUTH_Y), [(-1, -1), (-1, 1), (1, -1)], MAIN_HW, SOUTH_HW, R_MAIN),
    ((-154, 5), [(1, -1), (1, 1)], LANE_W / 2, LANE_W / 2, R_LANE),
]
RUT_OFFSETS = (5, 12)              # wheel ruts: distance (world px) outside the rounding circle
RUT_TAIL = 14                      # how far the ruts run on along each road (world px)
FIELD_TOP_LEFT = (224, 271)        # the crop field south-east of the crossroads: never painted over


def to_art(wx, wy):
    return (np.asarray(wx, float) - CANVAS_WORLD[0]) * 2, (np.asarray(wy, float) - CANVAS_WORLD[1]) * 2


def smooth_noise(shape, scale, rng):
    small = rng.random((shape[0] // scale + 3, shape[1] // scale + 3))
    big = ndimage.zoom(small, scale, order=3)[: shape[0], : shape[1]]
    big = ndimage.gaussian_filter(big, scale / 3)
    return (big - big.mean()) / (big.std() + 1e-9)


def catmull_rom(points, step=0.5):
    p = np.array(points, float)
    p = np.vstack([p[0] * 2 - p[1], p, p[-1] * 2 - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(int(np.linalg.norm(p2 - p1) / step), 1)
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-2])
    return np.array(out)


def lane_field(h, w):
    """Signed distance-ish field in art px: negative inside a lane."""
    field = np.full((h, w), 1e9)
    for pts in LANES:
        curve = catmull_rom(pts)
        ax, ay = to_art(curve[:, 0], curve[:, 1])
        line = np.zeros((h, w), bool)
        ix, iy = np.round(ax).astype(int), np.round(ay).astype(int)
        ok = (ix >= 0) & (ix < w) & (iy >= 0) & (iy < h)
        line[iy[ok], ix[ok]] = True
        dist = ndimage.distance_transform_edt(~line)
        field = np.minimum(field, dist - LANE_W)               # LANE_W world wide = LANE_W art px half
    return field


def corner_field(h, w):
    """Negative inside the rounded corner fillings."""
    field = np.full((h, w), 1e9)
    yy, xx = np.mgrid[0:h, 0:w]
    for (cx, cy), quads, hw_v, hw_h, r in CORNERS:
        for sx, sy in quads:
            kx, ky = cx + sx * hw_v, cy + sy * hw_h            # corner of the grass block
            px, py = to_art(kx + sx * r, ky + sy * r)          # centre of the rounding
            ax0, ay0 = to_art(kx, ky)
            rr = r * 2
            in_sq = ((xx - ax0) * sx >= -12) & ((xx - ax0) * sx <= rr) & ((yy - ay0) * sy >= -12) & ((yy - ay0) * sy <= rr)
            d = rr - np.hypot(xx - px, yy - py)
            field = np.where(in_sq, np.minimum(field, d), field)
    return field


def ruts(h, w, rng):
    """Pixels of the wheel ruts: dark line + light line beside it."""
    dark, light = np.zeros((h, w), bool), np.zeros((h, w), bool)
    for (cx, cy), quads, hw_v, hw_h, r in CORNERS:
        for sx, sy in quads:
            kx, ky = cx + sx * hw_v, cy + sy * hw_h
            pcx, pcy = kx + sx * r, ky + sy * r
            for off in RUT_OFFSETS:
                R = r + off
                pts = []
                # arc from the vertical road (pointing along -sx from the centre) to the horizontal one
                for a in np.linspace(0, np.pi / 2, 160):
                    pts.append((pcx - sx * R * np.cos(a), pcy - sy * R * np.sin(a), 1.0))
                for t in np.linspace(0, RUT_TAIL, 50):        # tails running on along both roads
                    k = 1.0 - t / RUT_TAIL
                    pts.append((pcx - sx * R, pcy + sy * t, k))
                    pts.append((pcx + sx * t, pcy - sy * R, k))
                for x, y, k in pts:
                    if rng.random() > 0.15 + 0.75 * k:
                        continue
                    ax, ay = to_art(x, y)
                    ix, iy = int(round(float(ax))), int(round(float(ay)))
                    if 0 <= ix < w - 1 and 0 <= iy < h - 1:
                        dark[iy, ix] = True
    return dark, light & ~dark


def fill_grass(img, hole, rng):
    """Grow grass into `hole`: the shade pattern carries on from around it, plus specks and tufts."""
    h, w = hole.shape
    codes = img[:, :, 0] * 65536 + img[:, :, 1] * 256 + img[:, :, 2]
    level = np.full((h, w), np.nan)
    for i, g in enumerate(GRASS):
        level[codes == g[0] * 65536 + g[1] * 256 + g[2]] = i
    # the shade of the patch each pixel sits in (ignores the little specks)
    known = ~np.isnan(level) & ~hole
    votes = [ndimage.uniform_filter(((level == i) & known).astype(float), 7) for i in range(3)]
    tot = sum(votes)
    lev = np.where(tot > 0, sum(i * v for i, v in enumerate(votes)) / np.maximum(tot, 1e-9), np.nan)
    # solve on a 4x smaller grid: unknown cells relax to the average of their neighbours
    f = 4
    hs, ws = h // f, w // f
    small_hole = hole[: hs * f, : ws * f].reshape(hs, f, ws, f).any(axis=(1, 3))
    small_lev = np.nanmean(lev[: hs * f, : ws * f].reshape(hs, f, ws, f), axis=(1, 3))
    unknown = small_hole | np.isnan(small_lev)
    small_lev = np.where(unknown, 1.0, small_lev)
    region = ndimage.binary_dilation(small_hole, iterations=40)
    for _ in range(3000):
        avg = (np.roll(small_lev, 1, 0) + np.roll(small_lev, -1, 0) + np.roll(small_lev, 1, 1) + np.roll(small_lev, -1, 1)) / 4
        small_lev = np.where(unknown & region, avg, small_lev)
    big = ndimage.zoom(small_lev, f, order=1)
    big = np.pad(big, ((0, h - big.shape[0]), (0, w - big.shape[1])), mode="edge")
    edge_dist = ndimage.distance_transform_edt(hole)
    wobble = smooth_noise((h, w), 24, rng) * 0.55 * np.clip(edge_dist / 30.0, 0, 1)
    shade = np.clip(np.round(big + wobble), 0, 2).astype(int)
    ys, xs = np.nonzero(hole)
    s = shade[ys, xs]
    out = GRASS[s].copy()
    roll = rng.random(len(ys))
    for i in range(3):
        acc = 0.0
        for col, p in GRASS_SPECKS[i]:
            sel = (s == i) & (roll >= acc) & (roll < acc + p)
            out[sel] = col
            acc += p
    img[ys, xs] = out
    # tufts
    n = int(len(ys) / TUFT_EVERY)
    for k in rng.choice(len(ys), n, replace=False):
        y0, x0 = ys[k], xs[k]
        for dy, row in enumerate(TUFT):
            for dx, ch in enumerate(row):
                yy, xx = y0 + dy, x0 + dx
                if ch == "#" and yy < h and xx < w and hole[yy, xx]:
                    img[yy, xx] = TUFT_COLOUR


def paint_dirt(img, where, rng):
    """Dirt like the old roads: mostly plain, soft lighter and darker patches, a few dots."""
    h, w = where.shape
    patch = smooth_noise((h, w), 9, rng)
    patch2 = smooth_noise((h, w), 5, rng)
    ys, xs = np.nonzero(where)
    t, t2 = patch[ys, xs], patch2[ys, xs]
    r = rng.random(len(ys))
    out = np.tile(np.array(DIRT_BASE), (len(ys), 1))
    out[(t > 0.55) & (r < 0.75)] = DIRT_LIGHT
    out[(t2 < -1.3) & (r < 0.5)] = DIRT_DARK
    out[(r > 0.94) & (t <= 0.55)] = DIRT_LIGHT
    out[r < 0.012] = DIRT_DARKEST
    out[(r > 0.012) & (r < 0.02)] = DIRT_DARK
    out[r > 0.994] = DIRT_SHINE
    img[ys, xs] = out


def update_minimap(final_dirt):
    m = np.asarray(Image.open(MINIMAP).convert("RGBA")).copy()
    road = np.array([198, 159, 112, 255])
    h, w = final_dirt.shape
    tiles = 16 * 2                                                  # art px per minimap pixel
    for ty in range(h // tiles):
        for tx in range(w // tiles):
            wx = CANVAS_WORLD[0] // 16 + tx
            wy = CANVAS_WORLD[1] // 16 + ty
            mx, my = wx - MINIMAP_ORIGIN[0], wy - MINIMAP_ORIGIN[1]
            if not (0 <= mx < m.shape[1] and 0 <= my < m.shape[0]):
                continue
            frac = final_dirt[ty * tiles:(ty + 1) * tiles, tx * tiles:(tx + 1) * tiles].mean()
            if frac > 0.35:
                m[my, mx] = road
    Image.fromarray(m).save(MINIMAP)


def main():
    rng = np.random.default_rng(11)
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(int).copy()
    h, w = img.shape[:2]
    codes = img[:, :, 0] * 65536 + img[:, :, 1] * 256 + img[:, :, 2]
    is_dirt = np.isin(codes, [c[0] * 65536 + c[1] * 256 + c[2] for c in DIRT])

    # 1. cobblestones -> grass
    grey = (img.max(2) - img.min(2) < 45) & (img.sum(2) < 690)
    boxes = np.zeros((h, w), bool)
    for x0, y0, x1, y1 in COBBLE_BOXES:
        ax0, ay0 = to_art(x0, y0)
        ax1, ay1 = to_art(x1, y1)
        boxes[int(ay0):int(ay1), int(ax0):int(ax1)] = True
    cobble = ndimage.binary_dilation(grey & boxes, iterations=2) & boxes & ~is_dirt
    old_cobble = cobble.copy()
    fill_grass(img, cobble, rng)

    # 2./3. new lanes and rounded corners
    field = np.minimum(lane_field(h, w), corner_field(h, w))
    field += smooth_noise((h, w), 6, rng) * 1.2                     # slightly wobbly edges
    fx, fy = to_art(*FIELD_TOP_LEFT)
    yy, xx = np.mgrid[0:h, 0:w]
    crop_field = (xx >= fx) & (yy >= fy)
    new_dirt = (field < 0) & ~crop_field
    # the cobble that sat on the north-south road becomes road again
    main_lo, main_hi = to_art(MAIN_X - MAIN_HW, 0)[0], to_art(MAIN_X + MAIN_HW, 0)[0]
    cy0, cy1 = to_art(0, 18)[1], to_art(0, 192)[1]
    new_dirt |= (xx >= main_lo) & (xx < main_hi) & (yy >= cy0) & (yy < cy1)
    core = ndimage.binary_erosion(is_dirt, iterations=3)
    repaint = new_dirt & ~core
    paint_dirt(img, repaint, rng)

    # 4. edges, only around what changed
    final = new_dirt | is_dirt
    near = ndimage.binary_dilation(repaint | old_cobble, iterations=8) & ~ndimage.binary_dilation(crop_field, iterations=6)
    d_in = ndimage.distance_transform_edt(final)
    d_out = ndimage.distance_transform_edt(~final)
    green = (img[:, :, 1] > img[:, :, 0] + 25)
    img[near & final & (d_in <= 1)] = DIRT_DARKEST
    img[near & final & (d_in > 1) & (d_in <= 2)] = DIRT_DARK
    img[near & ~final & (d_out <= 2.3) & green & ~crop_field] = EDGE_GREEN
    # inside of the new dirt that was an old edge line (green rim, brown lines) gets plain dirt again
    d, l = ruts(h, w, rng)
    d &= final & (d_in > 2)
    l &= final & (d_in > 2)
    img[l] = DIRT_LIGHT
    img[d] = DIRT_DARK

    out = Image.fromarray(img.astype(np.uint8))
    for c, r in SQUARES:
        x0, y0 = (c - 2) * 1024, (r - 1) * 1024
        out.crop((x0, y0, x0 + 1024, y0 + 1024)).save(f"art/ground/g_{c}_{r}.png", optimize=True)
    update_minimap(final)
    print(f"cobble pixels regrown: {old_cobble.sum()}, dirt pixels painted: {repaint.sum()}")


if __name__ == "__main__":
    main()
