"""Paints the eastern desert onto the ground art, updates the minimap, and draws the cactus art.

Run from the project root:   python3 tools/gen_desert.py
Needs Pillow and numpy. Only GRASS pixels inside the desert are repainted (roads, the border
wall and anything else stay as they are), so running it again changes nothing.

World layout (see scenes/main.tscn, GroundArt): the two east chunks ground_1_0.png (top) and
ground_1_1.png (bottom) cover world x 720..3120, y -992..1696, at 2 art pixels per world pixel.
"""
import math
import numpy as np
from PIL import Image, ImageDraw

SEED = 7
CHUNK_X = 720          # world x of the east chunks' left edge
TOP_Y = -992           # world y of the top chunk
DESERT_X = 2290        # world x where the desert starts (the edge wobbles around this)
EDGE_WOBBLE = 70       # world px the edge wanders left/right
FADE = 90              # world px of grass-to-sand dithering

SAND = np.array([(220, 188, 133), (233, 207, 155), (242, 223, 179)], dtype=np.uint8)   # beach tones
SAND_DEEP = np.array((209, 174, 120), dtype=np.uint8)    # dune shadows
SPECKS = [((192, 154, 108), 0.010), ((250, 236, 200), 0.004), ((214, 128, 84), 0.0012), ((150, 118, 84), 0.0015)]

rng = np.random.default_rng(SEED)


def smooth_noise(w, h, cell, octaves=3):
    """Blobby value noise in 0..1, size (h, w)."""
    out = np.zeros((h, w), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = max(int(cell / (2 ** o)), 4)
        gw, gh = w // c + 3, h // c + 3
        grid = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8))
        big = grid.resize((gw * c, gh * c), Image.BICUBIC)
        arr = np.asarray(big, dtype=np.float32)[:h, :w] / 255.0
        out += arr * amp
        total += amp
        amp *= 0.5
    return out / total


ROAD_Y = (238, 274)     # world y band of the east-west road (keeps its own colours)


def replaceable(px, world_y):
    """Grass (and the flower speckles in it) can become sand; roads and the stone border can't."""
    r, g, b = px[..., 0].astype(int), px[..., 1].astype(int), px[..., 2].astype(int)
    green = (g > r + 12) & (g > b + 8)
    stone = (abs(r - g) < 12) & (abs(g - b) < 14) & (r < 180)
    in_road = (world_y >= ROAD_Y[0]) & (world_y <= ROAD_Y[1])
    return np.where(in_road, green, ~stone)


def paint():
    top = Image.open("art/ground_1_0.png").convert("RGB")
    bot = Image.open("art/ground_1_1.png").convert("RGB")
    w, h = top.width, top.height + bot.height
    art = np.concatenate([np.asarray(top), np.asarray(bot)], axis=0).copy()

    ys = np.arange(h)[:, None]
    xs = np.arange(w)[None, :]
    world_x = CHUNK_X + xs / 2.0
    world_y = TOP_Y + ys / 2.0

    # wobbly edge line
    wob = (np.sin(world_y / 180.0) * 0.55 + np.sin(world_y / 67.0 + 1.3) * 0.3 + np.sin(world_y / 29.0 + 4.0) * 0.15)
    edge = DESERT_X + wob * EDGE_WOBBLE
    t = (world_x - edge) / FADE                       # <0 grass, 0..1 dithered, >1 sand

    blobs = smooth_noise(w, h, 120)
    grain = rng.random((h, w)).astype(np.float32)
    # dithering like the beach: blobby, then speckled at the very edge
    want_sand = (t + (blobs - 0.5) * 0.9 + (grain - 0.5) * 0.35) > 0.5
    # a few grass tufts surviving a little way into the sand
    tufts = smooth_noise(w, h, 40, 2)
    want_sand &= ~((tufts > 0.78) & (t < 2.2) & (grain < 0.85))

    mask = want_sand & replaceable(art, world_y)

    # sand tones: flat blobs, like the beach
    tone_n = smooth_noise(w, h, 90, 3)
    tone = np.digitize(tone_n, [0.44, 0.58])           # 0 dark, 1 base, 2 light
    sand = SAND[tone]

    # dunes: long soft ridges with a bright crest and a shadow just below it
    warp = smooth_noise(w, h, 260, 2)
    ridge = np.sin((world_y + warp * 140.0 + np.sin(world_x / 130.0) * 24.0) / 21.0)
    dune_zone = (smooth_noise(w, h, 300, 2) > 0.58) & (t > 1.5)
    crest = dune_zone & (ridge > 0.96)
    shade = dune_zone & (ridge < -0.62) & (ridge > -0.78)
    sand[shade] = SAND_DEEP
    sand[crest] = SAND[2]

    spk = rng.random((h, w))
    acc = 0.0
    for col, p in SPECKS:
        sel = (spk >= acc) & (spk < acc + p)
        sand[sel] = col
        acc += p

    art[mask] = sand[mask]
    Image.fromarray(art[: top.height]).save("art/ground_1_0.png")
    Image.fromarray(art[top.height:]).save("art/ground_1_1.png")
    return edge


