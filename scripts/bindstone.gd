class_name Bindstone
extends StaticBody2D
## A bindstone: the magic crystal rock in each village. Walk up and press F:
##  - BIND HOME HERE: you come back to this stone when you die and when you recall home (H).
##  - TELEPORT: jump to another bindstone you have already found. A stone counts as found once
##    you've walked up to it (so you can't teleport somewhere you've never been).
## The rules are the static functions at the bottom (no UI in them), so a server can run the same
## checks; the talking box is the ordinary DialogueUI (get_dialogue / choose, like an NPC).

const SAVE_HOME := "home_bind"          ## id of the stone you're bound to
const SAVE_FOUND := "bindstones_found"  ## ids of the stones you've found
const PX := 0.5
const SPARKS := 7

## Unique name used in the save file. Never change it once players have bound to it.
@export var stone_id := "village"
@export var display_name := "Village"
@export var interact_range := 40.0
## How far you notice (and "find") the stone.
@export var find_range := 90.0
## Where the picture's crystals are (world px above the stone's feet), for the sparkles and glow.
@export var crystal_at := Vector2(0, -52)
@export var glow_color := Color(1.0, 0.85, 0.45)

var _near := false
var _t := 0.0
var _sparks: Array = []    # {p, v, age, life}


func _ready() -> void:
	add_to_group("bindstones")
	add_to_group("interactables")
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var player := Players.local(get_tree())
	if player:
		var d := global_position.distance_to(player.global_position)
		if d <= find_range:
			discover(stone_id)
		var near := d <= interact_range
		if near != _near:
			_near = near
	# little motes drifting up around the crystal (fine pixels: tiny glowing things, see CLAUDE.md)
	if _sparks.size() < SPARKS and randf() < delta * 4.0:
		_sparks.append({"p": crystal_at + Vector2(randf_range(-12, 12), randf_range(-8, 10)),
				"v": Vector2(randf_range(-2, 2), randf_range(-9, -4)), "age": 0.0, "life": randf_range(1.0, 2.2)})
	for s in _sparks:
		s["age"] += delta
		s["p"] += s["v"] * delta
	_sparks = _sparks.filter(func(s): return s["age"] < s["life"])
	queue_redraw()


func _draw() -> void:
	# a soft pulsing light around the crystals
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	for k in 3:
		draw_circle(crystal_at, 10.0 + k * 6.0, Color(glow_color, (0.05 + 0.04 * pulse) / (k + 1)))
	for s in _sparks:
		var f: float = s["age"] / s["life"]
		var a := sin(f * PI)
		var p: Vector2 = (s["p"] as Vector2).snapped(Vector2(0.25, 0.25))
		draw_rect(Rect2(p, Vector2(0.5, 0.5)), Color(glow_color.lightened(0.5), a))
		draw_rect(Rect2(p + Vector2(-0.25, 0.125), Vector2(1.0, 0.25)), Color(glow_color, a * 0.5))
	# name, and the F prompt when you're close
	var top := crystal_at.y - 24.0
	var name_text := display_name.to_upper()
	HiFont.draw(self, Vector2(-floorf(HiFont.text_width(name_text, PX) / 2.0), top - 7.0), name_text, Color("9ad0ff"), PX)
	if _near:
		var t := "F  BINDSTONE"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), top), t, Color("f0d040"), PX)


func interact(player: Node2D) -> void:
	discover(stone_id)
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui:
		ui.open(self, player)


## Where you appear when you come to this stone: just in front of it.
func spawn_spot() -> Vector2:
	return global_position + Vector2(0, 16)


# ---- talking box (DialogueUI)

func get_dialogue(player: Node2D) -> Dictionary:
	var bound := home_id() == stone_id
	var text := "The bindstone hums with old magic. " + \
			("Your home is bound to this stone." if bound else "Bind your home here, or travel to another bindstone you have found.")
	var buttons: Array = []
	if not bound:
		buttons.append({"id": "bind", "label": "BIND HOME HERE"})
	buttons.append({"id": "teleport", "label": "TELEPORT"})
	buttons.append({"id": "close", "label": "LEAVE"})
	return {"text": text, "buttons": buttons}


func choose(id: String, player: Node2D) -> Dictionary:
	if id == "bind":
		bind_home(player, self)
		return {"text": "Bound! You will return to %s when you fall, and when you recall home (H)." % display_name,
				"buttons": [{"id": "back", "label": "BACK"}, {"id": "close", "label": "THANKS"}]}
	if id == "back":
		return get_dialogue(player)
	if id == "teleport":
		var dest := destinations(get_tree(), stone_id)
		if dest.is_empty():
			return {"text": "You don't know any other bindstones yet. Find one and touch it, and you can travel to it from here.",
					"buttons": [{"id": "back", "label": "BACK"}]}
		var buttons: Array = []
		for s: Bindstone in dest:
			buttons.append({"id": "tp:" + s.stone_id, "label": s.display_name.to_upper()})
		buttons.append({"id": "back", "label": "BACK"})
		return {"text": "Where to?", "buttons": buttons}
	if id.begins_with("tp:"):
		var to := find_stone(get_tree(), id.substr(3))
		if to and can_teleport(stone_id, to.stone_id):
			var world := get_tree().get_first_node_in_group("world")
			if world and world.has_method("teleport_to"):
				world.teleport_to(to.spawn_spot())
		return {}     # closes the box
	return {}


# ---- rules (no UI)

## Marks a stone as found (saved). Found stones are where you can teleport to.
static func discover(id: String) -> void:
	var found = SaveGame.get_value(SAVE_FOUND, [])
	if not found is Array:
		found = []
	if not found.has(id):
		found.append(id)
		SaveGame.put(SAVE_FOUND, found)


static func is_found(id: String) -> bool:
	var found = SaveGame.get_value(SAVE_FOUND, [])
	return found is Array and found.has(id)


## Teleporting is allowed from a stone you're at to any other stone you've found.
static func can_teleport(from_id: String, to_id: String) -> bool:
	return from_id != to_id and is_found(from_id) and is_found(to_id)


static func find_stone(tree: SceneTree, id: String) -> Bindstone:
	for s in tree.get_nodes_in_group("bindstones"):
		if s is Bindstone and s.stone_id == id:
			return s
	return null


## The other stones you can travel to from `from_id`, in the order they sit in the world.
static func destinations(tree: SceneTree, from_id: String) -> Array:
	var out: Array = []
	for s in tree.get_nodes_in_group("bindstones"):
		if s is Bindstone and can_teleport(from_id, s.stone_id):
			out.append(s)
	return out


static func home_id() -> String:
	return str(SaveGame.get_value(SAVE_HOME, ""))


## Binds `player`'s home to `stone`: respawn and home recall go there from now on (saved).
static func bind_home(player: Node2D, stone: Bindstone) -> void:
	SaveGame.put(SAVE_HOME, stone.stone_id)
	player.set("_spawn_point", stone.spawn_spot())


## On load: where the saved bind puts the player's home (null = no bind yet, keep the start).
static func home_spot(tree: SceneTree) -> Variant:
	var s := find_stone(tree, home_id())
	return s.spawn_spot() if s else null
