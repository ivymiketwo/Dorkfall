"""Rex's generated rooms sometimes come back with the floor cut out (transparent), leaving only the
plank seams. This paints a wooden plank floor back in under them.

  python3 tools/fill_room_floor.py <original.png> <out.png> [door_x0 door_x1]

Floor = transparent pixels inside the walls (found by flooding the outside from the picture's
edges; the doorway at the bottom edge between door_x0..door_x1 is sealed so the flood can't get in
through it). Each plank row (between the seam rows) gets its own slightly different wood tone and
a little grain, so it doesn't look flat."""
import random
import sys
from collections import deque
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
door = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else None
im = Image.open(src).convert("RGBA")
W, H = im.size
px = im.load()

outside = [[False] * H for _ in range(W)]
q = deque()
for x in range(W):
    for y in (0, H - 1):
        if door and y == H - 1 and door[0] <= x <= door[1]:
            continue                          # the doorway: don't flood in through it
        q.append((x, y))
for y in range(H):
    q.append((0, y)); q.append((W - 1, y))
while q:
    x, y = q.popleft()
    if x < 0 or y < 0 or x >= W or y >= H or outside[x][y] or px[x, y][3] > 0:
        continue
    if door and y == H - 1 and door[0] <= x <= door[1]:
        continue
    outside[x][y] = True
    q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

# plank rows: rows that hold several 1-px-tall seam pixels
seam_rows = []
for y in range(1, H - 1):
    n = sum(1 for x in range(W) if px[x, y][3] and not px[x, y - 1][3] and not px[x, y + 1][3])
    if n > 6:
        seam_rows.append(y)

BASE = (132, 96, 68)
rng = random.Random(7)
tones = {}
for y in range(H):
    band = sum(1 for s in seam_rows if s <= y)
    if band not in tones:
        tones[band] = rng.uniform(-9, 9)
    for x in range(W):
        if outside[x][y] or px[x, y][3] > 0:
            continue
        t = tones[band] + rng.uniform(-3, 3)
        if (x * 7 + band * 13) % 23 == 0:
            t -= 7                            # a little grain
        if y - 1 in seam_rows:
            t += 6                            # catch light just under a seam
        r, g, b = (max(0, min(255, int(c + t))) for c in BASE)
        px[x, y] = (r, g, b, 255)
im.save(out)
print("seams at", seam_rows)
