"""Draws the Yank Line's 16x16 ability icon (a purple line snaking up to a weighted tip) into
art/icons.png at slot 7 (the sheet grows if needed). Re-run to redraw it."""
import math
from PIL import Image

SLOT = 7
DARK = (58, 24, 96, 255)
MID = (150, 82, 224, 255)
LIGHT = (214, 176, 255, 255)

im = Image.open("art/icons.png").convert("RGBA")
if im.width < (SLOT + 1) * 16:
    bigger = Image.new("RGBA", ((SLOT + 1) * 16, 16), (0, 0, 0, 0))
    bigger.paste(im, (0, 0))
    im = bigger
icon = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
px = icon.load()

core = []
for i in range(400):
    u = i / 399
    # a loose line snaking from the bottom-left corner up to the tip
    bx, by = 2 + 10 * u, 13 - 10 * u
    w = 3.2 * math.sin(u * math.pi * 3.0) * (1 - 0.5 * u)
    p = (int(round(bx + w * 0.7)), int(round(by + w * 0.7)))
    if not core or core[-1] != p:
        core.append(p)
tip = (12, 3)
cs = set(core)
for (x, y) in core:                       # a dark shadow under the line
    for d in ((0, 1), (1, 1)):
        q = (x + d[0], y + d[1])
        if 0 <= q[0] < 16 and 0 <= q[1] < 16 and q not in cs:
            px[q] = DARK
for (x, y) in core:
    px[x, y] = MID
for k, (x, y) in enumerate(core):        # brighter towards the tip
    if k % 2 == 0 and k > len(core) * 0.5:
        px[x, y] = LIGHT
# the weighted tip: a little bead
for dx in (-1, 0, 1, 2):
    for dy in (-1, 0, 1, 2):
        if abs(dx - 0.5) + abs(dy - 0.5) <= 2:
            px[tip[0] + dx, tip[1] + dy] = DARK
for dx in (0, 1):
    for dy in (0, 1):
        px[tip[0] + dx, tip[1] + dy] = MID
px[tip[0], tip[1]] = LIGHT
im.paste(icon, (SLOT * 16, 0))
im.save("art/icons.png")
print("icon", SLOT, "drawn")
