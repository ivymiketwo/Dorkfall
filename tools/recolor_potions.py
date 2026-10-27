"""Rex's 4 potion bottles (art/item_src/potion_src/{small,medium,large,huge}.png) recoloured into one
red set (health) and one blue set (mana): art/item_src/{health,mana}_potion_<size>.png.

Only the liquid changes (glass, cork and outline stay as drawn). Liquid = the strongly coloured
pixels below the cork. Its shades are sorted dark to light and spread over a 7-step ramp by how
much of the liquid each shade covers, so every bottle gets the same palette and the same shading
structure. Edit RED / BLUE to change the colours, then re-run (and tools/add_item_icons.py)."""
import colorsys
from collections import Counter
from PIL import Image

RED = [(70, 9, 22), (114, 16, 32), (156, 26, 40), (196, 44, 52), (230, 82, 78), (246, 148, 136), (255, 214, 204)]
BLUE = [(16, 24, 78), (26, 46, 136), (38, 82, 188), (54, 126, 230), (88, 170, 250), (154, 212, 255), (216, 240, 255)]
STEPS = [0.06, 0.30, 0.62, 0.82, 0.93, 0.975]     # cumulative share of the liquid -> ramp step
CORK_ROWS = 7                                     # rows from the top of the bottle that are cork


def is_liquid(rgb, y, top):
    if y < top + CORK_ROWS:
        return False
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    h *= 360
    if v < 0.12:
        return False                                  # black outline
    if 185 <= h <= 245:
        return s >= 0.55                              # blue liquid (the glass is pale blue-grey)
    return s >= 0.3                                   # red / pink / purple / orange liquid and glints


def recolor(img, ramp):
    img = img.convert("RGBA")
    px = img.load()
    top = img.getbbox()[1]
    liquid = Counter()
    where = []
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if p[3] and is_liquid(p[:3], y, top):
                liquid[p[:3]] += 1
                where.append((x, y))
    # pale bubbles / sparkles floating in the liquid: pixels with liquid on 3+ sides become the glint
    inside = set(where)
    sparkles = []
    for y in range(img.height):
        for x in range(img.width):
            if (x, y) in inside or px[x, y][3] == 0:
                continue
            n = sum((x + dx, y + dy) in inside for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if n >= 3:
                sparkles.append((x, y))
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    shades = sorted(liquid, key=lum)
    total = sum(liquid.values())
    step_of = {}
    done = 0
    for c in shades:
        mid = (done + liquid[c] / 2) / total
        done += liquid[c]
        step_of[c] = sum(1 for t in STEPS if mid >= t)
    # the very brightest shade always gets the top of the ramp (the glint)
    if len(shades) > 2:
        step_of[shades[-1]] = len(ramp) - 1
    for x, y in where:
        p = px[x, y]
        px[x, y] = ramp[step_of[p[:3]]] + (p[3],)
    for x, y in sparkles:
        px[x, y] = ramp[-2] + (255,)
    return img


for size in ["small", "medium", "large", "huge"]:
    src = Image.open(f"art/item_src/potion_src/{size}.png")
    recolor(src, RED).save(f"art/item_src/health_potion_{size}.png")
    recolor(src, BLUE).save(f"art/item_src/mana_potion_{size}.png")
    print(size, "done")
