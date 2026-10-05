"""Turns a 4-direction gear drawing into a finished, wearable item in one go.

    python3 tools/new_gear.py iron_chestplate "Iron Chestplate" chest --defense 10 --value 250

Before running it, draw art/gear_src/<id>_4dir.png: 192x48, four 48x48 frames in the order
down (front), up (back), left, right, each drawn over the standing frame of that facing in
art/player_new.png (open that sheet, copy the first column's frames, draw the gear on a layer
above, export only the gear layer). Optionally also draw art/gear_src/<id>_icon.png (32x32);
without one, the icon is made from the front view.

It then:
  1. puts the gear on every walk / run / jump frame:
       chest   -> the body is DRESSED in it, like the robe: art/player_<id>.png, a whole player
                  sheet that replaces the body while worn (tools/gen_body_sheet.py)
       helmet / shield -> drawn on top as a layer: art/worn_<id>.png (tools/gen_worn_layer.py)
     plus a preview to check: art/gear_src/<id>_4dir_preview.png (both tools explain how to fix
     a single frame by hand),
  2. makes the paperdoll picture -> art/<id>_paperdoll.png,
  3. adds the icon to art/items.png and art/items_small.png (re-running replaces it in place),
  4. writes items/<id>.tres with the slot and stats given.
Restart Godot (or use a launcher) afterwards so it imports the new pictures.
"""
import argparse
import os
import re
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_body_sheet   # noqa: E402
import gen_worn_layer   # noqa: E402

SLOTS = ["helmet", "chest", "shield"]


def icon_from_front(front):
    bb = front.getbbox()
    crop = front.crop(bb)
    scale = 2 if crop.width * 2 <= 32 and crop.height * 2 <= 32 else 1
    big = crop.resize((crop.width * scale, crop.height * scale), Image.NEAREST)
    icon = Image.new("RGBA", (32, 32))
    icon.alpha_composite(big, ((32 - big.width) // 2, (32 - big.height) // 2))
    return icon


def put_icon(icon, frame):
    """Writes the icon into frame `frame` of the icon sheets (appending if it's a new frame)."""
    for path, size in (("art/items.png", 32), ("art/items_small.png", 8)):
        sheet = Image.open(path).convert("RGBA")
        n = sheet.width // size
        if frame >= n:
            grown = Image.new("RGBA", ((frame + 1) * size, size))
            grown.alpha_composite(sheet, (0, 0))
            sheet = grown
        small = icon if size == 32 else icon.resize((8, 8), Image.NEAREST)
        sheet.paste(Image.new("RGBA", (size, size)), (frame * size, 0))
        sheet.alpha_composite(small, (frame * size, 0))
        sheet.save(path)


def existing_icon_frame(tres):
    if os.path.exists(tres):
        m = re.search(r"icon_frame = (\d+)", open(tres).read())
        if m:
            return int(m.group(1))
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id")
    ap.add_argument("name")
    ap.add_argument("slot", choices=SLOTS)
    ap.add_argument("--defense", type=float, default=0.0)
    ap.add_argument("--value", type=int, default=50)
    ap.add_argument("--description", default="")
    a = ap.parse_args()

    src = "art/gear_src/%s_4dir.png" % a.id
    if not os.path.exists(src):
        sys.exit("draw %s first (see the top of this file)" % src)
    front = Image.open(src).convert("RGBA").crop((0, 0, 48, 48))
    if a.slot == "chest":
        art_path, field = "art/player_%s.png" % a.id, "body_sheet"
        gen_body_sheet.main(src, art_path)
        doll = Image.open(art_path).convert("RGBA").crop((0, 0, 48, 48))   # the dressed standing frame
    else:
        art_path, field = "art/worn_%s.png" % a.id, "worn_texture"
        gen_worn_layer.main(src, art_path)
        doll = Image.open(gen_worn_layer.BASE).convert("RGBA").crop((0, 0, 48, 48))
        doll.alpha_composite(front)
    doll_path = "art/%s_paperdoll.png" % a.id
    doll.save(doll_path)

    icon_src = "art/gear_src/%s_icon.png" % a.id
    icon = Image.open(icon_src).convert("RGBA") if os.path.exists(icon_src) else icon_from_front(front)
    tres = "items/%s.tres" % a.id
    frame = existing_icon_frame(tres)
    if frame is None:
        frame = Image.open("art/items.png").width // 32
    put_icon(icon, frame)

    with open(tres, "w") as f:
        f.write('[gd_resource type="Resource" script_class="Item" load_steps=4 format=3]\n\n')
        f.write('[ext_resource type="Script" path="res://scripts/item.gd" id="1_item"]\n')
        f.write('[ext_resource type="Texture2D" path="res://%s" id="2_art"]\n' % art_path)
        f.write('[ext_resource type="Texture2D" path="res://%s" id="3_doll"]\n\n' % doll_path)
        f.write('[resource]\nscript = ExtResource("1_item")\n')
        f.write('id = &"%s"\ndisplay_name = "%s"\n' % (a.id, a.name))
        if a.description:
            f.write('description = "%s"\n' % a.description.replace('"', "'"))
        f.write('icon_frame = %d\nvalue = %d\n' % (frame, a.value))
        if a.defense:
            f.write('defense = %s\n' % a.defense)
        f.write('equip_slot = "%s"\ntwo_handed = false\n' % a.slot)
        f.write('%s = ExtResource("2_art")\npaperdoll_texture = ExtResource("3_doll")\n' % field)
    print("made %s (icon frame %d)" % (tres, frame))


if __name__ == "__main__":
    main()
