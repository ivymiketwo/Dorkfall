class_name SleepRegions
extends Node
## Sleeping regions: monsters only think when a player is nearby.
##
## The world is split into square regions of REGION world px. Every region within
## `wake_radius` regions of any player is awake; monsters everywhere else are put to sleep
## (brain, regen and look all paused). Server work then grows with the number of places
## players are, not with the size of the map. Works the same with one player or many.
##
## Time still passes while asleep: when a monster wakes, its `slept(seconds)` is called so
## respawn countdowns catch up (a monster killed and left behind is back when you return).

const REGION := 512.0
## Regions around each player's region that stay awake (1 = 3x3: monsters 512-1024 px away
## from you are still thinking, well past any aggro or attack range).
@export var wake_radius := 1
## How often regions are re-checked, in game ticks (15 = 4 times a second at 60 ticks/s).
@export var check_every := 15

var _asleep := {}     ## monster instance id -> GameClock time it fell asleep


func _ready() -> void:
	_check.call_deferred()


func _physics_process(_delta: float) -> void:
	if GameClock.tick % check_every == 0:
		_check()


## True if a monster is asleep right now (for tests / debugging).
func is_asleep(monster: Node) -> bool:
	return _asleep.has(monster.get_instance_id())


func asleep_count() -> int:
	return _asleep.size()


static func region_of(p: Vector2) -> Vector2i:
	return Vector2i((p / REGION).floor())


func _check() -> void:
	var awake_regions: Array[Vector2i] = []
	for p in Players.all(get_tree()):
		awake_regions.append(region_of(p.global_position))
	for m in get_tree().get_nodes_in_group("monsters"):
		var r := region_of((m as Node2D).global_position)
		var awake := false
		for a in awake_regions:
			if absi(r.x - a.x) <= wake_radius and absi(r.y - a.y) <= wake_radius:
				awake = true
				break
		var id := m.get_instance_id()
		if awake and _asleep.has(id):
			var slept_for: float = GameClock.now - float(_asleep[id])
			_asleep.erase(id)
			_set_running(m, true)
			if m.has_method("slept"):
				m.slept(slept_for)
		elif not awake and not _asleep.has(id):
			_asleep[id] = GameClock.now
			_set_running(m, false)


func _set_running(m: Node, on: bool) -> void:
	m.set_physics_process(on)
	for part in ["Stats", "Look"]:
		var n := m.get_node_or_null(part)
		if n:
			n.set_physics_process(on)
			n.set_process(on)
