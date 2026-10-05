# Migration notes: single player -> server

Working rule for new code: player actions are small commands ("cast slot 3", "buy item X"),
game rules live in code with no scenes/UI in it, valuable state (items, coins, chase flags)
changes in one place, and visuals are separate from logic.

## Already server-friendly
- `SaveGame` is the only place data is written (swap the backend later).
- `Stats.take_damage` is the single choke point for damage; the guard/parry hooks in there.
- `Loot.roll` (rules) vs `Loot.spawn` (drawing): monsters roll drops through it.
- **Vorly** is the model for monsters: `vordy.gd` is a brain with no visuals (state, threat targeting,
  spells, cast timers, loot, respawn timer); `vordy_look.gd` draws everything and listens to its signals.
  Works with many players: targets by threat, ignores dead players, `KillCredit` gives XP and chase
  rolls to everyone with a 5%+ share of the damage, and leashing home wipes the threat table.
- `Inventory` rule functions (`try_use`, `prepare_drop`, `room_for`, `take_unbound`, `snapshot`).
- `AttackRules`: pure hit tests + `deal` for boss/monster attacks.
- `Trade.buy`: shop purchase rules, no UI. The shop window only shows the message.
- `Trade.sell(inv, shop, item, amount)`: selling to a vendor, no UI. Price comes from `Item.sell_price`
  (or a quarter of the shop price if unset; coins / account-bound never sell), never from the request; amount is clamped to what the bag
  holds; items out + coins in are one `Inventory.transact` with a before/after ledger check. On a
  server this runs server-side per request (also check the player is next to that shopkeeper, and
  rate-limit requests); the client just shows the returned message.
- `UniqueDrop.roll` and the account chase flags (`Item.account_has/mark_account`).
- `Attributes`: stat points, pools and damage % computed in one class, applied to `Stats`.
- `Experience.kill_xp` / `xp_to_next`: pure functions.

- `Player` input adapter: only `_gather_input` reads keys/mouse (`input_dir`, `input_sprint`,
  `input_guard`, `aim_world`); movement, casting, melee, guard and home-teleport read those values.
- `Stats` has no visuals: it emits `damaged` / `out_of_mana`, `StatsFx` draws them (`show_effects`).
- `Rng`: drops, unique drops and monster spell picks use it (seedable, server-ownable).
- `Inventory.transact`: all-or-nothing changes (used by `Trade.buy`).

- **Chat commands** live in `ChatCommands` (rules, no UI). One switch, `ChatCommands.ENABLED` / `can_use(player)`, turns them all off for multiplayer; later `can_use` checks the account role (admin / GM). `ChatLog` only types and displays.

- **Every monster is brain + look now.** `skeleton.gd` (also Lord Kilset and the Pirate Captain) and
  `mangyang.gd` draw nothing; `skeleton_look.gd`, `pirate_look.gd` and `mangyang_look.gd` do. Death and
  respawn are counted in the brain on the game tick (no tweens driving rules). Monsters target the
  nearest *living* player. Quests read each monster's `quest_kind` instead of its script name.
- **Attack timelines**: `AttackTimeline` lists when an attack hits ("at 0.7 s", "from 0.9 s to 1.06 s")
  and every attack ticks it from `_physics_process`; drawing only reads the time. Random timing that
  matters (when each boulder lands, when each stone stripe erupts) is rolled by the monster through `Rng`
  and handed to the attack. The fireball's splash damage and "who can hurt whom" are in `AttackRules`.
- **Ground loot**: `LootClaim.claim` is the only way items leave a pile: the pile must still have items,
  the taker must be within reach, and monster loot belongs to the top damage dealer for 60 s.
  Grab pets go through it too. Gravestones: `Gravestone.take_into` (owner only, from up close).
- **Pets**: `Pet.summon` / `pet.recall` are the rules; pets remember their owner. The pet list and the
  bag change in ONE save, so a pet can never be both out and in the bag.
- **Saving**: `SaveGame.batch` groups changes into one write (bag + gravestone, pet + bag, death), and
  every write goes to a temp file that is then swapped in, so a crash can't leave half a save.
- **Time**: `GameClock` (autoload) counts fixed physics ticks. Hotbar, melee and item cooldowns are
  "ready at" times on it; regen, poison, guard/parry, home teleport, casting and fishing bites run on
  the fixed tick. Vorly's cast timers count in physics ticks.
- **Movement**: every movement tick is numbered (`move_seq`) and remembered (velocity + end spot);
  `player.reconcile(seq, server_pos)` snaps to the server's answer and replays the later ticks.
- **Randomness**: monster wandering, skeleton boss attack layouts, fish rolls and bite timing go through `Rng`.

## Still to do (needs the actual server)
1. **Networking itself**: sending player commands up and state down. The pieces above are the
   hooks for it (commands, numbered movement ticks, rule functions that return results).
2. **Accounts**: pickups, pets and gravestones use the player's node / name as the owner for now;
   swap those for an account id.
3. **Fishing minigame**: the catch bar is pure skill and runs on the client; a server would only
   trust a "caught" result within sensible timing.
4. **Save file per player**: SaveGame is one file for one player; a server needs a database row per account.

