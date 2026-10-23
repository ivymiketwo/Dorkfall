"""Packs Rex's explosion pictures (art/explosion_src/explosion_N.png, 64x64, each a separate stage
from PixelLab) into one strip in play order: art/explosion.png.

    python3 tools/pack_explosion.py

ORDER lists which picture comes when (spark, flash, fireball, flames, smoke, puffs). Picture 3
(a smoke ring with an odd white middle) is left out.
"""
from PIL import Image

ORDER = [2, 7, 8, 5, 1, 6, 9, 0, 4]
SIZE = 64


def main():
    strip = Image.new("RGBA", (SIZE * len(ORDER), SIZE))
    for i, n in enumerate(ORDER):
        strip.alpha_composite(Image.open("art/explosion_src/explosion_%d.png" % n).convert("RGBA"), (i * SIZE, 0))
    strip.save("art/explosion.png")
    print("wrote art/explosion.png", strip.size)


if __name__ == "__main__":
    main()
