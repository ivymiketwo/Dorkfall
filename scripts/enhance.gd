class_name Enhance
extends RefCounted
## Gear enhancing rules, with no UI in them so a server can run the same checks (like Trade).
## The anvil window (enhance_ui.gd) only shows what these return.
##
## One attempt takes the item to the next level (+0 -> +1 ... up to +15). Every attempt uses up
## ELIXIRS Magical Elixirs and FLUX Flux whether it works or not; a failed attempt changes nothing
## else (no downgrades yet). Only staffs can be enhanced for now (Item.can_enhance). Each level raises
## the staff's damage range (Item.ENHANCE_BONUS, Item.damage_range).

const MAX_LEVEL := Item.MAX_ENHANCE
const ELIXIR_PATH := "res://items/magical_elixir.tres"
const FLUX_PATH := "res://items/flux.tres"
static var ELIXIR: Item:
	get: return load(ELIXIR_PATH)
static var FLUX: Item:
	get: return load(FLUX_PATH)
## Materials used per attempt.
const ELIXIRS := 1
const FLUXES := 1
## Chance that an attempt FROM each level works: index 0 = going +0 -> +1, ..., 14 = +14 -> +15.
const CHANCE := [1.0, 0.95, 0.9, 0.85, 0.8, 0.7, 0.6, 0.5, 0.45, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1]


## Chance (0..1) that enhancing an item at `level` works.
static func chance(level: int) -> float:
	return CHANCE[level] if level >= 0 and level < CHANCE.size() else 0.0


## Why `item` can't be enhanced right now with what's in `inv` ("" = it can).
static func blocked_reason(inv: Inventory, item: Item) -> String:
	if item == null:
		return "Place a staff on the anvil"
	if not item.can_enhance():
		return "Only staffs can be enhanced"
	if item.enhance >= MAX_LEVEL:
		return "Already at +%d" % MAX_LEVEL
	if inv == null or inv.items.find(item) == -1:
		return "The staff must be in your bag"
	if inv.count_of(ELIXIR) < ELIXIRS:
		return "You need a Magical Elixir"
	if inv.count_of(FLUX) < FLUXES:
		return "You need Flux"
	return ""


## One enhancing attempt on `item` (the very item in the bag). Returns
## {"ok": bool, "success": bool, "item": the item now in that slot, "message": String}.
## Dupe-safe: the materials leave and the new item goes in within ONE all-or-nothing transaction,
## and nothing the player sends is trusted (the level and the roll come from here).
static func attempt(inv: Inventory, item: Item) -> Dictionary:
	var why := blocked_reason(inv, item)
	if why != "":
		return {"ok": false, "success": false, "item": item, "message": why}
	var level := item.enhance
	var works := Rng.chance(chance(level))
	var result := {"item": item}
	var done := inv.transact(func() -> bool:
		var slot := inv.items.find(item)
		if slot == -1:
			return false
		if not inv.remove(ELIXIR, ELIXIRS) or not inv.remove(FLUX, FLUXES):
			return false
		if works:
			var up := item.enhanced_copy(level + 1)
			inv.replace_slot(slot, up, 1)
			result["item"] = up
		return true)
	if not done:
		return {"ok": false, "success": false, "item": item, "message": "Could not enhance"}
	var now: Item = result["item"]
	if works:
		return {"ok": true, "success": true, "item": now, "message": "Success!  %s" % now.title()}
	return {"ok": true, "success": false, "item": now, "message": "Failed. The staff stays +%d" % level}
