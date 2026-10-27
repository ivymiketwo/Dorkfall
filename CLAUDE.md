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
  The whole mountain is painted, unreachable parts too (`PAINT_ALL` in gen_ravine.py, Rex: no black
  areas on the map); GroundStream still skips any square that has no file.
- Enchanted forest (east of the troll valley, world x 6512..9456, about 80% of the green biome; the
  map grew to 696 x 168 tiles, ground squares to 22 columns): the valley narrows into a pass at
  x ~6400-6512 (VALLEY_TOP / VALLEY_BOTTOM end points in `tools/gen_ravine.py`); past it the
  mountain's cliffs carry on along Rex's red lines (EAST_TOP / EAST_BOTTOM; gen_ravine now paints to
  XM 7264, keeping everything west of x 6512 exactly as it was, and writes
  `art/ground_src/ravine_east_walk.png` so gen_enchanted keeps that rock: run gen_ravine first). It opens into a
  village (see below), then a big open clearing full of goblins (path ends at ~8050, 330). Ground + minimap: `tools/gen_enchanted.py` (moss, forest floor under the
  EnchForest* polygons in main.tscn, the PATH, a grey-to-moss seam at the pass; re-run after moving
  the forests). Dense forests: EnchForestNorth / South / East (Rex will reshape them) with Rex's big
  enchanted trees (`ench_*` in tree_art.gd); single trees EnchTree* use kinds "ench" / "ench_pine"
  (his small blue trees, `std_ench_*`).
- Monsters are split into a brain (no visuals) and a Look node; far-away ones sleep (`SleepRegions`).
  Trolls (grey valley) reuse the skeleton wizard brain (`scripts/troll.gd` extends it) and throw
  rocks (Rex had a club version added, then asked for it removed: rock throwers only).
