extends Node2D
## An enchanted crystal ball: a shaded glass sphere with swirling mist, a slowly
## pulsing glow and sparkles that drift up and twinkle. Drawn on the art pixel grid
## (half a world unit) so it matches the rest of the pixel art.

@export var radius_px := 12                       # radius in art pixels
@export var glow_color := Color(0.45, 0.8, 1.0)

const P := 0.5
var _t := 0.0
var _sparks: Array = []                           # {p, age, life}
var _spark_cd := 0.0


func _process(delta: float) -> void:
	_t += delta
	_spark_cd -= delta
	if _spark_cd <= 0.0:
		_spark_cd = randf_range(0.15, 0.45)
		var a := randf() * TAU
		_sparks.append({"p": Vector2(cos(a), sin(a)) * radius_px * P * randf_range(0.5, 1.2) + Vector2(0, -2.0),
				"age": 0.0, "life": randf_range(0.8, 1.6)})
	for i in range(_sparks.size() - 1, -1, -1):
		_sparks[i].age += delta
		_sparks[i].p += Vector2(0, -3.0) * delta
		if _sparks[i].age > _sparks[i].life:
			_sparks.remove_at(i)
	queue_redraw()


func _px(at: Vector2, c: Color, w := 1, h := 1) -> void:
	draw_rect(Rect2((at / P).floor() * P, Vector2(w, h) * P), c)


func _draw() -> void:
	var pulse := 0.8 + 0.2 * sin(_t * 2.2)
	# soft glow halo
	for r in [1.9, 1.6, 1.3]:
		draw_circle(Vector2.ZERO, radius_px * P * r, Color(glow_color.r, glow_color.g, glow_color.b, 0.045 * pulse))
	var R := float(radius_px)
	for y in range(-radius_px, radius_px):
		for x in range(-radius_px, radius_px):
			var cx := x + 0.5
			var cy := y + 0.5
			var d := sqrt(cx * cx + cy * cy) / R
			if d > 1.0:
				continue
			var col: Color
			if d > 0.88:
				col = Color(0.1, 0.12, 0.35)                                   # rim
			else:
				# light from the upper left
				var lit := clampf(1.0 - (Vector2(cx, cy) - Vector2(-R * 0.35, -R * 0.4)).length() / (R * 1.5), 0.0, 1.0)
				col = Color(0.12, 0.25, 0.6).lerp(Color(0.55, 0.88, 1.0), lit)
				col = Color(floorf(col.r * 5.0) / 5.0, floorf(col.g * 5.0) / 5.0, floorf(col.b * 5.0) / 5.0)   # banded, pixel-art shading
				# swirling mist
				var ang := atan2(cy, cx)
				var swirl := sin(ang * 2.0 - _t * 1.4 + d * 7.0) + 0.6 * sin(ang * 3.0 + _t * 0.9 - d * 5.0)
				if swirl > 1.05 and d < 0.8:
					col = col.lerp(Color(0.8, 0.95, 1.0), 0.55 * pulse)
			_px(Vector2(cx - 0.5, cy - 0.5) * P, col)
	# glassy highlight
	_px(Vector2(-R * 0.5, -R * 0.62) * P, Color(1, 1, 1, 0.95), 3, 1)
	_px(Vector2(-R * 0.62, -R * 0.5) * P, Color(1, 1, 1, 0.95), 1, 3)
	# the orb ponders: now and then a question mark swims up out of the mist and fades
	var ph := fposmod(_t, 7.0)
	if ph < 2.4:
		var ga := sin(ph / 2.4 * PI)
		var gc := Color(1.0, 0.95, 0.6, ga)
		var q := [".XXX.", "X...X", "....X", "...X.", "..X..", ".....", "..X.."]
		for qy in q.size():
			for qx in 5:
				if q[qy][qx] == "X":
					_px(Vector2(-2.5 + qx, -4.0 + qy - ph * 0.8) * P, gc)
	# sparkles
	for s: Dictionary in _sparks:
		var k: float = s.age / s.life
		var a := sin(k * PI)
		var c := Color(0.9, 0.97, 1.0, a)
		_px(s.p, c)
		if a > 0.6:
			_px(s.p + Vector2(P, 0), Color(c.r, c.g, c.b, 0.6))
			_px(s.p + Vector2(-P, 0), Color(c.r, c.g, c.b, 0.6))
			_px(s.p + Vector2(0, P), Color(c.r, c.g, c.b, 0.6))
			_px(s.p + Vector2(0, -P), Color(c.r, c.g, c.b, 0.6))
