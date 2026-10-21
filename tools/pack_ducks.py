"""Packs Rex's duck pictures (art/duck_src/*.png, 32x32 each) into one strip: art/ducks.png.

    python3 tools/pack_ducks.py

Each picture is moved up or down so its waterline (the bottom of the body) is on the same row
in every frame; they are otherwise left exactly as drawn. A blink frame is made from the
floating duck by closing its eye. The frame order is FRAMES below; scripts/ducks.gd uses the
same order (keep the two in step if you add a pose).
"""
import os
from PIL import Image

SRC = "art/duck_src"
OUT = "art/ducks.png"
SIZE = 32
WATERLINE = 27      # the first row under the body, in every frame
FRAMES = ["float", "blink", "quack", "preen_back", "preen_breast", "sleep",
          "dip", "dip_deep", "tail_up", "flap_half", "flap_up"]
# the floating duck's eye (x, y) and what to paint there for the blink
EYE_OPEN_TO_GREEN = [(21, 9), (22, 9)]
EYE_CLOSED_LINE = [(21, 10), (22, 10)]


def aligned(img):
    bb = img.getbbox()
    out = Image.new("RGBA", (SIZE, SIZE))
    out.alpha_composite(img, (0, WATERLINE - bb[3]))
    return out


def main():
    strip = Image.new("RGBA", (SIZE * len(FRAMES), SIZE))
    base = aligned(Image.open(os.path.join(SRC, "float.png")).convert("RGBA"))
    dy = WATERLINE - Image.open(os.path.join(SRC, "float.png")).getbbox()[3]
    for i, name in enumerate(FRAMES):
        if name == "blink":
            img = base.copy()
            green = img.getpixel((20, 9 + dy))
            dark = img.getpixel((22, 10 + dy))
            for x, y in EYE_OPEN_TO_GREEN:
                img.putpixel((x, y + dy), green)
            for x, y in EYE_CLOSED_LINE:
                img.putpixel((x, y + dy), dark)
        else:
            img = aligned(Image.open(os.path.join(SRC, name + ".png")).convert("RGBA"))
        strip.alpha_composite(img, (i * SIZE, 0))
    strip.save(OUT)
    print("wrote", OUT, strip.size)


if __name__ == "__main__":
    main()
