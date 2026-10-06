"""Trims the base character to the body-part map: only what was painted in the map stays.

    python3 tools/trim_body.py

For every frame of art/player_new.png:
  - pixels painted in art/gear_src/body_parts.png keep their colour,
  - other pixels (outline or skin) within 1 pixel of a painted pixel become / stay the outline,
  - everything else is deleted.
So bare skin left unpainted in the map is cut away and the new edge gets a 1 pixel outline,
and outlines that no longer border the body disappear.
The untrimmed original is kept in art/gear_src/player_new_original.png (the trim always starts
from that, so it can be re-run after editing the map).
"""
import os
import shutil
import numpy as np
from PIL import Image

BASE = "art/player_new.png"
ORIGINAL = "art/gear_src/player_new_original.png"
MAP = "art/gear_src/body_parts.png"
CELL = 48
DARK = 70


def main():
    if not os.path.exists(ORIGINAL):
        shutil.copy(BASE, ORIGINAL)
    src = np.array(Image.open(ORIGINAL).convert("RGBA"))
    painted = np.array(Image.open(MAP).convert("RGBA"))[..., 3] > 0
    out = np.zeros_like(src)
    h, w = painted.shape
    lum = src[..., :3].astype(float) @ np.array([0.3, 0.59, 0.11])
    removed = kept_outline = new_outline = 0
    for y in range(h):
        for x in range(w):
            if src[y, x, 3] == 0:
                continue
            if painted[y, x]:
                out[y, x] = src[y, x]
                continue
            # nearest painted neighbour (8 directions, same frame only)
            near = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if (dy or dx) and 0 <= ny < h and 0 <= nx < w and ny // CELL == y // CELL \
                            and nx // CELL == x // CELL and painted[ny, nx]:
                        near.append((ny, nx))
            if not near:
                removed += 1
                continue
            if lum[y, x] < DARK:
                out[y, x] = src[y, x]                 # an outline next to the body: keep it
                kept_outline += 1
            else:
                out[y, x] = darkest_outline(src, lum, y, x)   # bare skin at the new edge -> outline
                new_outline += 1
    Image.fromarray(out).save(BASE)
    print("trimmed %s: %d pixels deleted, %d outline kept, %d skin turned into outline" % (BASE, removed, kept_outline, new_outline))


def darkest_outline(src, lum, y, x):
    """An outline colour from the original art near (y, x) (falls back to near-black)."""
    best = None
    for r in range(1, 4):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                ny, nx = y + dy, x + dx
                if 0 <= ny < src.shape[0] and 0 <= nx < src.shape[1] and src[ny, nx, 3] and lum[ny, nx] < DARK:
                    if best is None or lum[ny, nx] < lum[best]:
                        best = (ny, nx)
        if best:
            return src[best]
    return np.array([0, 1, 6, 255], dtype=src.dtype)


if __name__ == "__main__":
    main()
