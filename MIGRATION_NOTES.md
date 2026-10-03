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

## Still to split
1. **Monster AI for `skeleton` and `mangyang`**: same brain/look split as Vorly (they already use
   `KillCredit`, but their AI still mixes in sprite code and visual tweens). Copy the Vorly pattern.
2. **Attack timelines**: the hit rules are in `AttackRules`, but each attack node still runs its own
   warn/sweep timer and is spawned by the monster script. `fireball.gd` still does its own blast test.
3. **Pickups and gravestones** add to the bag directly and are collected client-side.
4. **Pets**: follow logic and loot-grab run client-side. Needs pet records with a server-owned
   "summoned" flag and recall.
5. **Movement**: input is separated, but the body still moves locally (needs prediction + reconciliation).
6. **Time**: cooldowns and regen count frames in nodes; a server tick replaces that.
7. **Random placement inside monster scripts** (e.g. where boulders land in `skeleton.gd`) still uses
   plain `randf`.
