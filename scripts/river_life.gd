extends Node2D
## Life along the river: ferns on the banks, beavers gnawing on the shore, a beaver
## lodge, and beavers paddling about in the water. Positions come from
## data/river_life.json (made along with the river art); the swimmers read the
## river's water map so they never leave the water, the same way the ducks do.
## Lives in GroundArt (below the characters); the shore things are added to Entities
## so they sort with the player.

const DATA := "res://data/river_life.json"
const WATER_MAP := "res://art/water_info_river.png"
const FERNS := ["res://art/fern_a.png", "res://art/fern_b.png", "res://art/fern_c.png"]
const SWIMMERS := 4
const MIN_DEPTH := 8             # water-map value needed (distance from the bank)
const SPEED := 7.0
const KEEP_OUT := Rect2(130, -222, 160, 160)   # swimmers stay out from under the bridge

var _img: Image
var _water_pos := Vector2.ZERO   # where the river's water map sits (the WaterRiver sprite)
var _swimmers: Array = []
var _t := 0.0


func _ready() -> void:
	z_index = 1
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f != null:
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_build_shore.call_deferred(data)
	var water := get_parent().get_node_or_null("WaterRiver") as Sprite2D
	if water != null:
		_water_pos = water.position
	var tex: Texture2D = load(WATER_MAP)
	if tex != null:
		_img = tex.get_image()
		_make_swimmers()


# ---- shore: ferns, bank beavers, lodge --------------------------------------------

func _build_shore(data: Dictionary) -> void:
	var ents := get_parent().get_parent().get_node_or_null("Entities")
	if ents == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fern_sway.gdshader")
	var textures: Array = []
	for p: String in FERNS:
		textures.append(load(p))
	var n := 0
	for fd: Array in data.get("ferns", []):
		var s := Sprite2D.new()
		s.name = "Fern%d" % n
		n += 1
		s.texture = textures[int(fd[2]) % textures.size()]
		s.centered = false
		s.offset = Vector2(-17, -20)
		s.scale = Vector2(0.5, 0.5)
		s.material = mat
		s.position = Vector2(fd[0], fd[1])
		s.flip_h = (n % 2 == 0)
		ents.add_child(s)
	var tex_gnaw: Texture2D = load("res://art/beaver_gnaw.png")
	var b := 0
	for bd: Array in data.get("beavers", []):
		var c := Critter.new()
		c.name = "BankBeaver%d" % b
		b += 1
		c.texture = tex_gnaw
		c.hframes = 4
		c.centered = false
		c.offset = Vector2(-18, -30)
		c.scale = Vector2(0.5, 0.5)
		c.flip_h = float(bd[2]) < 0.0
		c.frames = PackedInt32Array([0, 1, 2, 1, 0, 3])
		c.durations = PackedFloat32Array([0.55, 0.22, 0.22, 0.22, 0.7, 0.3])
		c.position = Vector2(bd[0], bd[1])
		ents.add_child(c)
	var lodge: Variant = data.get("lodge", null)
	if lodge is Array:
		var d: Node = load("res://scenes/decor.tscn").instantiate()
		d.name = "BeaverLodge"
		d.set("kind", "beaver_lodge")
		d.position = Vector2(lodge[0], lodge[1])
		ents.add_child(d)


# ---- swimmers ---------------------------------------------------------------------

func _depth_at(p: Vector2) -> int:
	if _img == null:
		return 0
	var q: Vector2 = ((p - _water_pos) * 2.0).floor()
	if q.x < 0 or q.y < 0 or q.x >= _img.get_width() or q.y >= _img.get_height():
		return 0
	var px := _img.get_pixel(int(q.x), int(q.y))
	return int(px.r * 255.0) if px.a > 0.5 else 0


func _swim_ok(p: Vector2) -> bool:
	return _depth_at(p) >= MIN_DEPTH and not KEEP_OUT.has_point(p)


func _random_water(rng: RandomNumberGenerator, near: Vector2 = Vector2.INF, reach := 0.0) -> Vector2:
	for i in 120:
		var p: Vector2
		if near == Vector2.INF:
			# anywhere along the river: x across the map, y across the river's span
			p = Vector2(rng.randf_range(-1020.0, 640.0), rng.randf_range(-980.0, -100.0))
		else:
			p = near + Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		if _swim_ok(p):
			return p
	return Vector2.INF


func _make_swimmers() -> void:
	var tex: Texture2D = load("res://art/beaver_swim.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in SWIMMERS:
		var p := _random_water(rng)
		if p == Vector2.INF:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.hframes = 4
		s.centered = false
		s.offset = Vector2(-20, -19)
		s.scale = Vector2(0.5, 0.5)
		s.position = p
		add_child(s)
		_swimmers.append({"s": s, "pos": p, "target": p, "dir": 1.0, "state": "idle",
				"wait": rng.randf_range(0.5, 3.0), "phase": rng.randf() * 6.0})


func _process(delta: float) -> void:
	_t += delta
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for d in _swimmers:
		var s: Sprite2D = d["s"]
		if d["state"] == "idle":
			d["wait"] -= delta
			if d["wait"] <= 0.0:
				var tgt := _random_water(rng, d["pos"], 70.0)
				if tgt != Vector2.INF and _clear_path(d["pos"], tgt):
					d["target"] = tgt
					d["state"] = "swim"
				else:
					d["wait"] = rng.randf_range(0.5, 2.0)
		else:
			var to: Vector2 = d["target"] - d["pos"]
			if to.length() < 1.5:
				d["state"] = "idle"
				d["wait"] = rng.randf_range(1.5, 5.0)
			else:
				var np: Vector2 = d["pos"] + to.normalized() * SPEED * delta
				if _swim_ok(np):
					d["pos"] = np
					if absf(to.x) > 1.0:
						d["dir"] = signf(to.x)
				else:
					d["state"] = "idle"
					d["wait"] = 0.5
		var bob := roundf(sin(_t * 2.0 + float(d["phase"])) * 0.5)
		s.position = (d["pos"] as Vector2).round() + Vector2(0, bob)
		s.flip_h = float(d["dir"]) < 0.0
		# four-frame paddle cycle, a bit quicker while swimming
		var rate := 5.0 if d["state"] == "swim" else 2.5
		s.frame = int(_t * rate + float(d["phase"])) % 4


func _clear_path(a: Vector2, b: Vector2) -> bool:
	for i in range(1, 9):
		if not _swim_ok(a.lerp(b, i / 8.0)):
			return false
	return true
