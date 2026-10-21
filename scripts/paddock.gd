@tool
class_name Paddock
extends Node2D
## A fenced field with cows wandering about in it (scenes/paddock.tscn).
##
## The fence is a rectangle `size` big with its top-left corner at this node, built from Rex's
## ranch fence pieces (cut by tools/cut_fence.py: decor kinds "rfence_*", and the up-and-down
## pieces made here), with an open gate in the top or bottom side. It's built by itself, so in the editor you just move the node or change the
## numbers in the Inspector. Cows (scripts/cow.gd) wander inside, never into `keep_out` (in this
## node's local units, e.g. the barn) and never out through the gate.

const DECOR := preload("res://scenes/decor.tscn")
const COW := preload("res://scripts/cow.gd")
const STEP := 16.0                    # one left-right fence piece
const SIDE_STEP := 16.0               # posts of the up-and-down sides
const GATE := 32.0                    # gate opening (between the two gate posts)
const SIDE_TEX := preload("res://art/rfence_side.png")

## The fence rectangle (world px), from this node's position.
@export var size := Vector2(448, 544):
	set(v):
		size = v
		_rebuild()
## Which side has the gate, and how far along that side it starts (world px, from the left;
## a multiple of 16).
@export_enum("north", "south") var gate_side := "north":
	set(v):
		gate_side = v
		_rebuild()
@export var gate_at := 256.0:
	set(v):
		gate_at = v
		_rebuild()
## How many cows live here.
@export var cows := 4
## Areas inside the fence the cows keep out of (local units), e.g. where the barn stands.
@export var keep_out: Array[Rect2] = []
## Change to get a different start for the cows.
@export var variation := 1

var _built: Node2D


func _ready() -> void:
	y_sort_enabled = true
	_rebuild()
	if not Engine.is_editor_hint():
		_spawn_cows()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _built:
		_built.queue_free()
	_built = Node2D.new()
	_built.y_sort_enabled = true
	add_child(_built, false, Node.INTERNAL_MODE_BACK)      # generated, never saved in the scene
	var nx := int(round(size.x / STEP))
	var ny := int(round(size.y / SIDE_STEP))
	var rng := RandomNumberGenerator.new()
	rng.seed = variation
	# top and bottom: a post with rails to its right every 16 px (the next post covers the ends)
	for side in ["north", "south"]:
		var y := 0.0 if side == "north" else size.y
		for i in nx:
			var x := STEP * i
			if side == gate_side and x >= gate_at and x < gate_at + GATE:
				continue
			var r := rng.randf()
			_piece("rfence_a" if r < 0.7 else ("rfence_b" if r < 0.85 else "rfence_c"), Vector2(x + STEP * 0.5, y))
	# left and right: a post every 32 px with the rails running down to the next one
	for x in [0.0, size.x]:
		for i in ny:
			_side_post(Vector2(x, SIDE_STEP * i))
	# big posts on the corners (added last, so they're drawn over the pieces they stand on)
	for c in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		_piece("rfence_corner", c)
	# the gate: a post on the left, the gate swung open on its post on the right
	var gy := 0.0 if gate_side == "north" else size.y
	_piece("rfence_post", Vector2(gate_at + 2.25, gy))
	_piece("rfence_gate_open", Vector2(gate_at + GATE - 2.75, gy))


## One post of an up-and-down side: picture anchored at the post's foot, the rails hanging down
## to the next post, and a thin solid strip along them.
func _side_post(at: Vector2) -> void:
	var b := StaticBody2D.new()
	b.position = at
	var s := Sprite2D.new()
	s.texture = SIDE_TEX
	s.centered = false
	s.offset = Vector2(-4.5, -31)
	s.scale = Vector2(0.5, 0.5)
	b.add_child(s)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(4, SIDE_STEP)
	cs.shape = r
	cs.position = Vector2(0, SIDE_STEP * 0.5 - 1.5)
	b.add_child(cs)
	_built.add_child(b)


func _piece(kind: String, at: Vector2) -> void:
	var d := DECOR.instantiate()
	d.kind = kind
	d.position = at
	_built.add_child(d)


## Where cows may stand: inside the fence (a little in from it) and outside `keep_out`.
func is_pasture(p: Vector2) -> bool:
	if not Rect2(Vector2(14, 12), size - Vector2(28, 18)).has_point(p):
		return false
	for r in keep_out:
		if r.has_point(p):
			return false
	return true


## A random spot cows may walk to.
func random_spot(rng: RandomNumberGenerator) -> Vector2:
	for i in 40:
		var p := Vector2(rng.randf_range(14, size.x - 14), rng.randf_range(12, size.y - 6))
		if is_pasture(p):
			return p
	return size * 0.5


## True if the straight walk from a to b stays on the pasture.
func clear_walk(a: Vector2, b: Vector2) -> bool:
	for i in range(1, 11):
		if not is_pasture(a.lerp(b, i / 10.0)):
			return false
	return true


func _spawn_cows() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = variation
	for i in cows:
		var c: Node2D = COW.new()
		c.name = "Cow%d" % (i + 1)
		c.paddock = self
		c.rng_seed = variation * 100 + i
		c.position = random_spot(rng)
		add_child(c)
