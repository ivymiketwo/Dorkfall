"""Puts 32x32 item pictures from art/item_src/ into the icon sheets: art/items.png (32 px frames)
and art/items_small.png (8 px frames, shrunk). Usage: python3 tools/add_item_icons.py name:frame ...
e.g. flux:38 magical_elixir:39. The sheets grow if the frame is past their end."""
import sys
from PIL import Image


def put(sheet_path, frame, img, cell):
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.width < (frame + 1) * cell:
        bigger = Image.new("RGBA", ((frame + 1) * cell, cell), (0, 0, 0, 0))
        bigger.paste(sheet, (0, 0))
        sheet = bigger
    sheet.paste(Image.new("RGBA", (cell, cell), (0, 0, 0, 0)), (frame * cell, 0))
    sheet.alpha_composite(img, (frame * cell, 0))
    sheet.save(sheet_path)


for arg in sys.argv[1:]:
    name, frame = arg.split(":")
    img = Image.open(f"art/item_src/{name}.png").convert("RGBA")
    assert img.size == (32, 32), f"{name}: expected 32x32, got {img.size}"
    put("art/items.png", int(frame), img, 32)
    put("art/items_small.png", int(frame), img.resize((8, 8), Image.BOX), 8)
    print(name, "-> frame", frame)
