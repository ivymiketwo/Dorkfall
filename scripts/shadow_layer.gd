class_name ShadowLayer
extends Node2D
## Soft ground shadows for trees, buildings, props and creatures. Trees and
## buildings cast long shadows that swing round with the sun (long at dawn and
## dusk, short at noon, gone at night). Everything else gets a small blob under
## its feet. Sits right above the ground and below the entities.
## Tree shadows are drawn solid into two CanvasGroups (treetops, trunk bases) that are then laid
## down see-through as one piece, so overlapping trees make one smooth shadow, not a pile of circles.

# name prefix -> [half width, height]; height 0 = just a blob (half width, half height of the ellipse)
const CASTERS := {
	"Tree": ["tall", 6.0, 30.0],
	"Blacksmith": ["tall", 28.0, 34.0],
	"PotionShop": ["tall", 28.0, 34.0],
	"PetShop": ["tall", 28.0, 34.0],
	"FishingShop": ["tall", 28.0, 34.0],
	"WizardShop": ["tall", 28.0, 34.0],
	"Lamp": ["tall", 1.5, 18.0],
	"Player": ["blob", 6.5, 2.4],
	"Vorly": ["blob", 25.5, 8.0],
	"Mangyang": ["blob", 6.0, 2.4],
	"BoneLord": ["blob", 12.0, 4.0],
	"Skeleton": ["blob", 6.0, 2.4],
	"Crypt": ["tall", 30.0, 30.0], "CaveRock": ["blob", 12.0, 3.0], "CaveStalag": ["blob", 6.0, 2.0],
	"Grave": ["blob", 8.0, 2.4], "Fence": ["blob", 8.0, 1.6],
	"Well": ["blob", 9.0, 3.5], "Barrel": ["blob", 5.0, 2.0], "Crate": ["blob", 5.5, 2.0],
	"Anvil": ["blob", 5.0, 2.0],
	"Stall": ["blob", 17.0, 3.5], "Bush": ["blob", 9.0, 2.8], "Sign": ["blob", 4.0, 1.5], "Bench": ["blob", 11.0, 2.5],
	"Hay": ["blob", 9.0, 2.8], "Planter": ["blob", 6.0, 2.0], "Sacks": ["blob", 8.5, 2.2],
}

var _casters: Array[Node2D] = []
var _dn: DayNight
var _last_hour := -1.0
var _crown_group := CanvasGroup.new()
var _base_group := CanvasGroup.new()
var _crowns := Node2D.new()
var _bases := Node2D.new()
var _trees: Array[Node2D] = []        # the casters that are trees, refreshed each frame
var _sun_dir := Vector2.ZERO
var _sun := 1.0
var _forests: Array[Node] = []        # forests near the player
var _tree_key := ""                   # what the tree shadows were last drawn for
const SHADOW_COLOR := Color(0.04, 0.03, 0.10)


func _ready() -> void:
	_crown_group.add_child(_crowns)
	_base_group.add_child(_bases)
	add_child(_crown_group)
	add_child(_base_group)
	_crowns.draw.connect(_draw_crowns)
	_bases.draw.connect(_draw_bases)
	var ents := get_parent().get_node_or_null("Entities")
	if ents == null:
		return
	for n in ents.get_children():
		if n is Node2D and _kind(n.name) != null:
			_casters.append(n)
	ents.child_entered_tree.connect(func(n: Node):
		if n is Pet:
			_casters.append(n))


func _kind(nm: String) -> Variant:
	for k: String in CASTERS:
		if nm.begins_with(k):
			return CASTERS[k]
	return null


func _process(_delta: float) -> void:
	if _dn == null:
		_dn = get_tree().get_first_node_in_group("day_night") as DayNight
	queue_redraw()   # creatures move every frame; the layer is cheap


