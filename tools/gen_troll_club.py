"""Builds art/troll.png: Rex's troll frames (art/troll_src) with a big stone club drawn into
the troll's hand in every frame, and the throw frames turned into an overhead club smash.

The club is not a picture that gets rotated (that would make jagged pixels): it is drawn fresh
for every frame from a few numbers - where the fist is, which way the club points, how
foreshortened it is (pointing at / away from the camera makes it look shorter) and whether it
is in front of or behind the body. Those numbers are the tables below (CLUB). When the club is
in front, the fist is pasted back over the handle so the troll grips it.

Sheet layout (same as before, bigger cells so the club fits): CELL_W x CELL_H cells,
7 columns x 16 rows; rows = anim*4 + facing (down, up, left, right); anims idle (1 frame),
walk (6), swing (7), death (7). The old 80 px cell sits at (PAD_X, PAD_Y) inside each cell, so
the feet are at (40 + PAD_X, 62 + PAD_Y).

Run from the repo root:  python3 tools/gen_troll_club.py           (writes art/troll.png)
                         python3 tools/gen_troll_club.py --debug   (also marks the grips)
"""
import math
import sys
from PIL import Image

SRC = "art/troll_src"
OUT = "art/troll.png"
OLD = 80
CELL_W, CELL_H = 96, 92
PAD_X, PAD_Y = 8, 6
FACINGS = ["down", "up", "left", "right"]
ANIMS = [("idle", 1), ("walk", 6), ("throw", 7), ("death", 7)]

OUTLINE = (4, 4, 6, 255)
STONE = [(34, 34, 44), (52, 52, 64), (72, 72, 84), (96, 95, 104), (124, 122, 128), (156, 153, 154)]
WOOD = [(44, 28, 22), (72, 46, 30), (102, 68, 42), (134, 92, 56)]
ROPE = [(92, 58, 28), (146, 98, 44), (184, 132, 62)]

# club shape, in art px along its length from the grip
POMMEL = 2.0          # handle sticking out behind the fist
HEAD_AT = 10.0        # where the stone starts (rope binding here)
LENGTH = 30.0         # grip to the tip of the head
HANDLE_R = 1.3
HEAD_R0, HEAD_R1 = 2.8, 5.6
LIGHT = (-0.5, -0.7, 0.55)

# Per frame: (grip x, grip y, angle, length scale, layer) in the old 80 px cell.
# angle: screen direction from the fist to the club head (0 right, 90 down, 180 left,
# 270 up). length scale: 1 = seen side-on, smaller = pointing towards/away from the camera.
# layer: "front" (over the body, fist re-pasted on top) or "back" (behind the body).
# None = no club drawn in that frame.
CLUB = {
    ("idle", "down"): [(23, 51, 115, 0.75, "front")],
    ("idle", "up"): [(56, 51, 65, 0.75, "front")],
    ("idle", "left"): [(30, 47, 115, 0.8, "front")],
    ("idle", "right"): [(46, 47, 65, 0.8, "front")],
    ("walk", "down"): [(31, 52, 115, 0.75, "front")] * 6,
    ("walk", "up"): [(52, 50, 65, 0.75, "front")] * 6,
    ("walk", "right"): [(47, 52, 70, 0.8, "front"), (48, 52, 70, 0.8, "front"),
                         (46, 52, 70, 0.8, "front"), (44, 51, 72, 0.8, "front"),
                         (42, 53, 74, 0.8, "front"), (42, 53, 74, 0.8, "front")],
    ("throw", "down"): [
        (23, 47, 150, 0.8, "front"),
        (20, 43, 210, 0.9, "front"),
        (22, 19, 300, 0.6, "back"),
        (31, 21, 275, 0.5, "back"),
        (30, 53, 95, 0.9, "front"),
        (26, 50, 115, 0.75, "front"),
        (26, 50, 115, 0.75, "front"),
    ],
    ("throw", "up"): [
        (52, 42, 60, 0.8, "front"),
        (52, 47, 40, 0.9, "front"),
        (55, 29, 285, 0.8, "front"),
        (45, 11, 100, 0.75, "front"),
        (24, 55, 250, 0.8, "back"),
        (51, 53, 75, 0.75, "front"),
        (50, 52, 75, 0.75, "front"),
    ],
    ("throw", "left"): [
        (25, 45, 110, 0.8, "front"),
        (17, 30, 300, 0.9, "back"),
        (52, 19, 340, 0.9, "back"),
        (12, 22, 100, 1.0, "front"),
        (36, 56, 150, 0.9, "front"),
        (22, 44, 115, 0.8, "front"),
        (31, 49, 115, 0.8, "front"),
    ],
    ("throw", "right"): [
        (51, 38, 70, 0.8, "front"),
        (54, 33, 230, 0.9, "back"),
        (25, 19, 200, 0.9, "back"),
        (74, 29, 80, 1.0, "front"),
        (50, 45, 60, 0.9, "front"),
        (52, 48, 65, 0.8, "front"),
        (46, 46, 65, 0.8, "front"),
    ],
}
# death: frame 1 still in the hand (same as walk frame 1), frame 2 falling out of it,
# then lying on the ground beside the body: (grip x, grip y, angle) of the lying club.
DEATH_FALL = {
    "down": [(24, 52, 140, 0.8, "front")],
    "up": [(54, 52, 40, 0.8, "back")],
    "right": [(40, 50, 40, 0.9, "back")],
}
DEATH_LIE = {"down": (8, 60, 10), "up": (60, 58, 170), "right": (16, 60, 0)}


