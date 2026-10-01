extends "res://scripts/interior.gd"
## A cave: an interior with an irregular wall outline. `ring` is the outline of
## the walkable floor (room units); it becomes thin wall segments so nothing can
## walk out of the cave.

@export var ring := PackedVector2Array()


func _ready() -> void:
	super._ready()
	add_to_group("cave")
	var segs := PackedVector2Array()
	for i in ring.size():
		segs.append(ring[i])
		segs.append(ring[(i + 1) % ring.size()])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segs
	var cs := CollisionShape2D.new()
	cs.shape = shape
	var body := StaticBody2D.new()
	body.add_child(cs)
	add_child(body)