func _draw() -> void:
	var player := Players.local(get_tree())
	if player == null:
		return
	var sun := _dn.sun_height if _dn else 1.0
	var ang := _dn.sun_angle if _dn else PI * 0.5
	var night := _dn.night_amount if _dn else 0.0
	# Sun sweeps east -> west: shadows point west in the morning, east in the evening.
	var reach := lerpf(1.25, 0.3, sun)                     # long when the sun is low
	var dir := Vector2(-cos(ang) * reach, 0.18 + 0.28 * sun)
	var tall_alpha := 0.42 * sun
	var blob_alpha := lerpf(0.36, 0.18, night)
	var pp := player.global_position
	_trees.clear()
	_sun_dir = dir
	_sun = sun
	for i in range(_casters.size() - 1, -1, -1):
		var n := _casters[i]
		if not is_instance_valid(n):
			_casters.remove_at(i)
			continue
		if n.global_position.distance_to(pp) > 420.0:
			continue
		var spec: Array = _spec(n)
		if spec.is_empty():
			continue
		var p := to_local(n.global_position)
		if n is Pet:
			p += Pet.LIFT            # the pet's node sits above its feet (see pet.gd)
		if spec[0] == "blob":
			_ellipse(p + Vector2(0, -1), spec[1], spec[2], Color(0, 0, 0, blob_alpha))
		else:
			var hw: float = spec[1]
			if String(n.name).begins_with("Tree"):
				_trees.append(n)         # drawn merged, see _draw_crowns / _draw_bases
				continue
			var flat := Vector2(dir.x, 0.10 + 0.10 * sun)      # buildings/posts: mostly sideways
			if tall_alpha > 0.01:
				var col := Color(0.04, 0.03, 0.10, tall_alpha)
				var sv := flat * (spec[2] as float)
				for f in [1.0, 0.78, 0.56]:
					var q := PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(hw, 0),
							p + Vector2(hw, 0) + sv * f, p + Vector2(-hw, 0) + sv * f])
					draw_colored_polygon(q, Color(col.r, col.g, col.b, tall_alpha * 0.55))
			_ellipse(p, hw * 0.9 if hw < 12.0 else hw * 0.8, 2.6, Color(0, 0, 0, blob_alpha * 0.6))
	# forests (forest.gd) near the player hand over their whole shadow in one piece
	_forests.clear()
	for f in get_tree().get_nodes_in_group("forest"):
		if (f as Forest).is_near(pp, 420.0):
			_forests.append(f)
	# the tree shadows only need drawing again when something they depend on changes
	var key := "%s|%s|%s|%s" % [snappedf(dir.x, 0.01), snappedf(sun, 0.01), _trees.size(), _forests.size()]
	if not _trees.is_empty():
		key += "|%s|%s" % [_trees[0].get_instance_id(), _trees[-1].get_instance_id()]
	if key != _tree_key:
		_tree_key = key
		_crowns.queue_redraw()
		_bases.queue_redraw()
	_crown_group.self_modulate = Color(1, 1, 1, tall_alpha * 0.62)
	_base_group.self_modulate = Color(1, 1, 1, blob_alpha * 0.6)


## Treetop shadows: one squashed blob per tree, thrown away from the sun, all drawn solid (the
## group makes them see-through as a whole). Each forest's come as one batch of triangles.
func _draw_crowns() -> void:
	var sx := snappedf(_sun_dir.x, 0.01)
	var sh := snappedf(_sun, 0.01)
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for n in _trees:
		if is_instance_valid(n):
			var ts: float = n.get_meta("shadow_scale", 1.0)
			var j := jitter(n.global_position)
			ellipse_tris(pts, idx, n.global_position + Vector2(sx, 0.25 + 0.2 * sh) * 16.0 * ts,
					10.5 * ts * j, 5.6 * ts * (2.0 - j))
	_triangles(_crowns, pts, idx)
	for f in _forests:
		if is_instance_valid(f):
			var groups: Dictionary = (f as Forest).shadow_crowns()
			for ts: float in groups:
				var tri: Array = groups[ts]
				_triangles(_crowns, tri[0], tri[1], Vector2(sx, 0.25 + 0.2 * sh) * 16.0 * ts)


## The dark patch right at the foot of each trunk.
func _draw_bases() -> void:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for n in _trees:
		if is_instance_valid(n):
			var ts: float = n.get_meta("shadow_scale", 1.0)
			var hw := 6.0 * ts
			ellipse_tris(pts, idx, n.global_position, hw * 0.9 if hw < 12.0 else hw * 0.8, 2.6 * sqrt(ts))
	_triangles(_bases, pts, idx)
	for f in _forests:
		if is_instance_valid(f):
			var tri: Array = (f as Forest).shadow_bases()
			_triangles(_bases, tri[0], tri[1])


## Draws a batch of triangles given in world coordinates (moved by `shift`), in one go.
func _triangles(item: Node2D, pts: PackedVector2Array, idx: PackedInt32Array, shift := Vector2.ZERO) -> void:
	if idx.is_empty():
		return
	item.draw_set_transform_matrix(item.get_global_transform().affine_inverse() * Transform2D(0.0, shift))
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(SHADOW_COLOR)
	RenderingServer.canvas_item_add_triangle_array(item.get_canvas_item(), idx, pts, cols)
	item.draw_set_transform_matrix(Transform2D.IDENTITY)


## Adds an ellipse (a fan of triangles) to a triangle batch.
static func ellipse_tris(pts: PackedVector2Array, idx: PackedInt32Array, c: Vector2, rx: float, ry: float) -> void:
	var n := 14 if rx < 14.0 else 20
	var first := pts.size()
	pts.append(c)
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	for i in n:
		idx.append(first)
		idx.append(first + 1 + i)
		idx.append(first + 1 + (i + 1) % n)


## A steady 0.85..1.15 per tree, so neighbouring shadows aren't all the same size.
static func jitter(at: Vector2) -> float:
	var h := absi(int(at.x * 73.0) ^ int(at.y * 151.0)) % 1000
	return 0.85 + 0.3 * float(h) / 1000.0


func _spec(n: Node) -> Array:
	var k: Variant = _kind(n.name)
	if k != null:
		return k
	if n is Pet:
		return ["blob", 4.0, 1.6]
	return []


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	_ellipse_on(self, c, rx, ry, col)


func _ellipse_on(item: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14 if rx < 14.0 else 22
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	item.draw_colored_polygon(pts, col)
