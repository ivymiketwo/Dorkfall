class_name ShadowLayer
extends Node2D
## Soft ground shadows for trees, buildings, props and creatures. Trees and
## buildings cast long shadows that swing round with the sun (long at dawn and
## dusk, short at noon, gone at night). Everything else gets a small blob under
## its feet. Sits right above the ground and below the entities.

# name prefix -> [half width, height]; height 0 = just a blob (half width, half height of the ellipse)
const CASTERS := {
	"Tree": ["tall", 6.0, 30.0],
	"Blacksmith": ["tall", 28.0, 34.0],
	"PotionShop": ["tall", 28.0, 34.0],
	"PetShop": ["tall", 28.0, 34.0],
	"WizardShop": ["tall", 28.0, 34.0],
	"Lamp": ["tall", 1.5, 18.0],
	"Player": ["blob", 6.5, 2.4],
	"Vorly": ["blob", 17.0, 5.5],
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


func _ready() -> void:
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
		if spec[0] == "blob":
			_ellipse(p + Vector2(0, -1), spec[1], spec[2], Color(0, 0, 0, blob_alpha))
		else:
			var hw: float = spec[1]
			var is_tree := String(n.name).begins_with("Tree")
			var flat := Vector2(dir.x, 0.10 + 0.10 * sun)      # buildings/posts: mostly sideways
			if tall_alpha > 0.01:
				var col := Color(0.04, 0.03, 0.10, tall_alpha)
				if is_tree:
					# crown shadow: a soft blob thrown away from the sun, plus the trunk's
					var c := p + Vector2(dir.x, 0.25 + 0.2 * sun) * 16.0
					_ellipse(c, 11.0, 6.0, Color(col.r, col.g, col.b, tall_alpha * 0.55))
					_ellipse(c, 8.0, 4.2, Color(col.r, col.g, col.b, tall_alpha * 0.55))
				else:
					var sv := flat * (spec[2] as float)
					for f in [1.0, 0.78, 0.56]:
						var q := PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(hw, 0),
								p + Vector2(hw, 0) + sv * f, p + Vector2(-hw, 0) + sv * f])
						draw_colored_polygon(q, Color(col.r, col.g, col.b, tall_alpha * 0.55))
			_ellipse(p, hw * 0.9 if hw < 12.0 else hw * 0.8, 2.6, Color(0, 0, 0, blob_alpha * 0.6))


func _spec(n: Node) -> Array:
	var k: Variant = _kind(n.name)
	if k != null:
		return k
	if n is Pet:
		return ["blob", 4.0, 1.6]
	return []


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
