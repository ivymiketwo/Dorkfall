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
- Pixels stay sharp everywhere: the project default texture filter is Nearest, and every
  SubViewport must also set `canvas_item_default_texture_filter = 0` (Nearest), because
  SubViewports ignore the project setting and default to Linear (blurry).

## Art and world facts
- Viewport 640x360, camera zoom 2 (the mouse wheel zooms 0.8x-1.25x around that, see `world.gd`
  `_apply_zoom`: zoomed, the world's SubViewport renders at window resolution with a 640x360
  `size_2d_override`, so the layout, the interface and the mouse coordinates never change). Tiles are 32 px art drawn at half scale (16 world px), so
  1 art pixel = 0.5 world px. The world is laid out at 640x360 but DRAWN at the window's resolution
  (`world.gd` `_apply_zoom`, always on), so small things may use finer art: 1 art px = 0.25 world px
  (e.g. dropped coins, `Item.ground_scale` 0.25). Rule (Rex agreed): only tiny / fast / glowing things
  (drops, coins, sparkles, spell particles, icons) get the finer pixels, never anything with a body
  (characters, monsters, buildings, trees). The camera rounds to window pixels (`Player._place_camera`). Player sheet: 48x48 frames, 9 x 12 (rows = anim*4 + facing
  down/up/left/right; anims idle 4 frames, run 4, jump 9).
- The ground is a painting cut into 512 px squares (`art/ground/`, streamed by `GroundStream`).
  Edit with `tools/ground_tiles.py` (`assemble()` / `split()`); the invisible tile layer from
  `scripts/world.gd` only does collision.
- Village: dirt lanes painted by `tools/paint_village_roads.py` (LANES / CORNERS; re-run from
  `art/ground_src/village_before_roads.png`). Move a building -> adjust the lanes and re-run.
- East mountains + red-clay ravine (world x ~2500..4470): a pass through the mountains that widens
  into a grey rocky valley (cracked grey ground, rock outcrops for trolls) out to the map edge at
  x 6512. Made by `tools/gen_ravine.py`, which paints the ground, writes the wall tiles
  (`data/mountains.json`, read by `scripts/world.gd`), the minimap and the ravine / valley props.
  Valley walls: `VALLEY_TOP` / `VALLEY_BOTTOM`; outcrops: `OUTCROPS`; the north-west cliff from the
  mountains up to the top of the map: `NW_CLIFF` (its strip starts from `art/ground_src/north_before_cliff.png`). It paints in strips (~3 GB of
  memory, ~3.5 minutes). Re-run it to change them (it starts from `art/ground_src/east_before_ravine.png`).
  Unreachable land there is left unpainted and its ground squares don't exist (GroundStream skips them).
- Monsters are split into a brain (no visuals) and a Look node; far-away ones sleep (`SleepRegions`).
  Trolls (grey valley) reuse the skeleton wizard brain (`scripts/troll.gd` extends it). Their club is
  drawn into `art/troll.png` by `tools/gen_troll_club.py` (edit its CLUB table, never the sheet).
- Ducks (`scripts/ducks.gd`, drawing only): Rex's poses in `art/duck_src/`, packed into `art/ducks.png`
  by `tools/pack_ducks.py` (lines up the waterlines, makes the blink frame).
- Barn + cow paddock (south-west of the crossroads): `scenes/barn.tscn`; `scenes/paddock.tscn`
  (`scripts/paddock.gd` builds the fence and gate from Rex's ranch fence pieces, cut from
  `art/fence_src/` by `tools/cut_fence.py` into decor kinds `rfence_*`; `scripts/cow.gd` cows wander
  inside, solid, and stop short of the player). Cow sheet `art/cow.png` from `tools/pack_cows.py`
  (originals in `art/cow_src/`). The minimap there was repainted by hand to match.

