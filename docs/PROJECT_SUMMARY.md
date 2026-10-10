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
  spawn is the crossroads just south of Luck, at (208, 256).
- **Farmland:** wheat fields full of Mangyangs.
- **Graveyard / cave:** skeletons, Lord Kilset (boss) in the cave.
- **Vorly's lair** (the dragon boss, north-east of the village).
- **West desert** (sand), then the **red-clay ravine**, a pass through the mountains made by
  `tools/gen_ravine.py` (needs about 5 GB of RAM). It funnels in from the west, runs as a long narrow
  canyon, and funnels out again on the east (a mirror of the west side). The unreachable inside of the
  mountains is left black on purpose. Five **Skeleton Wizards** stand in the ravine.
- **East desert:** open sand (same recipe as the west desert, see `docs/desert_texture.md`) with
  34 cacti, out to the map edge at x 6512. It has no monsters yet.

## 5. Monsters and bosses (current state)

| Monster | Level | Notes |
|---|---|---|
| **Mangyang** (Rex's hopping scarecrow) | 1 | 4-direction idle and a 7-frame hop (west = east mirrored); moves only while in the air. **Crow swarm attack:** 3 crows start circling at its feet and drift up its body (extra warning); 0.25 s later a dark circle appears under the target; 0.5 s in, a swarm of ~12 crows flies from the scarecrow and hits everyone in the circle at 1.25 s, then scatters; the circling crows spiral up off screen. 50 damage, starts an attack every 3.5 s. Quests "Pest Control" (10) and "Mangyang Menace" (15). |
| **Skeleton** | 3+ | Red lane telegraph, then a lunge. Quests "Bone Collector" (12) and "The Restless Dead" (20). |
| **Lord Kilset** (BoneLord) | boss | Skeleton brain at boss scale; boulder rain and stone walls in the cave. Base health 280 (doubled at Rex's request). |
| **Pirate Captain** | 17 | 7 along the coast; skeleton brain with the pirate look. |
| **Skeleton Wizard** | 20 | Rex's sprite (idle, walk, throw; 4 directions). Keeps its distance, backs away if you get close (walk plays in reverse), and throws a fireball every 1.8 s. A red circle appears under the target (no aim prediction); the fireball leaves his hand from the centre of the red pixels in the last throw frame that has any, and lands after 1.0 s. 80 damage, health 630, 30-70 coins. |
| **Vorly** (dragon, first boss) | boss | Rex's dragon sprite (idle, walk, melee, 4-direction sit, death animation). Telegraphed melee bite (100 damage), a red-orb circle attack, and a 6 s orb barrage (sits facing one way; small random scatter on each orb). Health 1000. Quest "Slay Vorly" from Luck (one time, 1000 gold reward). |

## 6. Player, abilities, items, pets

- **Player:** 48x48 sheet (idle, run, jump); gear is fitted onto every frame through Rex's
  **body-part map** (`art/gear_src/README.md`). The player is always a wizard (no classes, no melee or blocking, no iron armour). The gear-fitting tools stay for future wizard-style armour (bone armour, say).
  Never edit `art/player_new.png` directly, and never regenerate `data/hands.json`.
- **Abilities and attacks:**
  - **Fireball:** Rex's 8-direction sprite. The wind-up orb sits on the staff tip and is layered
    correctly (behind the head facing west/north). The cast sound starts on key press and the hit
    sound plays only on impact. Speed 215 px/s with 0.5 s cast; damage 40.
  - **Red beam:** 60 damage.
  - **Blue staff beam** (left click): 15 damage, 1 s cooldown, hold to keep firing.
  - **Ward** (hold right click or Q): a summoning circle under you and a glass orb around you, lit
    only on the side facing the mouse. Aimed hits from the side you face (120 degree arc): 50% stopped
    (gear `ward_bonus` adds to it, max 90%), costing 25% of the stopped damage in mana. Everything
    else (ground effects, aimed hits from the side or behind): 30% stopped, costing 50% of it in
    mana. The first 0.25 s is a parry against aimed hits you face (95% stopped, half thrown back).
    Holding drains 10 mana/s, halves your speed, and you can't attack, cast or hop. Out of mana:
    "WARD BROKEN", 1 s lockout. Poison ticks and hop costs ignore the Ward.
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
- The east desert has no monsters, road or landmarks yet.
- The pet could also get a shorter "loot must sit for 1 s" delay if wanted.
- Aim prediction is ready for future monsters Rex picks.
- Older items: the "Build Windows release" GitHub Action is untested; armour and helmet icons
  still need 48x48 art; an optional river could be re-added.
- Leftover file `audio/music_our_town.ogg` may still sit in Rex's local folder (unused).