def minimap():
    """art/world_map.png is one pixel per 16px tile, top-left tile (-105, -62)."""
    m = Image.open("art/world_map.png").convert("RGBA")
    a = np.asarray(m).copy()
    h, w = a.shape[:2]
    noise = rng.random((h, w))
    for ty in range(h):
        wy = (ty - 62) * 16 + 8
        wob = math.sin(wy / 180.0) * 0.55 + math.sin(wy / 67.0 + 1.3) * 0.3 + math.sin(wy / 29.0 + 4.0) * 0.15
        edge = DESERT_X + wob * EDGE_WOBBLE + FADE * 0.5
        for tx in range(w):
            wx = (tx - 105) * 16 + 8
            r, g, b, al = a[ty, tx]
            if wx < edge or not (g > r + 12 and g > b + 8):
                continue
            c = (222, 200, 144) if noise[ty, tx] > 0.25 else (212, 188, 132)
            a[ty, tx] = (*c, al)
    Image.fromarray(a).save("art/world_map.png")


def cactus(path, arms, height, seed):
    """A saguaro in the game's pixel style (32px-tile art, outlined)."""
    r = np.random.default_rng(seed)
    W, H = 40, height + 8
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    OUT, DARK, MID, LIGHT, SPINE = (34, 52, 34, 255), (52, 108, 58, 255), (74, 142, 72, 255), (112, 178, 92, 255), (236, 226, 190, 255)

    def column(x0, y0, x1, y1, wdt):
        d.rounded_rectangle((x0 - 1, y0 - 1, x0 + wdt, y1 + 1), radius=wdt // 2, fill=OUT)
        d.rounded_rectangle((x0, y0, x0 + wdt - 1, y1), radius=wdt // 2 - 1, fill=MID)
        d.line((x0 + 1, y0 + 2, x0 + 1, y1 - 1), fill=LIGHT)
        d.line((x0 + wdt - 2, y0 + 2, x0 + wdt - 2, y1 - 1), fill=DARK)
        d.line((x0 + wdt // 2, y0 + 3, x0 + wdt // 2, y1 - 2), fill=DARK)   # rib

    cx, base = W // 2 - 5, H - 4
    for side, ah, alen in arms:
        y = base - ah
        if side < 0:
            column(cx - 10, y - alen, cx - 10 + 7, y, 7)
            d.rectangle((cx - 9, y - 6, cx + 1, y), fill=OUT)
            d.rectangle((cx - 8, y - 5, cx + 1, y - 1), fill=MID)
            d.line((cx - 8, y - 5, cx, y - 5), fill=LIGHT)
        else:
            column(cx + 13, y - alen, cx + 13 + 7, y, 7)
            d.rectangle((cx + 9, y - 6, cx + 20, y), fill=OUT)
            d.rectangle((cx + 9, y - 5, cx + 19, y - 1), fill=MID)
            d.line((cx + 9, y - 1, cx + 19, y - 1), fill=DARK)
    column(cx, base - height, cx + 10, base, 10)
    px = img.load()
    for _ in range(18):   # spines
        x, y = r.integers(4, W - 4), r.integers(4, H - 4)
        if px[x, y][3] and px[x, y] != OUT:
            px[x, y] = SPINE
    # little sand mound at the foot
    d.ellipse((cx - 6, base - 2, cx + 16, base + 3), fill=(209, 174, 120, 255))
    d.rectangle((cx, base - 3, cx + 9, base), fill=MID)
    d.line((cx - 1, base - 3, cx - 1, base), fill=OUT)
    d.line((cx + 10, base - 3, cx + 10, base), fill=OUT)
    img.save(path)


if __name__ == "__main__":
    paint()
    minimap()
    cactus("art/cactus_a.png", [(-1, 22, 12), (1, 30, 10)], 46, 1)
    cactus("art/cactus_b.png", [(1, 16, 9)], 32, 2)
    cactus("art/cactus_c.png", [], 22, 3)
    print("desert painted")
