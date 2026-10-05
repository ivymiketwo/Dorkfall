class_name Loot
extends RefCounted
## Monster drops, split so the rules can move to a server later:
##   Loot.roll(entries)  - pure rules. No scenes, no nodes. Returns what dropped.
##   Loot.spawn(...)     - only draws the result as pickups on the ground.
##
## An entry is a Dictionary:
##   item: Item, min: int, max: int, chance: float (default 1.0),
##   x: [lo, hi] and y: sideways/down offset from the monster (defaults to a small scatter).

const PICKUP := preload("res://scenes/pickup.tscn")


static func entry(item: Item, count_min := 1, count_max := 1, chance := 1.0, x := Vector2(-4, 4), y := 4.0) -> Dictionary:
	return {"item": item, "min": count_min, "max": count_max, "chance": chance, "x": x, "y": y}


## Returns [{item, count, offset}] for the entries that dropped.
static func roll(entries: Array) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		if e.get("item") == null:
			continue
		if float(e.get("chance", 1.0)) < 1.0 and not Rng.chance(float(e["chance"])):
			continue
		var x: Vector2 = e.get("x", Vector2(-4, 4))
		out.append({
			"item": e["item"],
			"count": Rng.randi_range(int(e.get("min", 1)), int(e.get("max", 1))),
			"offset": Vector2(Rng.randf_range(x.x, x.y), float(e.get("y", 4.0))),
		})
	return out


## `killed` (the dead monster's Stats) decides who owns the piles for a while (see LootClaim).
static func spawn(parent: Node, at: Vector2, drops: Array, killed: Stats = null) -> void:
	var owner := LootClaim.owner_for(killed)
	for d: Dictionary in drops:
		var p: Pickup = PICKUP.instantiate()
		p.monster_loot = true
		p.owner_id = owner
		p.public_at = GameClock.now + LootClaim.OWNER_LOCK
		p.item = d["item"]
		p.count = d["count"]
		p.position = at + d["offset"]
		parent.call_deferred("add_child", p)
