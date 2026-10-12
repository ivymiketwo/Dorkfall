"""Draws the rock the trolls throw: art/troll_rock.png, 4 frames of 20x20 (the same rock
turned a quarter each frame, so it tumbles while flying), in the troll sheet's greys.
Run from the repo root: python3 tools/gen_troll_rock.py"""
import math
import random
from PIL import Image

S = 20
OUTLINE = (4, 4, 6, 255)
SHADES = [(55, 54, 73), (80, 82, 97), (106, 110, 115), (137, 142, 143), (159, 167, 164), (198, 205, 198)]


def rock() -> Image.Image:
    rnd = random.Random(5)
    # a lumpy blob: radius changes around the edge
    bumps = [rnd.uniform(0.82, 1.0) for _ in range(9)]

    def r_at(a):
        f = (a / math.tau) * 9
        i = int(f) % 9
        t = f - int(f)
        return 7.6 * (bumps[i] * (1 - t) + bumps[(i + 1) % 9] * t)

    im = Image.new("RGBA", (S, S))
    px = im.load()
    cx, cy = 9.5, 10.0
    inside = set()
    for y in range(S):
        for x in range(S):
            dx, dy = x + 0.5 - cx - 0.5, y + 0.5 - cy - 0.5
            if math.hypot(dx, dy) <= r_at(math.atan2(dy, dx) % math.tau):
                inside.add((x, y))
    for (x, y) in inside:
        dx, dy = x - cx, y - cy
        # lit from the top left, a facet line across the middle
        light = (-dx * 0.55 - dy * 0.8) / 7.6
        if dx + dy * 0.4 > 1.5:
            light -= 0.35
        light += rnd.uniform(-0.12, 0.12)
        k = max(0, min(len(SHADES) - 1, int(round(2.2 + light * 2.4))))
        px[x, y] = SHADES[k] + (255,)
    for y in range(S):
        for x in range(S):
            if (x, y) in inside:
                continue
            if any((x + i, y + j) in inside for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = OUTLINE
    return im


def main() -> None:
    r = rock()
    sheet = Image.new("RGBA", (S * 4, S))
    for i in range(4):
        sheet.alpha_composite(r.rotate(-90 * i), (i * S, 0))
    sheet.save("art/troll_rock.png")


if __name__ == "__main__":
    main()
