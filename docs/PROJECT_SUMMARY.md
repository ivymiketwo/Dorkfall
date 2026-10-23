# Dorkfall: project summary (as of 2026-10-10)

A handoff for a new Claude chat. Read this first, then `CLAUDE.md` (project rules) and
`MIGRATION_NOTES.md` (server-readiness) in the repo.

---

## 1. The project and how Rex works

- **What it is:** "Dorkfall", a top-down pixel-art game in **Godot 4.7.2** (GDScript), inspired by
  Heartwood Online. The long-term goal is a **small persistent online world (MMO)**, so new game
  rules must stay server-friendly and dupe-proof (see section 7).
- **Rex** makes the art (sprites, sounds) and directs the design. He is **not a programmer**:
  explain things in plain language and skip jargon.
- **Repo:** GitHub `ivymiketwo/Dorkfall`, branch `main` (a push prints a harmless "repository
  moved" notice).
- **How Rex plays:** a Git clone on his Windows PC with two launchers in the repo root:
  - `update_and_play.bat` pulls, re-imports and starts the game;
  - `update_and_edit.bat` pulls and opens the Godot editor.
  - They put back Godot's own automatic edits to `project.godot` (backup kept in
    `project.godot.local-backup`) and to `*.import` files before pulling, and retry once if the
    pull fails. `.gitattributes` keeps `project.godot` and `*.import` in LF line endings, which stops
    line endings alone from blocking an update.
  - **So the workflow is: change, test, commit, push to `main`.** Rex runs the launcher. Nothing
    has to be copied to his PC by hand any more.
- **Art from Rex:** he usually drops folders of PNG frames in `C:\Users\Inositol\Downloads\<name>`
  (named like `South_0001.png`, `East_0003 (1).png`, `Rotations_0001.png`). A chat linked to his PC
  can read them there. Otherwise ask him to zip and attach them, because pasted images arrive
  re-compressed.
  - "Rotations" files are 8 directions numbered 1-8 = S, SE, E, NE, N, NW, W, SW (so 0001 = south,
    0003 = east, 0005 = north, 0007 = west). Rex is only using N/S/E/W now.
  - The originals of every sprite we built are kept next to the sheet in a `*_src` folder with a
    `.gdignore`.
- **Testing:** headless Godot scripts for logic, and `xvfb-run ... --rendering-driver opengl3` for
  screenshots. Main scene: `scenes/game.tscn`, a wrapper that renders the world
  (`scenes/main.tscn`) at 640x360 in a SubViewport. The UI is lifted out and drawn at full window
  resolution.

## 2. Technical ground rules

- **Scale:** viewport 640x360, camera zoom 2. Tiles are 32 px art drawn at half scale (16 world px),
  so **1 art pixel = 0.5 world px = 1 screen pixel**.
- **Ground:** a big painting cut into 512 px squares (`art/ground/`, streamed by `GroundStream`). Edit
  it with `tools/ground_tiles.py` (`assemble()` / `split()`). The invisible tile layer
  (`scripts/world.gd`) only handles collision. The map runs from world x -1680 to 6512 and y -992 to 1696.
- **Monsters** are split into a **brain** (logic only, no visuals) and a **Look** node (all
  drawing and animation). Far-away monsters sleep (`SleepRegions`).
- **Telegraphed attacks** use `AttackTimeline` (when things happen, ticked on the physics tick),
  `AttackRules` (hit tests, `deal`), and `AttackGuard.bind(attack, caster)` (the attack vanishes if
  the caster dies).
- **Pixel-perfect rendering:** this took several rounds. The current, working setup is:
  - the camera is rounded to whole *screen* pixels (half a world px) every frame
    (`Player._place_camera()`);
  - `snap_2d_vertices_to_pixel` is on the game SubViewport (`scenes/game.tscn`);
  - **physics interpolation** is on (`project.godot`) for the player, pets and monsters. The
    `World` and `Game` roots are OFF; Player, pets and monster scene roots are ON; their
    `Sprite2D` is OFF so look scripts can pose it instantly. Teleports and respawns call
    `reset_physics_interpolation()`.
  - **Don't** use `snap_2d_transforms_to_pixel`. It snaps to whole *world* px, which made the
    player wobble and the pet flicker 2 px.
  - All of this is written up in `docs/desert_texture.md` ("Keep everything on the pixel grid").
- **Audio:** the `Sound` autoload has two volume channels, "SFX" (every sound player is routed to it
  automatically) and "Ambient" (nothing uses it yet). The Esc menu has a Sound page with an
  **Ambient sound** slider and a **Sound effects** slider, saved to `user://settings.cfg`. Music was
  added, then removed at Rex's request.

## 3. Rex's design rules (also in CLAUDE.md)

