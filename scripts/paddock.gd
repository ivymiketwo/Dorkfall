@tool
class_name Paddock
extends Node2D
## A fenced field with cows wandering about in it (scenes/paddock.tscn).
##
## The fence is a rectangle `size` big with its top-left corner at this node, built from the
## wooden fence pieces of the crop field (decor.tscn, "wfence_a" / "wfence_side_a"), with an open
## gate in one side. It's built by itself, so in the editor you just move the node or change the
## numbers in the Inspector. Cows (scripts/cow.gd) wander inside, never into `keep_out` (in this
## node's local units, e.g. the barn) and never out through the gate.

const DECOR := preload("res://scenes/decor.tscn")
const COW := preload("res://scripts/cow.gd")
const STEP := 16.0                    # one fence piece
const GATE := 48.0                    # gate opening (between the two gate posts)

## The fence rectangle (world px), from this node's position.
@export var size := Vector2(448, 544):
	set(v):
		size = v
		_rebuild()
## Which side has the gate, and how far along that side it starts (world px, from the top or left).
@export_enum("north", "south", "west", "east") var gate_side := "east":
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
	var ny := int(round(size.y / STEP))
	# top and bottom rows (piece centres every 16 px)
	for side in ["north", "south"]:
		var y := 0.0 if side == "north" else size.y
		for i in nx:
			var x := STEP * (i + 0.5)
			if not _in_gate(side, x - STEP * 0.5, x + STEP * 0.5):
				_piece("wfence_a", Vector2(x, y))
	# left and right columns
	for side in ["west", "east"]:
		var x := 0.0 if side == "west" else size.x
		for i in range(1, ny + 1):
			var y := STEP * i
			if not _in_gate(side, y - STEP, y):
				_piece("wfence_side_a", Vector2(x, y))
	# the gate: two posts, the two halves swung open outwards
	var a := _gate_point(gate_at)
	var b := _gate_point(gate_at + GATE)
	_piece("wgate_post", a)
	_piece("wgate_post", b)
	var out := {"north": Vector2(0, -10), "south": Vector2(0, 10), "west": Vector2(-10, 0), "east": Vector2(10, 0)}[gate_side] as Vector2
	var leaf := "wgate_leaf_h" if gate_side in ["west", "east"] else "wgate_leaf_v"
	_piece(leaf, a + out)
	_piece(leaf, b + out)


func _gate_point(along: float) -> Vector2:
	match gate_side:
		"north": return Vector2(along, 0)
		"south": return Vector2(along, size.y)
		"west": return Vector2(0, along)
	return Vector2(size.x, along)


func _in_gate(side: String, from: float, to: float) -> bool:
	return side == gate_side and to > gate_at and from < gate_at + GATE


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
