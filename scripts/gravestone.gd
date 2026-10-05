class_name Gravestone
extends Node2D
## Left behind when the player dies, holding everything they were carrying and wearing.
## Walk up and press F to loot it. Whatever doesn't fit in your inventory stays on the
## stone until you make room. It crumbles once it's empty.

@export var interact_range := 30.0

const PX := 0.5

var owner_name := "Rex"
var loot: Array = []            # [{"item": Item, "count": int}, ...]
var _near := false

static var _restoring := false


## Writes every gravestone in the world to the save file.
static func save_all(tree: SceneTree, exclude: Gravestone = null) -> void:
	if _restoring:
		return
	var out := []
	for n in tree.get_nodes_in_group("gravestones"):
		var g := n as Gravestone
		if g == null or g == exclude or g.is_queued_for_deletion():
			continue
		var loot_out := []
		for e: Dictionary in g.loot:
			var p := SaveGame.item_to_path(e.item)
			if p != "":
				loot_out.append({"item": p, "count": e.count})
		out.append({"x": g.position.x, "y": g.position.y, "owner": g.owner_name, "loot": loot_out})
	SaveGame.put("gravestones", out)


## Recreates saved gravestones under `parent` (call once when the world loads).
static func restore(parent: Node) -> void:
	var saved = SaveGame.get_value("gravestones")
	if not saved is Array:
		return
	_restoring = true
	for d in saved:
		if not d is Dictionary:
			continue
		var g := Gravestone.new()
		g.name = "Gravestone"
		g.owner_name = str(d.get("owner", "Rex"))
		for e in d.get("loot", []):
			var it := SaveGame.item_from_path(str(e.get("item", "")))
			if it:
				g.add_loot(it, int(e.get("count", 1)))
		if g.loot.is_empty():
			g.free()
			continue
		g.position = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
		parent.add_child(g)
	_restoring = false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("gravestones")
	Gravestone.save_all(get_tree())
	# pops up out of the ground
	scale = Vector2(1.0, 0.1)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func add_loot(item: Item, count: int) -> void:
	loot.append({"item": item, "count": count})


func _process(_delta: float) -> void:
	var player := Players.local(get_tree())
	var near := player != null and global_position.distance_to(player.global_position) <= interact_range
	if near != _near:
		_near = near
		queue_redraw()


## The rules of looting, with no visuals (a server runs this per request): only the owner,
## only from up close. Moves what fits into their bag and saves bag and stone in ONE write,
## so a crash can never leave an item in both. Returns {"taken_any": bool, "empty": bool, "reason": String}.
func take_into(player: Node2D) -> Dictionary:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or is_queued_for_deletion():
		return {"taken_any": false, "empty": false, "reason": "gone"}
	if global_position.distance_to(player.global_position) > interact_range + 4.0:
		return {"taken_any": false, "empty": false, "reason": "too_far"}
	if str(player.get("display_name")) != owner_name:
		return {"taken_any": false, "empty": false, "reason": "not_yours"}
	return SaveGame.batch(func() -> Dictionary:
		var taken_any := false
		for e: Dictionary in loot:
			var left := inv.add(e.item, e.count)
			if left != e.count:
				taken_any = true
			e.count = left
		loot = loot.filter(func(e: Dictionary) -> bool: return e.count > 0)
		Gravestone.save_all(get_tree(), self if loot.is_empty() else null)
		return {"taken_any": taken_any, "empty": loot.is_empty(), "reason": "" if loot.is_empty() else "full"})


func interact(player: Node2D) -> void:
	var r := take_into(player)
	var at := player.position + Vector2(0, -26)
	if r["empty"]:
		FloatingText.spawn(get_parent(), at, "LOOTED", Color("f0d040"))
		queue_free()
	elif r["reason"] == "not_yours":
		FloatingText.spawn(get_parent(), at, "NOT YOUR GRAVE", Color("e03c3c"))
	elif r["reason"] == "full":
		FloatingText.spawn(get_parent(), at, "INVENTORY FULL", Color("e03c3c"))
		if r["taken_any"]:
			queue_redraw()


func _draw() -> void:
	var o := Color("1f1a24")
	var stone := Color("a8a8b4"); var light := Color("c8c8d4"); var dark := Color("7a7a88")
	# shadow + mound of earth
	draw_rect(Rect2(-8, -1, 16, 3), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-8, -2, 16, 3), Color("5a3e26"))
	draw_rect(Rect2(-7, -3, 14, 2), Color("7a5634"))
	# tombstone: rounded top, outlined
	draw_rect(Rect2(-5, -15, 10, 13), o)
	draw_rect(Rect2(-4, -16, 8, 1), o)
	draw_rect(Rect2(-4, -15, 8, 12), stone)
	draw_rect(Rect2(-3, -16, 6, 1), stone)
	draw_rect(Rect2(-4, -15, 1, 12), light)
	draw_rect(Rect2(3, -15, 1, 12), dark)
	draw_rect(Rect2(-4, -4, 8, 1), dark)
	# cross
	draw_rect(Rect2(-1, -13, 2, 7), dark)
	draw_rect(Rect2(-3, -11, 6, 2), dark)
	# moss
	draw_rect(Rect2(-4, -5, 3, 1), Color("5a8a3a"))
	draw_rect(Rect2(-4, -6, 1, 1), Color("5a8a3a"))
	var name_text := (owner_name + "'S GRAVE").to_upper()
	HiFont.draw(self, Vector2(-floorf(HiFont.text_width(name_text, PX) / 2.0), -22), name_text, Color("c8c8d4"), PX)
	if _near:
		var t := "F  LOOT"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), -29), t, Color("f0d040"), PX)
