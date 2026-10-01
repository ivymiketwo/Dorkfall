class_name KillCredit
extends RefCounted
## Who gets credit when a monster dies, with no scenes or visuals in it.
## Everyone who did a real share of the damage (MIN_SHARE of the total) is "eligible":
## each gets full XP and their own roll at a chase drop, so grouping up never costs anyone.
## The loot pile itself drops once, for the top damage dealer.

const MIN_SHARE := 0.05


## Eligible players, biggest damage first. Falls back to the last attacker if that was a player.
static func eligible(stats: Stats, min_share := MIN_SHARE) -> Array[Node]:
	var total := 0.0
	for id in stats.contributions:
		total += float(stats.contributions[id])
	var rows: Array = []
	for id in stats.contributions:
		var n := instance_from_id(id) as Node
		if n == null or not is_instance_valid(n) or not n.is_in_group("player"):
			continue
		if total > 0.0 and float(stats.contributions[id]) / total >= min_share:
			rows.append([n, float(stats.contributions[id])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array[Node] = []
	for r in rows:
		out.append(r[0])
	if out.is_empty() and stats.last_source != null and is_instance_valid(stats.last_source) \
			and stats.last_source.is_in_group("player"):
		out.append(stats.last_source)
	return out


## Gives XP and chase-drop rolls to everyone eligible. Returns them (top dealer first).
static func award(stats: Stats, mob_level: int, xp: int, at: Node2D, unique_item: Item, unique_chance: float) -> Array[Node]:
	var who := eligible(stats)
	for p in who:
		Experience.grant_kill(p, mob_level, xp, at)
		UniqueDrop.roll(p, unique_item, unique_chance)
	if at != null:
		Quests.on_kill(who, at)
	return who