def mirror(entries):
    out = []
    for e in entries:
        if e is None:
            out.append(None)
            continue
        x, y, a, s, layer = e
        out.append((OLD - 1 - x, y, (180 - a) % 360, s, layer))
    return out


def death_entries(facing):
    hold = CLUB[("walk", facing)][0]
    lie = DEATH_LIE[facing]
    return [hold] + DEATH_FALL[facing] + [(lie[0], lie[1], lie[2], 1.0, "back")] * 5


def club_for(anim, facing):
    if anim == "death":
        if facing == "left":
            return mirror(death_entries("right"))
        return death_entries(facing)
    if (anim, facing) in CLUB:
        return CLUB[(anim, facing)]
    if facing == "left":                # walk west is the east walk mirrored (same in the art)
        return mirror(CLUB[(anim, "right")])
    raise KeyError((anim, facing))


def _hash(a, b):
    h = (a * 374761393 + b * 668265263) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return (h ^ (h >> 16)) / 0xFFFFFFFF


def _radius(t):
    if t < HEAD_AT:
        return HANDLE_R
    k = min(1.0, (t - HEAD_AT) / (LENGTH - HEAD_AT - 4.0))
    k = k * k * (3 - 2 * k)
    r = HEAD_R0 + (HEAD_R1 - HEAD_R0) * k
    return r


