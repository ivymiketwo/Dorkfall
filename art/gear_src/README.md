# Making wearable gear

Gear (helmets, chest pieces, leg armour) is drawn once in 4 directions and then fitted onto
all 68 frames of the character automatically, using the **body-part map**.

## The files in this folder
| File | What it is |
|---|---|
| `body_parts.png` | **The body-part map** (432x576, same layout as `art/player_new.png`). Every body pixel is painted with the colour of its piece. Hand-made by Rex. |
| `body_parts_legend.png` | The colours. |
| `player_new_original.png` | The untrimmed character. `art/player_new.png` is made from it (see "Trimming"). |
| `<name>_4dir.png` | A piece of gear drawn in 4 directions (the input). |
| `<name>_4dir_preview.png` | Every frame wearing it (made by the tool, for checking). |
| `body_plain_4x*.png`, `body_parts_*4x.png`, `body_parts_overlay_4x.png` | 4x helper images for editing the map. |

This folder has a `.gdignore`, so Godot never imports or ships any of it.

## The body-part map
One plain colour per piece:

| Piece | Colour (R, G, B) |
|---|---|
| head | 230, 60, 60 |
| chest | 60, 190, 60 |
| arms | 240, 110, 200 |
| legs | 70, 100, 240 |
| feet | 240, 220, 50 |

- **Outlines stay unpainted.** Dark outline pixels (the body's edge, the gaps between arms and
  torso) are left transparent in the map, so every outfit keeps the character's outline.
- **Skin left unpainted is cut away** from the character by the trim (see below).
- Optional, for frames that need steering: a piece can be split into four quarters with
  quarter colours (top-left, top-right, bottom-left, bottom-right as seen on screen). They are
  listed in `tools/gen_part_map.py` (`COLORS`). Plain and quarter colours can be mixed.
- Edit with a pencil tool, no smoothing, colours picked with the eyedropper. Editing at 4x is
  fine: send the 4x file (1728x2304) and it is scaled down by taking the middle of each 4x4 block.

## Making a new piece of gear
1. Draw `<name>_4dir.png`: 192x48, four 48x48 frames in this order: **front (down), back (up),
   left, right**. Draw each one over the first standing frame of that direction in
   `art/player_new.png` (rows 0-3, column 0), on its own layer, then export only the gear.
   Paint over the pixels of the piece it covers (head / chest / legs in the map).
   Optional: `<name>_icon.png` (32x32 inventory icon).
2. Run:
   ```
   python3 tools/new_gear.py <name> "<Display Name>" <slot> --defense 6 --value 150
   ```
   Slots: `helmet` (dresses the head), `chest` (chest), `legs` (legs).
3. Check `<name>_4dir_preview.png`. Restart Godot / use a launcher so it imports the new art.

What it does:
- Every frame is dressed piece by piece using the map. The piece is mapped along the body's
  tilt (an axis from the middle of the legs to the middle of the head), so gear leans in jumps.
  Each pixel of the piece takes the gear colour from the same relative spot on the standing pose.
- The result is saved as a **layer of only the repainted pixels**: `art/worn_<name>.png`. The
  game draws it over the body frame by frame, so helmet + chest + legs stack.
- New items get `items/<name>.tres` and an icon (in `art/items.png` and `art/items_small.png`).
  For an existing item only the worn art is updated; its stats, price and icon are kept
  (unless `<name>_icon.png` exists).

The current iron set was drawn by script: `tools/draw_iron_chestplate.py` (chestplate) and
`tools/draw_iron_gear.py` (helm, greaves). Their drawings follow the map's areas, so re-run
them (then `new_gear.py`) after changing the map.

## After changing the map
```
python3 tools/trim_body.py                 # re-trim the character from the original
python3 tools/draw_iron_chestplate.py      # only for the script-drawn iron set
python3 tools/draw_iron_gear.py
python3 tools/new_gear.py iron_chestplate "Iron Chestplate" chest
python3 tools/new_gear.py iron_helm "Iron Helm" helmet
python3 tools/new_gear.py iron_greaves "Iron Greaves" legs
```
(re-run `new_gear.py` for every other piece of gear too).

## Trimming
`tools/trim_body.py` makes `art/player_new.png` from `player_new_original.png`: painted pixels
keep their colour, outlines within 1 px of the painted body stay, unpainted skin next to the body
becomes outline, everything else is deleted. Always re-run it rather than editing
`art/player_new.png` by hand.

## Rules
- **Do not regenerate `data/hands.json`** (`tools/gen_hand_data.py`): it holds hand-tuned staff
  positions. Small trims don't need new hand positions.
- The wizard robe is different: a hand-drawn full body sheet (`body_sheet` on the item) that
  replaces the body. Gear layers hide while it is worn.
- Tools need Python 3 with Pillow and numpy.
