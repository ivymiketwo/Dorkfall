extends Node2D
## A bubbling cauldron: iron pot over a crackling fire, with bubbles popping on the
## brew and puffs of steam drifting up. Everything is drawn on the art pixel grid
## (half a world unit), so it matches the rest of the pixel art.

@export var brew_color := Color(0.39, 0.84, 0.42)
@export var steam_color := Color(0.75, 1.0, 0.75)
@export var texture_override: Texture2D   # e.g. a purple-brew version for the wizard shop

const P := 0.5                         # one art pixel in world units
const TEX := preload("res://art/cauldron.png")
const SURFACE := Vector2(0, -17.5)     # centre of the brew, relative to the node (pot bottom)
const RX := 8.5
const RY := 1.6

var _t := 0.0
var _bubbles: Array = []               # {p, age, life, size}
var _steam: Array = []                 # {p, age, life, drift}
var _bubble_cd := 0.0
var _steam_cd := 0.0


func _process(delta: float) -> void:
	_t += delta
	_bubble_cd -= delta
	if _bubble_cd <= 0.0:
		_bubble_cd = randf_range(0.05, 0.18)
		var a := randf() * TAU
		var r := sqrt(randf()) * 0.85
		_bubbles.append({"p": SURFACE + Vector2(cos(a) * RX * r, sin(a) * RY * r), "age": 0.0,
				"life": randf_range(0.45, 0.95), "size": 1 if randf() < 0.5 else 2})
	_steam_cd -= delta
	if _steam_cd <= 0.0:
		_steam_cd = randf_range(0.12, 0.3)
		_steam.append({"p": SURFACE + Vector2(randf_range(-6.0, 6.0), -1.0), "age": 0.0,
				"life": randf_range(1.2, 2.0), "drift": randf_range(-1.5, 1.5)})
	for i in range(_bubbles.size() - 1, -1, -1):
		_bubbles[i].age += delta
		if _bubbles[i].age > _bubbles[i].life:
			_bubbles.remove_at(i)
	for i in range(_steam.size() - 1, -1, -1):
		var s: Dictionary = _steam[i]
		s.age += delta
		s.p += Vector2(s.drift + sin(_t * 2.0 + s.p.y) * 0.8, -6.0) * delta
		if s.age > s.life:
			_steam.remove_at(i)
	queue_redraw()


func _px(at: Vector2, c: Color, w := 1, h := 1) -> void:
	draw_rect(Rect2((at / P).floor() * P, Vector2(w, h) * P), c)


func _draw() -> void:
	var flick := 0.75 + 0.25 * sin(_t * 11.0) * sin(_t * 7.3)
	# warm firelight on the hearth (a flattened glow under the pot)
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.55, 0.2, 0.10 * flick))
	draw_circle(Vector2.ZERO, 11.0, Color(1.0, 0.62, 0.25, 0.12 * flick))
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(texture_override if texture_override else TEX, Rect2(Vector2(-15, -23), Vector2(30, 23)), false)
	# flames licking up around the bottom of the pot: little tapered tongues
	for i in 7:
		var bx := -9.0 + i * 3.0 + sin(_t * 3.0 + i) * 0.5
		var hn := int((4.0 + 7.0 * absf(sin(_t * (6.0 + i * 0.9) + i * 2.1))) * (1.0 - absf(bx) / 14.0))
		for j in hn:
			var k := float(j) / float(maxi(hn, 1))
			var w := maxi(1, int(round(3.0 * (1.0 - k))))
			var sway := int(round(sin(_t * 9.0 + i + j * 0.6) * k * 1.5))
			var y := 0.5 - (j + 1) * P
			var x := bx + (sway - w / 2.0) * P
			var col := Color(0.92, 0.3, 0.1) if k > 0.55 else Color(1.0, 0.58, 0.16)
			_px(Vector2(x, y), col, w, 1)
			if k < 0.35 and w >= 3:
				_px(Vector2(x + P, y), Color(1.0, 0.9, 0.5))
	# shimmering streak drifting across the brew
	var sx := fposmod(_t * 5.0, RX * 2.0 + 6.0) - RX - 3.0
	for k in 5:
		var x := sx + k * P
		if absf(x) < RX * 0.8:
			_px(SURFACE + Vector2(x, -0.5), brew_color.lightened(0.5))
	# bubbles: swell up as little domes, then pop into a splash ring
	for b: Dictionary in _bubbles:
		var k: float = b.age / b.life
		var c: Vector2 = b.p
		if k < 0.8:
			var s: int = (b.size + 1) if k > 0.4 else b.size
			_px(c + Vector2(-P, -(s) * P), brew_color.darkened(0.45), s + 2, s + 1)
			_px(c + Vector2(0, -(s - 1) * P), brew_color.lightened(0.3), s, s)
			_px(c + Vector2(0, -(s - 1) * P), Color(1, 1, 1, 0.95))
		else:
			var col := brew_color.lightened(0.65)
			for o in [Vector2(-3 * P, 0), Vector2(3 * P, 0), Vector2(-2 * P, -2 * P), Vector2(2 * P, -2 * P), Vector2(0, -3 * P)]:
				_px(c + o, col)
	# steam puffs
	for s: Dictionary in _steam:
		var k: float = s.age / s.life
		var col := steam_color
		col.a = 0.7 * (1.0 - k)
		var size := 2 if k < 0.35 else (3 if k < 0.7 else 4)
		if size >= 3:          # rounded puff: square with the corners knocked off
			_px(s.p + Vector2(P, 0), col, size - 2, size)
			_px(s.p + Vector2(0, P), col, 1, size - 2)
			_px(s.p + Vector2((size - 1) * P, P), col, 1, size - 2)
		else:
			_px(s.p, col, size, size)
