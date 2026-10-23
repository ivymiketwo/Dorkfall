"""Packs Rex's clockwork spider (art/spider_src/) into one sheet: art/clockwork_spider.png.

    python3 tools/pack_spider.py

Same layout as the cow (tools/pack_cows.py): row 0 = standing, rows 1-4 = walking, 8 frames
each; columns in row 0 and the order of rows 1-4 follow the player's facing order:
down (south), up (north), left (west), right (east). Each picture is only moved so that the
middle of its canvas is the middle of the frame and its feet end on the row FEET.
"""
import os
from PIL import Image

SRC = "art/spider_src"
OUT = "art/clockwork_spider.png"
FW, FH = 56, 52
FEET = 48
DIRS = ["south", "north", "west", "east"]
WALK = 8


def place(img, bottom):
    out = Image.new("RGBA", (FW, FH))
    out.alpha_composite(img, (FW // 2 - img.width // 2, FEET - bottom))
    return out


def main():
    sheet = Image.new("RGBA", (FW * WALK, FH * 5))
    for col, d in enumerate(DIRS):
        img = Image.open(os.path.join(SRC, "stand_%s.png" % d)).convert("RGBA")
        sheet.alpha_composite(place(img, img.getbbox()[3]), (col * FW, 0))
        frames = [Image.open(os.path.join(SRC, "walk_%s_%d.png" % (d, i + 1))).convert("RGBA")
                  for i in range(WALK)]
        bottom = max(f.getbbox()[3] for f in frames)
        for i, f in enumerate(frames):
            sheet.alpha_composite(place(f, bottom), (i * FW, (1 + col) * FH))
    sheet.save(OUT)
    print("wrote", OUT, sheet.size)


if __name__ == "__main__":
    main()
