"""Turns a single upright staff picture into the game's art for a staff item.

    python3 tools/add_staff.py sun_staff "path/to/Object (54).png" 33

It:
  1. keeps the original in art/staff_src/<id>_original.png,
  2. trims it (1 px of empty border kept) to art/worn_<id>.png: the picture held in the hands
     (HeldWeapon uses a single upright picture as is; size it with the item's hold_scale),
  3. makes the inventory icon (the staff tilted 45 degrees, fitted to 32x32) and writes it into
     frame <icon_frame> of art/items.png and art/items_small.png.
The item itself (items/<id>.tres: name, stats, price, which spell it shoots) is written by hand.
"""
import math
import os
import shutil
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from new_gear import put_icon   # noqa: E402


def trimmed(img):
    bb = img.getbbox()
    crop = img.crop(bb)
    out = Image.new("RGBA", (crop.width + 2, crop.height + 2))
    out.alpha_composite(crop, (1, 1))
    return out


def icon_for(staff):
    crop = staff.crop(staff.getbbox())
    # pick the biggest scale whose 45-degree tilt still fits in 32x32
    s = 32.0 * math.sqrt(2) / (crop.width + crop.height)
    big = crop.resize((max(1, round(crop.width * s)), max(1, round(crop.height * s))), Image.NEAREST)
    tilted = big.rotate(-45, resample=Image.NEAREST, expand=True)
    tilted = tilted.crop(tilted.getbbox())
    if tilted.width > 32 or tilted.height > 32:
        k = 32.0 / max(tilted.size)
        tilted = tilted.resize((int(tilted.width * k), int(tilted.height * k)), Image.NEAREST)
    icon = Image.new("RGBA", (32, 32))
    icon.alpha_composite(tilted, ((32 - tilted.width) // 2, (32 - tilted.height) // 2))
    return icon


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sid, src, frame = sys.argv[1], sys.argv[2], int(sys.argv[3])
    os.makedirs("art/staff_src", exist_ok=True)
    shutil.copyfile(src, "art/staff_src/%s_original.png" % sid)
    img = Image.open(src).convert("RGBA")
    trimmed(img).save("art/worn_%s.png" % sid)
    put_icon(icon_for(img), frame)
    print("wrote art/worn_%s.png and icon frame %d" % (sid, frame))


if __name__ == "__main__":
    main()