- **Difficulty = harder to play against, NOT spongier.** Keep time-to-kill roughly flat. Scale
  difficulty with shorter telegraphs, smaller openings to punish, better aim, more and mixed attacks,
  smarter movement and monster combinations. Rex dislikes Darkfall's "more health and damage"
  approach.
- **Aim prediction** (`AttackRules.predict`, e.g. a monster's `aim_lead`) exists but is **only used
  where Rex picks it**. It is not on by default.
- **Level-gap damage penalty** (`AttackRules.level_gap_mult`, applied in `Stats.take_damage`): the
  player deals full damage to monsters up to 3 levels above them, then 5% less per extra level
  (4 = 95%, 5 = 90%, ...), with a floor of **60%**.
- **Vorly (the first boss)** must stay easy to dodge just by moving.

## 4. World and areas (west to east)

- **West coast:** ocean, beach, Pirate Captains along the coast, and a **wooden dock** at the west end
  of the road (walkable, fishable).
- **Village:** Luck (quest NPC), the notice board, shops (fishing, potions, pets, wizard). The default
  spawn is the crossroads just south of Luck, at (208, 256). The wizard shop is Rex's stone tower
  (`art/bld_wizard_tower.png`, at the same scale as the other buildings, so bigger than them), and
  the potion shop is Rex's cottage (`art/bld_potion_cottage.png`), the pet shop his mossy stone
  cottage (`art/bld_pet_cottage.png`) and the fishing shop his slate-roofed shack
  (`art/bld_fish_shack.png`). The blacksmith (`art/bld_blacksmith.png`, painted smoke) and two
  houses (`bld_house_red.png`, `bld_house_shutters.png`, no interiors) are his too. The buildings
  are scattered loosely (Rex's layout, Oct 2026) along winding dirt lanes with rounded "desire path"
  corners and wheel ruts at every right-angle junction; there are no cobblestones any more. The
  lanes are painted by `tools/paint_village_roads.py` (edit its LANES / CORNERS and re-run; it starts
  from `art/ground_src/village_before_roads.png` and also marks the lanes on the minimap).
  The village pond was moved 176 px east (`tools/move_pond.py`); moving it means moving its
  collision ellipse (`world.gd`), WaterPond1, the ducks and the minimap too.
- **Trees:** the standard living trees (kinds oak, oak2, cherry, pine in `scripts/tree.gd`) use Rex's
  std_* set (round trees, two pines, a gnarled tree for the old cherry spots), each spot picking
  one look from its position; the burnt dead trees keep their old art.
- **Forests:** Rex's big trees (`art/trees_src/`, packed with darker copies into one picture
  `art/trees_atlas.png` by `tools/pack_trees.py`, which also writes the list in `scripts/tree_art.gd`)
  can be placed one by one (tree.tscn, the new kinds) or as a thick forest: `scenes/forest.tscn` /
  `scripts/forest.gd`, a Polygon2D outline drawn in the editor that fills itself with trees (also in
  the editor) and is solid in the game, swept up by `canopy_block` so you can't walk far in behind the
  treetops. Trees in front of you fade see-through; deeper trees use the darker copies. Kept cheap:
  one shared picture and no tinting, so a forest draws in a few batches; each forest hands
  ShadowLayer its whole shadow as one cached batch of triangles (group `forest`).
  Placed so far (Rex's map, Oct 2026): ForestNorth and ForestSouth in main.tscn, two big bands that
  close off the north and south of the west half of the map (the beach strip stays open). A cliff
  (`NW_CLIFF` in `tools/gen_ravine.py`) runs from the east mountains up to the top of the map,
  closing off the north-east corner of the meadow.
  - Shop interiors are one room picture plus invisible solid rectangles (`scripts/interior.gd`). The
    potion shop is Rex's generated room (128x128 world px, smaller than the other shops), built by
    `tools/gen_potion_interior.py`, which lays the old shop's floorboards under its transparent floor
    (sources in `art/interior_src`). Its painted cauldron gets live bubbles and steam from
    `cauldron.gd` with `draw_pot` off. The wizard shop is built the same way
    (`tools/gen_wizard_interior.py`: old stone bricks for the floor and back wall; its arched window
    is left see-through so the animated night sky `wiz_window.png` shows from behind). In both,
    the counter is also a separate y-sorted sprite (group `y_sorted`) that hides the keeper's feet.
    The fishing shop is Rex's generated room too (`tools/gen_fishing_interior.py`): its see-through
    floor is repainted as planks lined up with the seams left in the picture.
    The pet shop too (`tools/gen_pet_interior.py`): the little dragon idles in the left nest (Rex's
    10 frames, `art/pet_dragon_src`; the first frame holds 2 s) and the sleeping fat dragon
    (`pet_pen.png` without its straw) lies in the big nest.
- **Farmland:** wheat fields full of Mangyangs.
- **Graveyard / cave:** skeletons, Lord Placeholder (boss) in the cave.
- **Vorly's lair** (the dragon boss, north-east of the village).
- **Grass straight into the red clay** (the old west desert strip was removed and the original grass
  restored; the grass-to-clay edge is the same blotchy blend as clay-to-grey), then the **red-clay ravine**, a pass through the mountains made by
  `tools/gen_ravine.py` (paints in strips, about 3 GB of RAM). It funnels in from the west and runs
  as a long narrow canyon. The unreachable inside of the mountains is left black on purpose. Five
  **Skeleton Wizards** stand in the ravine.
- **Grey valley** (replaced the east desert): east of x ~4470 the ravine widens into a wide valley
  (walls traced from Rex's sketch, `VALLEY_TOP` / `VALLEY_BOTTOM`) of the same cracked ground in grey,
  out to the map edge at x 6512, with 10 rock outcrops (`OUTCROPS`, sizes from Rex's sketch; the
  ravine's pillar cliffs, one or two ledges) and dead trees, rocks and bones. 14 **Trolls** are
  spread across it (`Troll1..14` in `main.tscn`, kept clear of walls and props).

## 5. Monsters and bosses (current state)

| Monster | Level | Notes |
|---|---|---|
| **Mangyang** (Rex's hopping scarecrow) | 1 | 4-direction idle and a 7-frame hop (west = east mirrored); moves only while in the air. **Crow swarm attack:** 3 crows start circling at its feet and drift up its body (extra warning); 0.25 s later a dark circle appears under the target; 0.5 s in, a swarm of ~12 crows flies from the scarecrow and hits everyone in the circle at 1.25 s, then scatters; the circling crows spiral up off screen. 50 damage, starts an attack every 3.5 s. Quests "Pest Control" (10) and "Mangyang Menace" (15). |
| **Skeleton** | 3+ | Rex's 4-direction sprite (`art/skeleton_new.png`, 64 px cells: idle, 6-frame walk, 6-frame attack, 7-frame death; originals in `art/skeleton_src`, look `skeleton_new_look.gd`). Red lane telegraph (wind-up frames play over it), then a lunge with the punch frame. Quests "Bone Collector" (12) and "The Restless Dead" (20). |
| **Lord Placeholder** (BoneLord) | boss | Skeleton brain at boss scale; boulder rain and stone walls in the cave. Base health 280 (doubled at Rex's request). |
| **Pirate Captain** | 17 | 7 along the coast; skeleton brain with the pirate look. |
| **Skeleton Wizard** | 20 | Rex's sprite (idle, walk, throw; 4 directions). Keeps its distance, backs away if you get close (walk plays in reverse), and throws a fireball every 1.8 s. A red circle appears under the target (no aim prediction); the fireball leaves his hand from the centre of the red pixels in the last throw frame that has any, and lands after 1.0 s. 80 damage, health 630, 30-70 coins. |
| **Troll** | 22 | Rex's sprite with a stone club drawn in (`art/troll.png`, 96x92 cells, 7 x 16: idle 1 frame, 6-frame walk, 7-frame swing (Rex's throw frames), 7-frame death; built by `tools/gen_troll_club.py` from the originals in `art/troll_src`: the club is drawn fresh per frame from a table of fist position, angle, foreshortening and front/back layer). Brain `troll.gd` extends the skeleton wizard's (chase, leash, loot, respawn) but never backs off. Overhead club smash, club hits the ground 0.65 s into the swing: within 16 px it is a melee smash (red circle radius 14 where the club lands, 120 damage, every 1.6 s); further out (up to 95 px) the smash knocks a tumbling rock (`art/troll_rock.png`) from where the club hit at you (red circle radius 22 under you, lands 0.4 s later, 100 damage, every 2.4 s). No aim prediction. Damage +10% per level above 20, health 690, 40-90 coins. 14 in the grey valley. |
| **Vorly** (dragon, first boss) | boss | Rex's dragon sprite (idle, walk, melee, 4-direction sit, death animation). Telegraphed melee bite (100 damage), a red-orb circle attack, and a 6 s orb barrage (sits facing one way; small random scatter on each orb). Health 1000. Quest "Slay Vorly" from Luck (one time, 1000 gold reward). |

## 6. Player, abilities, items, pets

- **Player:** 48x48 sheet (idle, run, jump); gear is fitted onto every frame through Rex's
  **body-part map** (`art/gear_src/README.md`). The player is always a wizard (no classes, no melee or blocking, no iron armour). The gear-fitting tools stay for future wizard-style armour (bone armour, say).
  Never edit `art/player_new.png` directly, and never regenerate `data/hands.json`.
- **Abilities and attacks:**
  - **Fireball:** Rex's 8-direction sprite. The wind-up orb sits on the staff tip and is layered
    correctly (behind the head facing west/north). The cast sound starts on key press and the hit
    sound plays only on impact. Speed 215 px/s with 0.5 s cast; damage 40.
  - **Crimson Swarm** (`abilities/crimson_swarm.tres`, `scripts/crimson_swarm.gd`): 0.8 s cast with a
    red summoning circle under the player, the staff fires the Red Beam laser (visual only) up to a point
    40 px above the target; 15 missiles bloom up out of its tip like a flower (each spreads out on its own side, evenly round the clock, then curls back in) on
    glowing magic trails (no smoke: they're magic missiles), float and linger ~0.43 s at the top, slam down in ~0.15 s (each bit of
    trail fades 1.6 s after the missile passed, knot end first) onto 15 small circles (radius 6) in the tightest round packing
    (`PACK_15` pulled 6% tighter for a smidge of overlap, cluster radius ~26; the falls twist the cluster 65 degrees counter-clockwise) on the mouse (max 170 px away). Each circle hits what's in it for 15 damage and Rex's red flame
    bursts up (`art/crimson_flame.png`, 12 frames made from his drawing by
    `tools/gen_crimson_flame.py`; original in `art/crimson_flame_src`). 40 mana, 6 s cooldown.
    Placed once on bar 1 for older saves (`Hotbar.GRANT_ONCE`).
  - **Crimson Barrage** (`abilities/crimson_barrage.tres`, same script with `stream` on): instant cast.
    The laser fires to a knot 38 px above the caster that rides along with them for ~5 s, shooting one missile every
    0.5 s (10 in all); each shoots straight up out of the knot, then slams onto its own circle wherever the cursor
    is when it leaves (max 170 px from the caster). 20 damage per missile, 40 mana, 8 s cooldown.
    Placeholder icon (index 6).
  - **Red beam:** 60 damage.
  - **Blue staff beam** (left click): 15 damage, 1 s cooldown, hold to keep firing.
  - **Ward** (hold right click): a summoning circle under you and a glass orb around you, lit
    only on the side facing the mouse. Aimed hits from the side you face (120 degree arc): 50% stopped
    (gear `ward_bonus` adds to it, max 90%), costing 25% of the stopped damage in mana. Everything
    else (ground effects, aimed hits from the side or behind): 30% stopped, costing 50% of it in
    mana. The first 0.25 s is a parry against aimed hits you face (95% stopped, half thrown back).
    Holding drains 10 mana/s, halves your speed, and you can't attack, cast or hop. Out of mana:
    "WARD BROKEN", 1 s lockout. Poison ticks and hop costs ignore the Ward.
  - **Stats:** Intelligence (mana, magic damage) and Vitality (health). Stamina, sprint and
    Dexterity were removed; the bunnyhop is the fast way to move.
  - **Bunnyhop** ("Begone"): chain-hop health cost **set to 0 for testing** (was 35).
- **Sounds:** fireball cast and hit (30% quieter), ray swoosh on every beam, jump (half volume).
- **Economy:** sell items to vendors (right-click Sell while a shop is open; left-click shows the
  value). Fish: minnow 20, perch 50, bass 75, golden carp 100. Rules are in `Trade.sell` and
  dupe-safe.
- **Pet "Tiny Dragon"** (from the pet shop): Rex's 4-direction sprite at 80% size, smoothed movement.
  It fetches loot with 0.25 s between grabs and pauses 0.25 s after each grab before heading to the
  next pile. It's always drawn behind the player (its node sits 14 px above its feet; the shadow is
  offset to match).

## 7. Server-readiness (from MIGRATION_NOTES.md, short version)

Player actions are small commands. Game rules live in code with no UI; valuable state changes in one
place (`Inventory.transact`, `Trade`, `LootClaim`, `SaveGame.batch`). Visuals are separate from logic
(brain/look). `GameClock` provides fixed ticks and `Rng` provides seedable randomness. Debug F1-F4 keys
and chat commands (`/help`, `/xp`, `/gold`, `/heal`, `/time`, `/quests`, `/resetquests`,
`/resetcharacter`) are kept on purpose for testing and are listed for lockdown before a server
exists.

## 8. Open items / ideas not done yet

- Bunnyhop health cost is off for testing; restore it later (it was 35 per chained hop).
- The grey valley has trolls but no landmarks yet.
- The pet could also get a shorter "loot must sit for 1 s" delay if wanted.
- Aim prediction is ready for future monsters Rex picks.
- Older items: the "Build Windows release" GitHub Action is untested; armour and helmet icons
  still need 48x48 art; an optional river could be re-added.
- Leftover file `audio/music_our_town.ogg` may still sit in Rex's local folder (unused).
