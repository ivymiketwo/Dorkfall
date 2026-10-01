class_name Ambient
extends Node2D
## Little touches of life: chimney smoke, daytime birds, night fireflies.
## All drawn with plain rects so they match the pixel art. Lives in World.

const SMOKE_SOURCES := [
	{"pos": Vector2(147, 85), "col": Color(0.86, 0.86, 0.9)},     # blacksmith chimney
	{"pos": Vector2(270, 87), "col": Color(0.62, 0.9, 0.62)},     # potion shop chimney
	{"pos": Vector2(347, 83), "col": Color(0.7, 0.75, 1.0)},     # wizard shop chimney
]
const FIREFLY_COUNT := 46
const AREA := Vector2(360, 210)            # half-size of the box around the player

var _dn: DayNight
var _player: Node2D
var _puffs: Array = []
var _smoke_t := 0.0
var _birds: Array = []
var _bird_t := 6.0
var _flies: Array = []
var _fly_layer: Node2D
var _time := 0.0
var _flutter: Array = []     # butterflies that hang around a handful of bushes


func _ready() -> void:
	z_index = 90
	_fly_layer = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fly_layer.material = mat
	_fly_layer.draw.connect(_draw_flies)
	add_child(_fly_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_setup_butterflies.call_deferred()
	for i in FIREFLY_COUNT:
		_flies.append({"p": Vector2(rng.randf_range(-AREA.x, AREA.x), rng.randf_range(-AREA.y, AREA.y)),
				"ph": rng.randf() * TAU, "sp": rng.randf_range(0.5, 1.4), "r": rng.randf_range(6, 16)})


func _setup_butterflies() -> void:
	var ents := get_parent().get_node_or_null("Entities")
	if ents == null:
		return
	var bushes: Array = []
	for n in ents.get_children():
		if String(n.name).begins_with("Bush"):
			bushes.append(n)
	var cols := [Color("f6f0e0"), Color("f2d24a"), Color("8ec4f4"), Color("f29a4a"), Color("f0a0c8")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in bushes.size():
		if i % 4 != 1:                      # only some bushes get visitors
			continue
		for k in rng.randi_range(1, 2):
			_flutter.append({"home": (bushes[i] as Node2D).global_position + Vector2(0, -8), "ph": rng.randf() * TAU,
					"sp": rng.randf_range(0.6, 1.1), "r": rng.randf_range(9, 16), "col": cols[rng.randi() % cols.size()]})


func _process(delta: float) -> void:
	_time += delta
	if _dn == null:
		_dn = get_tree().get_first_node_in_group("day_night") as DayNight
	if _player == null:
		_player = Players.local(get_tree())
	if _player == null:
		return
	var pp := _player.global_position
	var outdoors := pp.y < 2300.0
	# --- smoke
	_smoke_t -= delta
	if _smoke_t <= 0.0 and outdoors:
		_smoke_t = 0.55
		for s: Dictionary in SMOKE_SOURCES:
			if pp.distance_to(s.pos) < 380.0:
				_puffs.append({"p": s.pos + Vector2(randf_range(-1, 1), 0), "age": 0.0, "life": randf_range(2.6, 3.6),
						"col": s.col, "w": randf_range(-2, 2)})
	for i in range(_puffs.size() - 1, -1, -1):
		var pf: Dictionary = _puffs[i]
		pf.age += delta
		pf.p += Vector2(4.0 + pf.w + 3.0 * sin(_time + pf.p.x), -8.0) * delta
		if pf.age > pf.life:
			_puffs.remove_at(i)
	# --- birds
	var night := _dn.night_amount if _dn else 0.0
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = randf_range(14.0, 30.0)
		if night < 0.2 and outdoors:
			var dir := 1.0 if randf() < 0.5 else -1.0
			var n := randi_range(1, 4)
			var y0 := pp.y + randf_range(-110, -40)
			for k in n:
				_birds.append({"p": Vector2(pp.x - dir * (380.0 + k * 14.0), y0 + randf_range(-10, 10) + k * 5.0),
						"v": Vector2(dir * randf_range(46, 62), randf_range(-3, 3)), "ph": randf() * TAU})
	for i in range(_birds.size() - 1, -1, -1):
		var b: Dictionary = _birds[i]
		b.p += b.v * delta
		if absf(b.p.x - pp.x) > 460.0:
			_birds.remove_at(i)
	# --- fireflies drift; wrap around the player so they're always nearby
	var vis := clampf((night - 0.25) / 0.5, 0.0, 1.0) * (1.0 if outdoors else 0.0)
	_fly_layer.visible = vis > 0.01
	for f: Dictionary in _flies:
		f.p += Vector2(sin(_time * f.sp + f.ph) * 6.0, cos(_time * f.sp * 0.8 + f.ph * 2.0) * 4.0) * delta
	if _fly_layer.visible:
		if _dn:
			var c := _dn.color
			_fly_layer.modulate = Color(minf(1.0 / maxf(c.r, 0.05), 4.0), minf(1.0 / maxf(c.g, 0.05), 4.0),
					minf(1.0 / maxf(c.b, 0.05), 4.0), vis)
		_fly_layer.queue_redraw()
	queue_redraw()


func _draw() -> void:
	for pf: Dictionary in _puffs:
		var t: float = pf.age / pf.life
		var s := roundf(lerpf(1.5, 5.0, t) * 2.0) / 2.0
		var col: Color = pf.col
		col.a = (1.0 - t) * 0.7
		var p: Vector2 = (pf.p as Vector2).snapped(Vector2(0.5, 0.5))
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), col)
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s * 0.5, s * 0.5)), Color(1, 1, 1, col.a * 0.5))
	for b: Dictionary in _birds:
		_draw_bird(b)
	_draw_butterflies()


