class_name SpellRotation
extends RefCounted
## A boss's own spell list and cooldowns. Every boss creates its OWN instance,
## so nothing is shared between bosses, and none of it touches the player's
## hotbar cooldowns.
##
##   rotation = SpellRotation.new(3.0)                     # 3 s global cooldown
##   rotation.add("slam", 150.0, _start_slam)              # name, range, what to do
##   rotation.add("bomb", 200.0, _throw_bomb, 2.0, 6.0)    # weight 2, own 6 s cooldown
##   ...each physics frame:   rotation.tick(delta)
##   ...when he may cast:     rotation.try_cast(distance_to_target)
##
## try_cast rolls at random (weighted) among spells that are in range and off
## their own cooldown, and starts the global cooldown.

var global_cooldown: float
var _global_timer: float
var _spells: Array[Dictionary] = []


func _init(global_cd := 3.0, first_delay := -1.0) -> void:
	global_cooldown = global_cd
	_global_timer = global_cd if first_delay < 0.0 else first_delay


## `own_cooldown` is optional (0 = none): a per-spell cooldown on top of the global one.
func add(spell_name: String, cast_range: float, action: Callable, weight := 1.0, own_cooldown := 0.0) -> void:
	_spells.append({"name": spell_name, "range": cast_range, "action": action,
			"weight": weight, "cd": own_cooldown, "timer": 0.0})


func tick(delta: float) -> void:
	_global_timer -= delta
	for s in _spells:
		s["timer"] -= delta


func ready() -> bool:
	return _global_timer <= 0.0


## Casts one spell at random if the global cooldown is up. Returns the spell's
## name, or "" if nothing was cast (on cooldown, or nothing in range).
func try_cast(dist: float) -> String:
	if _global_timer > 0.0:
		return ""
	var options: Array[Dictionary] = []
	var total := 0.0
	for s in _spells:
		if dist <= s["range"] and s["timer"] <= 0.0:
			options.append(s)
			total += s["weight"]
	if options.is_empty():
		return ""
	var roll := Rng.randf() * total
	var pick := options[options.size() - 1]
	for s in options:
		roll -= s["weight"]
		if roll <= 0.0:
			pick = s
			break
	_global_timer = global_cooldown
	pick["timer"] = pick["cd"]
	pick["action"].call()
	return pick["name"]
