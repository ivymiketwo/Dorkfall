# Dorkfall: project brief for Claude

Godot 4.7 top-down pixel-art game. Long-term goal: a small persistent online world, so keep
server-readiness and dupe prevention in mind (see MIGRATION_NOTES.md before touching game rules).

## Working with Rex
- Rex is not a programmer: explain things in plain language, no jargon without a short explanation.
- Rex plays from a Git clone on Windows using two launchers in the repo root:
  `update_and_play.bat` (pull, import, play) and `update_and_edit.bat` (pull, open editor).
  Push finished work to `main`; that is what the launchers pull.
- The launchers discard Godot's own automatic edits to `project.godot` (backed up to
  `project.godot.local-backup`) and `*.import` files before pulling. Rex never edits those by hand.
- Images pasted into chat arrive re-compressed. For exact pixel files (maps, sprites) ask Rex to
  zip the PNG and attach the zip, or upload it to GitHub.

## Checking your work
- Godot 4.7.2 Linux binary: download from the GitHub releases if not present. Import first:
  `godot --headless --path . --import`, then run scenes headless, or with
  `xvfb-run ... --rendering-driver opengl3` for screenshots.
- Main scene is `scenes/game.tscn` (a wrapper: the world in `scenes/main.tscn` renders at
  640x360 in a SubViewport; CanvasLayers in group `ui_layer` are drawn at full window resolution).

## Art and world facts
- Viewport 640x360, camera zoom 2. Tiles are 32 px art drawn at half scale (16 world px), so
  1 art pixel = 0.5 world px. Player sheet: 48x48 frames, 9 x 12 (rows = anim*4 + facing
  down/up/left/right; anims idle 4 frames, run 4, jump 9).
- The ground is a painting cut into 512 px squares (`art/ground/`, streamed by `GroundStream`).
  Edit with `tools/ground_tiles.py` (`assemble()` / `split()`); the invisible tile layer from
  `scripts/world.gd` only does collision.
- East mountains + red-clay ravine (world x ~2500..5280): a pass through the mountains that opens out
  into the east desert (to the map edge at x 6512). Made by `tools/gen_ravine.py`, which paints
  the ground, writes the wall tiles (`data/mountains.json`, read by `scripts/world.gd`), the minimap
  and the ravine / east-desert props. It needs ~5 GB of memory. Re-run it to change them (it starts from `art/ground_src/east_before_ravine.png`).
  Unreachable land there is left unpainted and its ground squares don't exist (GroundStream skips them).
- Monsters are split into a brain (no visuals) and a Look node; far-away ones sleep (`SleepRegions`).

## Difficulty design (Rex's rules)
- Stronger monsters must be *harder to play against*, not spongier: keep time-to-kill roughly flat
  and scale difficulty with shorter telegraphs, smaller punish windows, better aim, more/mixed
  attacks, smarter movement and monster combinations. Avoid big health multipliers.
- Aim prediction (`AttackRules.predict`): monsters past the ravine aim where the player will be,
  not where they stand (the ravine's skeleton wizards don't; they're fast instead). Vorly (first boss) stays easy to dodge by moving.
- Level gap (`AttackRules.level_gap_mult`, applied in `Stats.take_damage`): a player hitting a
  monster up to 3 levels above does full damage, then 5% less per extra level, floor 60%.

## Gear (armour) pipeline: read art/gear_src/README.md
- Never regenerate `data/hands.json` with `tools/gen_hand_data.py`: it holds hand-tuned
  staff positions that the tool would overwrite.
- `art/player_new.png` is trimmed from `art/gear_src/player_new_original.png` by
  `tools/trim_body.py`. Never edit the trimmed sheet directly; edit the map or the original.
- Admin/debug: F1-F4 keys and chat commands (`/help`) are kept on purpose for testing
  (listed in MIGRATION_NOTES.md to lock down before a server exists).
