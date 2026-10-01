class_name Attributes
extends Node
## Intelligence / Strength / Dexterity. Everyone starts at 10; each level gives
## 2 points to spend. Base stats top out at 50; gear (and later elixirs) can push the
## total up to HARD_CAP.
##   Intelligence -> mana pool and magic damage
##   Strength     -> health pool and melee damage
##   Dexterity    -> stamina pool and ranged damage
## Pools: 400 at 10, +12.5 per point (900 at 50, about 1100 at 66).
## Damage: +2% per point above 10.

signal changed

const NAMES := ["int", "str", "dex"]
const LABELS := {"int": "Intelligence", "str": "Strength", "dex": "Dexterity"}
const START := 10
const BASE_CAP := 50
const HARD_CAP := 66
const POINTS_PER_LEVEL := 2
const POOL_BASE := 400.0
const POOL_PER_POINT := 12.5
const DMG_PER_POINT := 2.0

## Points spent on each stat (on top of START).
var spent := {"int": 0, "str": 0, "dex": 0}
## Temporary boosts, e.g. from elixirs: stat -> points.
var temp := {}

@onready var stats: Stats = get_parent().get_node("Stats")
@onready var xp: Experience = get_parent().get_node("Experience")
@onready var equipment: Equipment = get_parent().get_node("Equipment")


func _ready() -> void:
	var saved = SaveGame.get_value("attributes")
	if saved is Dictionary:
		for n in NAMES:
			spent[n] = clampi(int(saved.get(n, 0)), 0, BASE_CAP - START)
	# never more spent than earned (guards a hand-edited or old save)
	while _spent_total() > earned():
		for n in NAMES:
			if spent[n] > 0 and _spent_total() > earned():
				spent[n] -= 1
	xp.changed.connect(_refresh)
	equipment.changed.connect(_refresh)
	_refresh.call_deferred()


func earned() -> int:
	return POINTS_PER_LEVEL * (xp.level - 1)


func _spent_total() -> int:
	return int(spent["int"]) + int(spent["str"]) + int(spent["dex"])


func unspent() -> int:
	return earned() - _spent_total()


func base_of(stat: String) -> int:
	return START + int(spent[stat])


func bonus_of(stat: String) -> int:
	var b := int(equipment.total(stat + "_bonus")) + int(temp.get(stat, 0))
	return clampi(b, 0, HARD_CAP - base_of(stat))


func total_of(stat: String) -> int:
	return base_of(stat) + bonus_of(stat)


func pool_for(stat: String) -> float:
	return POOL_BASE + POOL_PER_POINT * (total_of(stat) - START)


func damage_percent(stat: String) -> float:
	return DMG_PER_POINT * (total_of(stat) - START)


func can_spend(stat: String) -> bool:
	return unspent() > 0 and base_of(stat) < BASE_CAP


func spend(stat: String) -> bool:
	if not can_spend(stat):
		return false
	spent[stat] += 1
	SaveGame.put("attributes", spent.duplicate())
	_refresh()
	return true


func _refresh() -> void:
	_set_pool("max_mana", pool_for("int"))
	_set_pool("max_health", pool_for("str"))
	_set_pool("max_stamina", pool_for("dex"))
	stats.attr_magic_percent = damage_percent("int")
	stats.attr_melee_percent = damage_percent("str")
	stats.attr_ranged_percent = damage_percent("dex")
	stats.changed.emit()
	changed.emit()


## Changes a pool's size. Someone who was full stays full; otherwise the current amount is kept.
func _set_pool(max_name: String, value: float) -> void:
	var cur_name := max_name.trim_prefix("max_")
	var was_full: bool = stats.get(cur_name) >= stats.get(max_name) - 0.01
	stats.set(max_name, value)
	stats.set(cur_name, value if was_full else minf(stats.get(cur_name), value))
