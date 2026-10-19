@tool
class_name Forest
extends Polygon2D
## A thick forest you draw in the editor, like a cliff face: nobody can walk into it.
##
## How to use (in the Godot editor, scene main.tscn):
##   1. Drag scenes/forest.tscn onto "Entities" (or add a child node of type Forest there).
##   2. With the forest selected, click the points of its outline in the 2D view (the polygon
##      editing buttons appear at the top of the 2D view).
##   3. The forest fills in by itself while you edit. Change "Kinds" to pick which trees grow in
##      it, "Spacing" to make it thinner or thicker, "Variation" for another random arrangement.
## In the game the outline is invisible and solid: you walk along the edge, under the trees.
## Trees fade to see-through while you stand behind them, so you never lose your character.

const EDGE_INSET := 5.0          # edge trees stand this far inside the outline (world px)
const MAX_TREES := 4000
const FADE_ALPHA := 0.35         # how see-through a tree gets when you're behind it
const DEEP := 90.0               # trees this far inside the outline are the darkest

## Which trees grow here (names from scripts/tree_art.gd). Repeat a name to make it more common.
@export var kinds: PackedStringArray = ["oak_dark", "oak_dark", "oak_round", "fir", "fir",
		"willow_mossy", "willow_teal", "willow_twisted", "pine_small", "twisted", "jungle"]
## Distance between trees (world px). Smaller = thicker forest.
@export_range(16.0, 90.0, 1.0) var spacing := 30.0
## Change to get a different random arrangement.
@export var variation := 1
## How far above the outline the forest is solid (world px). The treetops stick up a long way
## above the trunks; this keeps you from walking far in behind them on the forest's top side.
@export_range(0.0, 100.0, 1.0) var canopy_block := 48.0

var _trees: Node2D
var _key := ""
var _list: Array[Sprite2D] = []
var _bounds := Rect2()


func _ready() -> void:
	y_sort_enabled = true
	if not Engine.is_editor_hint():
		color = Color(0, 0, 0, 0)          # the outline itself is invisible in the game
		_make_wall()
	_build()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if _state() != _key:
			_build()
		return
	_fade(delta)


## Trees you're standing behind turn see-through; they come back when you leave.
func _fade(delta: float) -> void:
	var pl := Players.local(get_tree())
	if pl == null:
		return
	var p := to_local(pl.global_position) + Vector2(0, -10)        # the middle of the character
	var near := _bounds.grow(10.0).has_point(p)
	var k := minf(delta * 8.0, 1.0)
	for t in _list:
		var want := 1.0
		if near and t.position.y > p.y + 6.0 and Rect2(t.position + t.offset + Vector2(8, 6), t.texture.get_size() - Vector2(16, 6)).has_point(p):
			want = FADE_ALPHA
		if absf(t.modulate.a - want) > 0.01:
			t.modulate.a = lerpf(t.modulate.a, want, k)


func _state() -> String:
	return "%s|%s|%s|%s" % [polygon, kinds, spacing, variation]   # canopy_block only matters in game


## The solid part: the outline, swept upwards by canopy_block (the outline, the outline moved up,
## and the strip each edge sweeps through on the way; overlapping shapes are fine).
func _make_wall() -> void:
	if polygon.size() < 3:
		return
	var body := StaticBody2D.new()
	var up := Vector2(0, -canopy_block)
	var pieces: Array[PackedVector2Array] = [polygon]
	if canopy_block > 0.0:
		var moved := PackedVector2Array()
		for p in polygon:
			moved.append(p + up)
		pieces.append(moved)
		var n := polygon.size()
		for i in n:
			var a := polygon[i]
			var b := polygon[(i + 1) % n]
			if absf(b.x - a.x) > 0.5:
				pieces.append(PackedVector2Array([a, b, b + up, a + up]))
	for piece in pieces:
		var shape := CollisionPolygon2D.new()
		shape.polygon = piece
		body.add_child(shape)
	add_child(body)


func _build() -> void:
	_key = _state()
	if _trees:
		_trees.queue_free()
	_list.clear()
	_trees = Node2D.new()
	_trees.y_sort_enabled = true
	add_child(_trees, false, Node.INTERNAL_MODE_BACK)     # generated, never saved in the scene
	var names: Array[String] = []
	for k in kinds:
		if TreeArt.has(k):
			names.append(k)
	if names.is_empty() or polygon.size() < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = variation
	for p: Dictionary in _spots(rng):
		var s := Sprite2D.new()
		var kind: String = names[rng.randi() % names.size()]
		TreeArt.apply(s, kind)
		s.position = p.pos
		# deeper in the forest = darker, so the middle reads as thick shade
		var depth := clampf(_edge_distance(p.pos) / DEEP, 0.0, 1.0)
		var v := 1.0 - 0.24 * depth + rng.randf_range(-0.04, 0.0)
		s.modulate = Color(v, v, v)
		s.set_meta("shadow_scale", TreeArt.shadow_scale(kind))
		s.add_to_group("forest_tree")
		_trees.add_child(s)
		_list.append(s)
		_bounds = Rect2(s.position + s.offset, s.texture.get_size()) if _list.size() == 1 \
				else _bounds.merge(Rect2(s.position + s.offset, s.texture.get_size()))


## Where the trees go: first a row just inside the outline, then the inside filled evenly.
func _spots(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var grid := {}
	var cell := spacing
	var poly := polygon
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		var dir := (b - a) / length
		var inward := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + inward * 2.0, poly):
			inward = -inward
		var t := rng.randf_range(0.0, spacing * 0.5)
		while t < length:
			var p := a + dir * t + inward * (EDGE_INSET + rng.randf_range(0.0, 3.0))
			if Geometry2D.is_point_in_polygon(p, poly) and _free(grid, cell, p, spacing * 0.6):
				_add(grid, cell, p)
				out.append({"pos": p, "edge": true})
			t += spacing * rng.randf_range(0.6, 0.8)
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var step := spacing * 0.75
	var y := r.position.y
	while y <= r.end.y and out.size() < MAX_TREES:
		var x := r.position.x
		while x <= r.end.x:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)) * spacing
			if Geometry2D.is_point_in_polygon(p, poly) and _free(grid, cell, p, spacing * 0.7):
				_add(grid, cell, p)
				out.append({"pos": p, "edge": false})
			x += step
		y += step
	return out


func _edge_distance(p: Vector2) -> float:
	var best := INF
	var n := polygon.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % n])
		best = minf(best, q.distance_to(p))
	return best


func _free(grid: Dictionary, cell: float, p: Vector2, d: float) -> bool:
	var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in grid.get(c + Vector2i(dx, dy), []):
				if q.distance_to(p) < d:
					return false
	return true


func _add(grid: Dictionary, cell: float, p: Vector2) -> void:
	var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
	if not grid.has(c):
		grid[c] = []
	(grid[c] as Array).append(p)
