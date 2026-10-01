extends Node2D
## A shop interior: one room-sized picture plus invisible solid rectangles.
## The room lives far away from the town on the same map, and the player is
## teleported into it. Edit `solids` in the Inspector to move walls/furniture
## (each Rect2 is x, y, width, height in room pixels).

signal exit_requested(interior: Node2D)

@export var room_size := Vector2(224, 176)
## >= 0: the camera follows the player around the room (a big cave) with this
## much rock margin, instead of being pinned on a small shop.
@export var scroll_margin := -1.0
@export var solids: Array[Rect2] = []


func _ready() -> void:
	var body := StaticBody2D.new()
	add_child(body)
	for r in solids:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = r.position + r.size / 2.0
		body.add_child(cs)
	# NPCs join the y-sorted Entities layer so the player can walk in front of and behind them
	var entities := get_parent().get_parent().get_node_or_null("Entities")
	if entities:
		for c in get_children():
			if c is Npc:
				c.reparent.call_deferred(entities, true)
	$Exit.body_entered.connect(func(b: Node2D) -> void:
		if b.is_in_group("player"):
			exit_requested.emit(self))


func entry_position() -> Vector2:
	return to_global($Entry.position)


func room_center() -> Vector2:
	return to_global(room_size / 2.0)


## Camera limits while inside.
func camera_rect() -> Rect2i:
	if scroll_margin >= 0.0:
		var o := to_global(Vector2.ZERO)
		return Rect2i(Vector2i(o - Vector2(scroll_margin, scroll_margin)), Vector2i(room_size + Vector2(scroll_margin, scroll_margin) * 2.0))
	var c := room_center()
	return Rect2i(Vector2i(c - Vector2(160, 90)), Vector2i(320, 180))