## The player
- Always a wizard: no classes, no melee swing, no shields, no iron armour. Left click fires
  the staff's spell. Right click holds the Ward (`scripts/ward.gd`): a mana-powered
  block (50% / 25% mana for aimed hits it faces, 30% / 50% mana for everything else) with a parry window; the orb is lit from the mouse side (`shaders/ward_orb.gdshader`). Stats are Intelligence (mana, magic damage) and Vitality (health).
  No stamina and no sprint. Space is a plain jump (no cost, no cooldown; the old "Begone" gust
  hop skill was removed at Rex's request).
- Momentum (player.gd, "Momentum" group in the Inspector): speed above walking is carried and
  only goes one way (no air strafing, Rex's call: wrong vibe for top-down). On the ground it bleeds
  off, and the friction ramps up the longer you stay on the ground (`friction_start` ->
  `friction_max` over `friction_ramp` s), so jumping right as you land keeps nearly all of it and
  late jumps eat speed (Rex's design). Each jump in a row shortens that grace (`ramp_shrink`, floor
  `friction_ramp_min`); it resets whenever you're back at walking speed or less, for any reason,
  and when a yank gives fresh speed (Rex asked for that reset to be bulletproof). A jump keeps the part of your speed pointing where you jump
  (at least walking speed if moving); no steering in the air; walls soak up what hits them.
  Momentum skills push the player through `Player.yank_to` (and later more like it). Planned: a
  wind gust cast on the ground that you walk into.
- Staff spells: besides left click, a staff can have up to 3 more spells (`Item.spells`), cast
  with Q / E / R (actions `staff_spell_1..3`, rebindable; `BasicAttack.cast_staff_spell`). Rex's
  plan: several colour-coded spells per staff, each staff with its own theme. First: the
  Linecaster Staff (Astral Staff art), purple-rope theme modelled on a MICLIC line charge (no
  rocket): Q = Yank Line (`scripts/line_yank.gd` / `scenes/spells/line_yank.tscn`), a grapple
  that must NOT look like a grapple: the line is flung, lies loose and wiggly, snaps tight and
  yanks you to its tip. Space during the yank hops out at full speed.
- Keep the gear-fitting pipeline (below) for future wizard-style armour that isn't a robe.
- New staffs are a single upright picture: `tools/add_staff.py <id> <png> <icon_frame>` keeps the
  original in `art/staff_src/`, trims it to `art/worn_<id>.png` and makes the tilted inventory
  icon; then write `items/<id>.tres` by hand (copy `amethyst_staff.tres`). `HeldWeapon` uses the
  whole picture when it isn't an old 120x160 worn sheet. `hold_scale` 0.77 = same pixel size as the
  character (Rex draws them about 50 px tall in an 80x80 canvas so they don't drag on the floor).
  Fine-detail staffs (Rex's test, the Astral Staff): drawn ~100 px tall, `hold_scale` 0.385 (half-size pixels).
  Spells leave from the orb, 4 picture px below the top; if the orb sits lower (under a spike or in a
  cage) set the item's `orb_from_top` (the Amethyst Staff uses 9).
- Unique staff attacks: an ability of kind SPELL points at a scene in `scenes/spells/` whose root
  script runs the whole attack (rules on the game tick via AttackTimeline, the rest is drawing)
  and gets `caster` and `damage` from BasicAttack. First one: the Sun Staff's halo beam
  (`scripts/sun_halo.gd`, timings in `scenes/spells/sun_halo.tscn`'s Inspector).
  The Void Staff's black hole: `scripts/void_hole.gd` / `scenes/spells/void_hole.tscn`.
  The Clockwork Staff's spider: `scripts/clockwork_spider.gd` / `scenes/spells/clockwork_spider.tscn`
  (ray, summoning circle, orange half-dome, then a clockwork spider that hunts the nearest monster
  and explodes). Spider sheet `art/clockwork_spider.png` from `tools/pack_spider.py` (originals in
  `art/spider_src/`, drawn at native half size); explosion strip `art/explosion.png` from
  `tools/pack_explosion.py` (Rex's 10 stages in `art/explosion_src/`, frame order in its ORDER list).
  A spell can root its caster (`player.rooted_until`) and fill the cast bar (`Hotbar.start_channel`).

## Difficulty design (Rex's rules)
- Stronger monsters must be *harder to play against*, not spongier: keep time-to-kill roughly flat
  and scale difficulty with shorter telegraphs, smaller punish windows, better aim, more/mixed
  attacks, smarter movement and monster combinations. Avoid big health multipliers.
- Aim prediction (`AttackRules.predict`, e.g. the wizard's `aim_lead`): aims where the player will
  be. Not a default: only use it on the monsters / attacks Rex picks. Vorly (first boss) stays easy to dodge by moving.
- Level gap (`AttackRules.level_gap_mult`, applied in `Stats.take_damage`): a player hitting a
  monster up to 3 levels above does full damage, then 5% less per extra level, floor 60%.

## Gear (armour) pipeline: read art/gear_src/README.md
- Never regenerate `data/hands.json` with `tools/gen_hand_data.py`: it holds hand-tuned
  staff positions that the tool would overwrite.
- `art/player_new.png` is trimmed from `art/gear_src/player_new_original.png` by
  `tools/trim_body.py`. Never edit the trimmed sheet directly; edit the map or the original.
- Admin/debug: F1-F4 keys and chat commands (`/help`) are kept on purpose for testing
  (listed in MIGRATION_NOTES.md to lock down before a server exists).
