#!/usr/bin/env python3
"""Finds the character's RIGHT hand in every frame of the player sheets and writes data/hands.json.

Run it again whenever you change art/player_new.png or art/player_new_robe.png:
    python3 tools/gen_hand_data.py

Sheet layout: 9 columns x 12 rows of 48x48 frames; row = animation*4 + facing (down, up, left, right);
animations are idle (4 frames), run (4), jump (9).

For each frame it stores [x, y, behind]: the hand position in art pixels, and whether the held weapon
should be drawn BEHIND the body (1) or in front of it (0). The weapon is behind when the right hand is
on the far side of the body (facing up or left) or when no hand is visible in the frame.
"""
import json, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = [4, 4, 9]                  # idle, run, jump
FACINGS = ["down", "up", "left", "right"]
DEFAULT = {"down": (14, 28), "up": (34, 28), "left": (22, 28), "right": (26, 28)}


def skin_mask(a):
    r, g, b, al = [a[..., i].astype(float) for i in range(4)]
    return (al > 0) & (r - b > 40) & (r > g) & (g > b) & (b / np.maximum(g, 1) > 0.7)


def find_hand(frame, facing):
    a = np.array(frame)
    opaque = a[..., 3] > 0
    if not opaque.any():
        return None
    ys, xs = np.where(opaque)
    top, bot = ys.min(), ys.max()
    h = bot - top + 1
    sk = skin_mask(a)
    band = np.zeros_like(sk)
    band[int(top + 0.30 * h):int(top + 0.80 * h) + 1, :] = True
    cand = sk & band
    if facing in ("left", "right"):
        # side view: the hanging arm, roughly mid-body
        mid = np.zeros_like(sk)
        mid[int(top + 0.42 * h):int(top + 0.68 * h) + 1, :] = True
        c = sk & mid
        if c.sum() >= 2:
            yy, xx = np.where(c)
            x = float(np.median(xx))
            return x, float(np.median(yy)), c.sum()
        return None
    # only the character's right side of the body counts (down = screen-left, up = screen-right)
    ox = np.where(opaque)[1]
    head = opaque.copy()
    head[int(top + 0.25 * h):, :] = False
    cx = float(np.median(np.where(head)[1])) if head.any() else float(np.median(ox))
    side = np.zeros_like(sk)
    side[:, :int(cx) - 1 if facing == "down" else 0] = facing == "down"
    if facing == "up":
        side[:, int(cx) + 2:] = True
    cand = cand & side
    if cand.sum() < 2:
        return None
    yy, xx = np.where(cand)
    # character's right hand: facing down = screen-left, facing up = screen-right
    # take the outermost skin pixels of that side (the hand), averaged
    order = np.argsort(xx) if facing == "down" else np.argsort(-xx)
    pick = order[:max(2, len(order) // 6)]
    return float(xx[pick].mean()), float(yy[pick].mean()), len(pick)


def smooth(rowdata, anim, n):
    """Steady the hand: idle uses one fixed hand position (plus the body's own bob), run/jump average with neighbours."""
    pts = [r for r in rowdata[:n]]
    xs = np.array([p[0] for p in pts]); ys = np.array([p[1] for p in pts])
    if anim == 0:
        xs[:] = np.median(xs); ys[:] = np.round(np.mean(ys) * 2) / 2
    else:
        return rowdata          # run and jump: follow the hand exactly
    for i, p in enumerate(pts):
        p[0] = round(float(xs[i]), 1); p[1] = round(float(ys[i]), 1)
    return rowdata


def process(path):
    sheet = Image.open(path).convert("RGBA")
    out = {}
    for anim, n in enumerate(FRAMES):
        for f, facing in enumerate(FACINGS):
            row = anim * 4 + f
            rowdata, last = [], None
            for i in range(9):
                if i >= n:
                    rowdata.append(None)
                    continue
                fr = sheet.crop((i * 48, row * 48, i * 48 + 48, row * 48 + 48))
                hand = find_hand(fr, facing)
                if hand is None:
                    x, y = last if last else DEFAULT[facing]
                    rowdata.append([round(x, 1), round(y, 1), 1])      # no visible hand: hide the weapon behind the body
                else:
                    x, y, _ = hand
                    last = (x, y)
                    behind = 1 if facing in ("up", "left") else 0
                    rowdata.append([round(x, 1), round(y, 1), behind])
            out[str(row)] = smooth(rowdata, anim, n)
    return out


if __name__ == "__main__":
    data = {
        "naked": process(os.path.join(ROOT, "art", "player_new.png")),
        "robe": process(os.path.join(ROOT, "art", "player_new_robe.png")),
    }
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "hands.json"), "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print("wrote data/hands.json")