- Goblins (enchanted forest's big clearing, ~200 in packs of 3-6): Rex's "tower defense" monster, NOT a
  dodging fight: no telegraph, low health (80, no level scaling), runs at you faster than you walk
  (chase 92 vs walk 70) with the run animation and just punches (`scripts/goblin.gd` brain,
  `scripts/goblin_look.gd`, `scenes/goblin.tscn`). Each punch picks the left or right hand at random
  (mirrored rows of the sheet). One that spots you or gets hit calls the goblins within `call_range`.
  Their nameplates only show once hurt (`Nameplate.only_when_hurt`). Sheet `art/goblin.png` from
  `tools/pack_goblin.py` (Rex's pixellab frames in `art/goblin_src/`). Placed by keeping out of the
  forests, rock and everything west of x 7600 (the village). The punch is quick (lands 0.12 s in) and
  the goblin keeps running at you while it swings, so walking away doesn't dodge it (Rex: they
  couldn't hit a moving player before).
- Enchanted village (Rex picked the spot): between the troll pass and the big clearing, about
  x 6600..7300, y -350..690; the forests were cut back to open it (EnchForestNorth / South). First
  building: the enchanted potion shop (`scenes/ench_potion_shop.tscn`, Rex's 256 px stump drawn at
  0.5 scale, door at its origin, at 6960, 188) -> interior `scenes/interior_ench_potion_shop.tscn`
  (Interiors at 2400, 3000; keeper "Briar" uses Mirelle's art for now and the same potion stock).
  Rex's originals in `art/ench_potion_src/`; the room's see-through floor and counter top were filled
  by `tools/fill_room_planks.py` (draws its own planks, for rooms with no seams left).
  Second: the enchanted wizard shop (`scenes/ench_wizard_shop.tscn`, same 0.5 scale, at 6800, 184)
  -> `scenes/interior_ench_wizard_shop.tscn` (Interiors at 2800, 3000; keeper "Mossbeard", Rex's
  pixellab wizard `art/ench_wizard_keeper.png`, sells the wizard shop's stock). Originals in
  `art/ench_wizard_src/`. Both rooms have a counter overlay (`art/interior_ench_*_counter.png`,
  only the counter and what stands on it) so the keeper stands behind the counter.
- Bindstones (Rex's crystal stalagmites, one per village; `scripts/bindstone.gd`, scenes
  `bindstone_village.tscn` "Espenhal" at 410, 214 and `bindstone_enchanted.tscn` "Enchanted Village" at
  6880, 292; art `art/bindstone_*.png` trimmed from `art/bindstone_src/`, drawn at 0.5). F opens the
  DialogueUI: BIND HOME HERE (saved "home_bind"; respawn and home recall H go to `spawn_spot()`, loaded by
  `Player._load_home_bind`) and TELEPORT to any other stone you've found ("bindstones_found": walking
  within `find_range` finds it), via `world.teleport_to`. `stone_id` is the save key: never rename it.
  New village: instance a bindstone scene with a new stone_id / display_name. DialogueUI buttons wrap
  onto more rows when there are many.
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
  and when a yank gives fresh speed (Rex asked for that reset to be bulletproof). Each jump on carried speed also keeps only `jump_speed_keep` of it (Rex: 0.95,
  5% per jump; was 0.8, long-distance hopping had been too strong). A jump keeps the part of your speed pointing where you jump
  (at least walking speed if moving); no steering in the air; walls soak up what hits them.
  Momentum skills push the player through `Player.yank_to` (and later more like it). Planned: a
  wind gust cast on the ground that you walk into.
- Staff spells: besides left click, a staff can have up to 3 more spells (`Item.spells`), cast
  with Q / E / R (actions `staff_spell_1..3`, rebindable; `BasicAttack.cast_staff_spell`). They show
  in a 3-slot row right above hotbar slots 1-3 (`hotbar_ui.gd`, with cooldown shading; click
  casts). That bar only ever shows the equipped staff's own spells: no items or other skills
  can be dropped on it (Rex's rule). Yank Line icon: `art/icons.png` slot 7 (`tools/add_yank_icon.py`). Rex's
  plan: several colour-coded spells per staff, each staff with its own theme. First: the
  Linecaster Staff (Astral Staff art), purple-rope theme modelled on a MICLIC line charge (no
  rocket): Q = Yank Line (`scripts/line_yank.gd` / `scenes/spells/line_yank.tscn`), a grapple
  that must NOT look like a grapple: the line is flung, lies loose and wiggly, snaps tight and
  yanks you to its tip. Space during the yank hops out at full speed.
- Gear enhancing (staffs only for now, +0 to +15): the anvil in the blacksmith (`scripts/anvil.gd`,
  F opens `scripts/enhance_ui.gd`: item square, elixir + flux squares, progress bar, Enhance button;
  click / drag bag items onto it). Rules with no UI in `scripts/enhance.gd` (success chance per
  level in CHANCE, 1 Magical Elixir + 1 Flux per attempt, failure keeps the level). Each level
  raises the staff's damage range by `Item.ENHANCE_BONUS` percent of its base (small steps to +7,
  big from +8, double at +15). An enhanced item
  is its own copy (`Item.enhanced_copy`, `Item.enhance`, `Item.title()` = "+5 Name"), saved as
  "<path>#+<level>" by `SaveGame.item_to_path` / `item_from_path`. Flux (`items/flux.tres`, 1000
  coins) is sold by the blacksmith "Smith" (`art/blacksmith_keeper.png`, behind the counter; the room is
  Rex's 128x128 generated one, its floor came back see-through and was repainted by
  `tools/fill_room_floor.py` from `art/interior_src/`; the counter is redrawn on top as
  `art/interior_blacksmith_counter.png` so Smith stands behind it); the Magical
  Elixir (`items/magical_elixir.tres`) drops from every monster at 5% (`Loot.ELIXIR_CHANCE`, added
  in `Loot.roll`). Item pictures from Rex go in `art/item_src/` -> `tools/add_item_icons.py name:frame`.
- Damage (Rex chose MMO-style, Oct 2026): each staff has a damage range (`Item.damage_min/max`,
  tooltip "MAGIC DAMAGE 34-46"); a staff spell does `Ability.weapon_percent` of one roll of it per
  hit (`Ability.hit_damage`; basic beams 100%, Sun Halo 240%, Clockwork Spider 184%, Void Hole 62.5%
  a tick; multi-hit spells roll once per cast), then Intelligence (`Stats.magic_mult`) and the
  target's `Stats.armour` (armour / (armour + 100) less; monsters are all 0 for now). Spells with
  weapon_percent 0 (the hotbar spells) still use their fixed `damage`.
- Staff tiers (Rex, Oct 2026: wider gap + level requirements). `Item.level_req`, enforced by
  `Equipment.can_wear` in `equip_from` (also from the hotbar); tooltips add "REQUIRES LEVEL N" (red
  when too low), the shop shows "Lv N". Average damage grows like monster health
  (15 x (1 + 0.25 x (level - 3)), the skeleton / troll health scaling), so time-to-kill stays flat:
  Wooden 13-17 (none), Vorly's 20-26 (5), Amber 36-46 (10), Clockwork 43-55 (12), Amethyst 53-67 (15),
  Astral + Linecaster 63-79 (18), Twilight 70-88 (20), Void 77-95 (22), Sun 87-108 (25).
  Already-worn gear isn't taken off if you're under its level. Test: chat `/level N`.
- Potions: 4 sizes each of health and mana (small 75 / normal 150 / large 300 / huge 600; the normal
  ones are the old `health_potion` / `mana_potion`), all sold at the potion shop. Art: Rex's 4 bottles
  in `art/item_src/potion_src/`, recoloured to one red and one blue palette by
  `tools/recolor_potions.py` (RED / BLUE ramps). Items with the same `Item.use_group` share a use
  cooldown (all health potions, all mana potions).
- Keep the gear-fitting pipeline (below) for future wizard-style armour that isn't a robe.
- New staffs are a single upright picture: `tools/add_staff.py <id> <png> <icon_frame>` keeps the
  original in `art/staff_src/`, trims it to `art/worn_<id>.png` and makes the tilted inventory
  icon; then write `items/<id>.tres` by hand (copy `amethyst_staff.tres`). `HeldWeapon` uses the
  whole picture when it isn't an old 120x160 worn sheet. `hold_scale` 0.77 = same pixel size as the
  character (Rex draws them about 50 px tall in an 80x80 canvas so they don't drag on the floor).
  Fine-detail staffs (Rex's test, the Astral Staff): drawn ~100 px tall, `hold_scale` 0.385 (half-size pixels).
  Spells leave from the orb, 4 picture px below the top; if the orb sits lower (under a spike or in a
  cage) set the item's `orb_from_top` (the Amethyst Staff uses 9).
- Left click is always a simple coloured beam (Rex, Oct 2026): every staff's `basic_attack` is a BEAM
  ability (sun_beam / void_beam / clockwork_beam for the three below); the special attacks are each
  staff's Q spell (`Item.spells[0]`), with longer cooldowns now that they come on top of the beam
  (Sun Halo 6 s, Void Hole 7 s, Clockwork Spider 6 s). Q icons: `art/icons.png` slots 8-10
  (`tools/add_spell_icons.py`).
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

## Windows and menus (Rex's reference: a classic MMO inventory, Oct 2026)
- Every window uses `scripts/ui_style.gd`: brushed-steel bevel frame, dark charcoal-blue inside,
  `UiStyle.window(c, rect, title)` = frame + title bar with the title centred (the close button,
  `CloseButton.attach`, sits in the title bar's right end); `well` (sunken area behind slot grids /
  text fields), `slot`, `tab` (blue when open), `button` (steel), `divider`, `thousands` ("25,558,069").
  New windows: use these, put content below `UiStyle.FRAME + UiStyle.TITLE_H` (11 units).
- Windows are movable (Rex): `CloseButton.attach` also adds `WindowDrag` (`scripts/window_drag.gd`), an
  invisible handle over the title bar; positions are saved per window name ("window_pos") and put
  back each time a window opens (after its own open() placed it); opening / clicking a window brings
  it to the front. Item tooltips and the dragged item are drawn by `TooltipUI` (`scripts/tooltip_ui.gd`,
  last in hud.tscn, z_index 100) so they're always in front: windows call `TooltipUI.show_tip(self, at,
  title, lines)` / `hide_tip(self)` (and `show_icon` / `hide_icon` for a dragged item) instead of
  drawing their own. Context menu z 90, Esc menu z 80, so windows moved to the front stay under them.
- Inventory window (`inventory_ui.gd`, B or P): 5 x 6 bag (Inventory.SLOT_COUNT 30, Rex chose one
  page), worn gear in a column on the right (weapon on top, then head, body, legs: drag in / out,
  double-click, right-click), the purse under it ("1,450 Gold"). The old Equipment window
  (paperdoll) is gone; its gear bonuses moved to the Stats window. Coins don't take a bag slot:
  `Inventory.gold` (the purse); count_of / add / remove / room_for with the coins item use it, so
  shops, quests and loot didn't change; it's saved as a last {"gold": n} entry of the bag snapshot,
  old saves' coin stacks move into it on load, and it drops into the gravestone on death.

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
  staff positions that the tool would overwrite. The south-facing jump (naked) uses Rex's hand-placed
  poses instead: `HoldStyle.jump_pose_south` / `jump_grip_south` / `jump_behind_south`; the robed
  south jump (7 frames) has its own (`robe_jump_pose_south` / `robe_jump_grip_south` / `robe_jump_behind_south`) (east / west
  jumps: `jump_pose_east` / `jump_pose_west`).
- `art/player_new.png` is trimmed from `art/gear_src/player_new_original.png` by
  `tools/trim_body.py`. Never edit the trimmed sheet directly; edit the map or the original.
- Admin/debug: F1-F4 keys and chat commands (`/help`) are kept on purpose for testing
  (listed in MIGRATION_NOTES.md to lock down before a server exists).