def draw_club(size, gx, gy, angle, s):
    """Returns {(x, y): colour} for the club pixels (no outline), and the outline set."""
    w, h = size
    a = math.radians(angle)
    d = (math.cos(a), math.sin(a))
    n = (-d[1], d[0])
    cx, cy = gx + 0.5, gy + 0.5
    r_end = _radius(LENGTH - 0.01)
    t_end = LENGTH - r_end                # axis stops where the round end cap begins
    ex, ey = cx + d[0] * s * t_end, cy + d[1] * s * t_end
    L = LIGHT
    ln = math.sqrt(sum(c * c for c in L))
    L = (L[0] / ln, L[1] / ln, L[2] / ln)
    pix = {}
    span = int(LENGTH + 8)
    for y in range(max(0, int(cy) - span), min(h, int(cy) + span)):
        for x in range(max(0, int(cx) - span), min(w, int(cx) + span)):
            px, py = x + 0.5 - cx, y + 0.5 - cy
            along = px * d[0] + py * d[1]
            u = px * n[0] + py * n[1]
            t = along / max(s, 0.05)
            hit = None
            if -POMMEL <= t <= t_end:
                r = _radius(t)
                # lumpy stone: the head's edge wobbles a little
                if t >= HEAD_AT:
                    r += (_hash(int(t), 1 if u > 0 else 2) - 0.5) * 0.9
                if abs(u) <= r:
                    a2 = max(-1.0, min(1.0, u / r))
                    nz = math.sqrt(max(0.0, 1 - a2 * a2))
                    nrm = (n[0] * a2, n[1] * a2, nz)
                    hit = (t, u, nrm)
            qx, qy = x + 0.5 - ex, y + 0.5 - ey
            dq = math.hypot(qx, qy)
            if dq <= r_end + (_hash(int(math.degrees(math.atan2(qy, qx)) // 40), 7) - 0.5) * 0.9:
                wx, wy = qx / r_end, qy / r_end
                nz = math.sqrt(max(0.0, 1 - min(1.0, wx * wx + wy * wy)))
                if hit is None or s < 0.9:      # the head end covers the handle when foreshortened
                    hit = (LENGTH, u, (wx, wy, nz))
            if hit is None:
                continue
            t, u, nrm = hit
            b = nrm[0] * L[0] + nrm[1] * L[1] + nrm[2] * L[2]
            if t < HEAD_AT - 0.5:
                pal = WOOD
                k = (b + 0.2) / 1.2
                grain = _hash(int(t), int(u + 9)) - 0.5
                k += grain * 0.25
            elif t < HEAD_AT + 1.5:
                pal = ROPE
                k = (b + 0.2) / 1.2 + (0.25 if (int(t * 1.5) + int(u + 9)) % 2 else -0.15)
            else:
                pal = STONE
                k = (b + 0.35) / 1.35
                tex = _hash(int(t * 0.7), int(u * 0.7 + 20))
                k += (tex - 0.5) * 0.3
                if _hash(int(t), int(u + 30)) > 0.93:
                    k -= 0.35                    # little cracks and pits
            idx = max(0, min(len(pal) - 1, int(round(k * (len(pal) - 1)))))
            pix[(x, y)] = pal[idx] + (255,)
    outline = set()
    for (x, y) in pix:
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ox, y + oy)
            if q not in pix and 0 <= q[0] < w and 0 <= q[1] < h:
                outline.add(q)
    return pix, outline


def compose(body, entry, fist_r=3.0):
    """body: the troll frame already placed in a CELL_W x CELL_H image."""
    if entry is None:
        return body.copy()
    gx, gy, angle, s, layer = entry
    gx += PAD_X
    gy += PAD_Y
    pix, outline = draw_club(body.size, gx, gy, angle, s)
    club = Image.new("RGBA", body.size)
    cp = club.load()
    for q in outline:
        cp[q] = OUTLINE
    for q, c in pix.items():
        cp[q] = c
    if layer == "back":
        out = club.copy()
        out.alpha_composite(body)
        return out
    out = body.copy()
    out.alpha_composite(club)
    # the fist goes back over the handle
    op, bp = out.load(), body.load()
    for y in range(int(gy - fist_r - 1), int(gy + fist_r + 2)):
        for x in range(int(gx - fist_r - 1), int(gx + fist_r + 2)):
            if 0 <= x < body.width and 0 <= y < body.height:
                if math.hypot(x - gx, y - gy) <= fist_r and bp[x, y][3] > 0:
                    op[x, y] = bp[x, y]
    return out


def build(debug=False):
    sheet = Image.new("RGBA", (CELL_W * 7, CELL_H * 16))
    for ai, (anim, count) in enumerate(ANIMS):
        for fi, facing in enumerate(FACINGS):
            entries = club_for(anim, facing)
            for c in range(count):
                im = Image.open(f"{SRC}/{anim}_{facing}_{c + 1}.png").convert("RGBA")
                body = Image.new("RGBA", (CELL_W, CELL_H))
                off = (OLD - im.width) // 2
                body.alpha_composite(im, (PAD_X + off, PAD_Y + off))
                frame = compose(body, entries[c])
                if debug and entries[c] is not None:
                    frame.putpixel((entries[c][0] + PAD_X, entries[c][1] + PAD_Y), (255, 0, 255, 255))
                sheet.alpha_composite(frame, (c * CELL_W, (ai * 4 + fi) * CELL_H))
    return sheet


if __name__ == "__main__":
    dbg = "--debug" in sys.argv
    out = build(dbg)
    out.save("/tmp/troll_club_debug.png" if dbg else OUT)
