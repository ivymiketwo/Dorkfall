"""Turns a 4-direction gear drawing into a finished, wearable item in one go.

    python3 tools/new_gear.py iron_helm "Iron Helm" helmet --defense 4 --value 70

Slots and the body pieces they dress (see art/gear_src/body_parts.png):
    helmet -> head      chest -> chest      legs -> legs

Before running it, draw art/gear_src/<id>_4dir.png: 192x48, four 48x48 frames in the order
down (front), up (back), left, right, each drawn over the standing frame of that facing in
art/player_new.png. Optionally also draw art/gear_src/<id>_icon.png (32x32).

It then:
  1. dresses every walk / run / jump frame with it, piece by piece using the body-part map, and
     saves just the repainted pixels as a layer: art/worn_<id>.png (the game draws it over the
     body, so a helm, a chestplate and greaves can all be worn at once). A preview of every frame:
     art/gear_src/<id>_4dir_preview.png
  2. puts the icon in art/items.png and art/items_small.png. A NEW item gets one made from the
     front view (or <id>_icon.png); an EXISTING item keeps its icon unless <id>_icon.png exists,
  3. writes items/<id>.tres. If the item already exists only its worn art is updated; its name,
     stats and price are left alone (the options below are for new items).
Restart Godot (or use a launcher) afterwards so it imports the new pictures.
"""
import argparse
import os
import re
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_body_sheet   # noqa: E402

SLOTS = ["helmet", "chest", "legs"]
PIECES = {"helmet": ("head",), "chest": ("chest",), "legs": ("legs",)}


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
    worn = "art/worn_%s.png" % a.id
    gen_body_sheet.main(src, worn, PIECES[a.slot], overlay=True)

    tres = "items/%s.tres" % a.id
    icon_src = "art/gear_src/%s_icon.png" % a.id
    frame = existing_icon_frame(tres)
    if frame is None or os.path.exists(icon_src):
        if frame is None:
            frame = Image.open("art/items.png").width // 32
        icon = Image.open(icon_src).convert("RGBA") if os.path.exists(icon_src) else icon_from_front(front)
        put_icon(icon, frame)

    if os.path.exists(tres):
        update_item(tres, worn)
        print("updated %s (worn art only; icon frame %d)" % (tres, frame))
        return
    with open(tres, "w") as f:
        f.write('[gd_resource type="Resource" script_class="Item" load_steps=3 format=3]\n\n')
        f.write('[ext_resource type="Script" path="res://scripts/item.gd" id="1_item"]\n')
        f.write('[ext_resource type="Texture2D" path="res://%s" id="2_worn"]\n\n' % worn)
        f.write('[resource]\nscript = ExtResource("1_item")\n')
        f.write('id = &"%s"\ndisplay_name = "%s"\n' % (a.id, a.name))
        if a.description:
            f.write('description = "%s"\n' % a.description.replace('"', "'"))
        f.write('icon_frame = %d\nvalue = %d\n' % (frame, a.value))
        if a.defense:
            f.write('defense = %s\n' % a.defense)
        f.write('equip_slot = "%s"\ntwo_handed = false\n' % a.slot)
        f.write('worn_texture = ExtResource("2_worn")\n')
    print("made %s (icon frame %d)" % (tres, frame))


def update_item(tres, worn):
    """Points an existing item at the new worn layer, leaving everything else as it was."""
    s = open(tres).read()
    s = re.sub(r'\[ext_resource type="Texture2D"[^\n]*id="(2_worn|2_art|3_doll|4_body)"\]\n', "", s)
    s = re.sub(r'\n(worn_texture|paperdoll_texture|body_sheet) = [^\n]*', "", s)
    s = re.sub(r'\nbody_jump_frames = [^\n]*', "", s)
    s = s.replace('[ext_resource type="Script" path="res://scripts/item.gd" id="1_item"]\n',
                  '[ext_resource type="Script" path="res://scripts/item.gd" id="1_item"]\n'
                  '[ext_resource type="Texture2D" path="res://%s" id="2_worn"]\n' % worn, 1)
    s = s.rstrip("\n") + '\nworn_texture = ExtResource("2_worn")\n'
    open(tres, "w").write(s)


if __name__ == "__main__":
    main()
