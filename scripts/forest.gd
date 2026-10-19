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
var _grid := {}                  # GRID-sized cells -> trees whose trunk is in that cell
var _faded := {}                 # trees that are (or are still turning back from) see-through
var _shadow_cache := {}          # see shadow_triangles()
const GRID := 40.0


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("forest")
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


## Trees you're standing behind turn see-through; they come back when you leave. Only looks at
## the trees at all while you're near this forest (or some are still see-through).
func _fade(delta: float) -> void:
	var pl := Players.local(get_tree())
	if pl == null:
		return
	var p := to_local(pl.global_position) + Vector2(0, -10)        # the middle of the character
	var near := _bounds.grow(10.0).has_point(p)
	if not near and _faded.is_empty():
		return
	var k := minf(delta * 8.0, 1.0)
	var check: Array[Sprite2D] = []
	if near:
		check = _nearby(p)
	var want_faded := {}
	for t in check:
		if t.position.y > p.y + 6.0 and Rect2(t.position + t.offset + Vector2(8, 6), t.region_rect.size - Vector2(16, 6)).has_point(p):
			want_faded[t] = true
			_faded[t] = true
	for t: Sprite2D in _faded.keys():
		var want := FADE_ALPHA if want_faded.has(t) else 1.0
		t.modulate.a = lerpf(t.modulate.a, want, k)
		if want == 1.0 and t.modulate.a > 0.99:
			t.modulate.a = 1.0
			_faded.erase(t)


## Trees within r of a world position (used by ShadowLayer to find the shadows it needs to draw).
func trees_near(world_pos: Vector2, r: float) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	var p := to_local(world_pos)
	if not _bounds.grow(r).has_point(p):
		return out
	var c0 := Vector2i(floori((p.x - r) / GRID), floori((p.y - r) / GRID))
	var c1 := Vector2i(floori((p.x + r) / GRID), floori((p.y + r) / GRID))
	for gy in range(c0.y, c1.y + 1):
		for gx in range(c0.x, c1.x + 1):
			for t: Sprite2D in _grid.get(Vector2i(gx, gy), []):
				out.append(t)
	return out


## All this forest's tree shadows as one batch of triangles (world coordinates), so the whole forest's
## shadow is one draw instead of one per tree. "crown" = treetop shadows thrown away from the sun
## (sun_x / sun_h as in ShadowLayer, already rounded by it), "base" = the dark patch at each trunk.
## Kept until the sun moves on.
func shadow_triangles(part: String, sun_x: float, sun_h: float) -> Array:
	var key := "%s|%s|%s" % [part, sun_x, sun_h] if part == "crown" else part
	if _shadow_cache.has(key):
		return _shadow_cache[key]
	for k: String in _shadow_cache.keys():
		if k.begins_with(part):
			_shadow_cache.erase(k)             # an older sun position
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for t in _list:
		var ts: float = t.get_meta("shadow_scale", 1.0)
		var at := to_global(t.position)
		if part == "crown":
			var j := ShadowLayer.jitter(at)
			ShadowLayer.ellipse_tris(pts, idx, at + Vector2(sun_x, 0.25 + 0.2 * sun_h) * 16.0 * ts,
					10.5 * ts * j, 5.6 * ts * (2.0 - j))
		else:
			ShadowLayer.ellipse_tris(pts, idx, at, 6.0 * ts * 0.8, 2.6 * sqrt(ts))
	var out := [pts, idx]
	_shadow_cache[key] = out
	return out


## The trees whose trunks are within a tree's height below / half a tree's width beside p.
func _nearby(p: Vector2) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	var c := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
	for gy in range(c.y, c.y + 4):
		for gx in range(c.x - 2, c.x + 3):
			for t: Sprite2D in _grid.get(Vector2i(gx, gy), []):
				out.append(t)
	return out


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
	_grid.clear()
	_faded.clear()
	_shadow_cache.clear()
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
		# deeper in the forest = darker, so the middle reads as thick shade (darker copies of the
		# trees are in the atlas; tinting here would stop the trees being drawn together)
		var depth := clampf(_edge_distance(p.pos) / DEEP, 0.0, 1.0)
		var shade := clampi(roundi(depth * (TreeArt.SHADE_COUNT - 1) + rng.randf_range(-0.4, 0.4)), 0, TreeArt.SHADE_COUNT - 1)
		TreeArt.apply(s, kind, shade)
		s.position = p.pos
		s.set_meta("shadow_scale", TreeArt.shadow_scale(kind))
		_trees.add_child(s)
		_list.append(s)
		var gc := Vector2i(floori(s.position.x / GRID), floori(s.position.y / GRID))
		if not _grid.has(gc):
			_grid[gc] = []
		(_grid[gc] as Array).append(s)
		_bounds = Rect2(s.position + s.offset, s.region_rect.size) if _list.size() == 1 \
				else _bounds.merge(Rect2(s.position + s.offset, s.region_rect.size))


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