func _draw_bird(b: Dictionary) -> void:
	var p: Vector2 = (b.p as Vector2).snapped(Vector2(0.5, 0.5))
	var up := sin(_time * 14.0 + b.ph) > 0.0
	var dark := Color(0.12, 0.1, 0.14)
	var flip := signf(b.v.x)
	# ground shadow far below
	draw_rect(Rect2(p + Vector2(-2, 70), Vector2(4, 1.5)), Color(0, 0, 0, 0.12))
	# body
	draw_rect(Rect2(p + Vector2(-1.5, -0.5), Vector2(3, 1.5)), dark)
	draw_rect(Rect2(p + Vector2(1.5 * flip - (0.5 if flip > 0 else 1.0), -0.5), Vector2(1, 1)), dark)
	if up:
		draw_rect(Rect2(p + Vector2(-3.5, -2.0), Vector2(2, 1)), dark)
		draw_rect(Rect2(p + Vector2(1.5, -2.0), Vector2(2, 1)), dark)
		draw_rect(Rect2(p + Vector2(-2.0, -1.0), Vector2(1, 1)), dark)
		draw_rect(Rect2(p + Vector2(1.0, -1.0), Vector2(1, 1)), dark)
	else:
		draw_rect(Rect2(p + Vector2(-3.5, 0.5), Vector2(2, 1)), dark)
		draw_rect(Rect2(p + Vector2(1.5, 0.5), Vector2(2, 1)), dark)


func _draw_flies() -> void:
	if _player == null:
		return
	var pp := _player.global_position
	for f: Dictionary in _flies:
		# wrap into the box around the player
		var rel: Vector2 = f.p - pp
		rel.x = fposmod(rel.x + AREA.x, AREA.x * 2.0) - AREA.x
		rel.y = fposmod(rel.y + AREA.y, AREA.y * 2.0) - AREA.y
		var p := (pp + rel).snapped(Vector2(0.5, 0.5))
		var blink := 0.5 + 0.5 * sin(_time * 2.2 * f.sp + f.ph)
		blink = blink * blink
		var col := Color(0.85, 1.0, 0.45)
		_fly_layer.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(col.r, col.g, col.b, 0.16 * blink))
		_fly_layer.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(col.r, col.g, col.b, 0.34 * blink))
		_fly_layer.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 1, 0.8, 0.5 + 0.5 * blink))


func _draw_butterflies() -> void:
	if _player == null or (_dn and _dn.night_amount > 0.35) or _player.global_position.y > 2300.0:
		return
	var pp := _player.global_position
	for f: Dictionary in _flutter:
		var home: Vector2 = f.home
		if home.distance_to(pp) > 380.0:
			continue
		var t: float = _time * f.sp + f.ph
		# lazy figure-eight around the bush, pausing now and then to "land"
		var rest := smoothstep(0.75, 0.95, sin(t * 0.37) * 0.5 + 0.5)
		var off := Vector2(sin(t) * f.r, sin(t * 2.0) * f.r * 0.45 - 4.0 + cos(t * 0.6) * 3.0)
		off = off.lerp(Vector2(4.0, -3.0), rest)
		var p := (home + off).snapped(Vector2(0.5, 0.5))
		var flap := sin(_time * lerpf(22.0, 4.0, rest) + f.ph)
		var wing := 1.5 if flap > 0.0 else 0.5
		var c: Color = f.col
		draw_rect(Rect2(p + Vector2(-2.0, -wing - 0.5), Vector2(2.0, 1.5 + wing * 0.5)), c)
		draw_rect(Rect2(p + Vector2(0.0, -wing - 0.5), Vector2(2.0, 1.5 + wing * 0.5)), c)
		draw_rect(Rect2(p + Vector2(-0.25, -0.5), Vector2(0.5, 2.0)), Color(0.15, 0.1, 0.12))
