extends Node2D
## A small gust of wind at the feet when a hop launches: a few wisps curl outward
## and a dust ring puffs, then it all fades in about a third of a second.

var direction := Vector2.DOWN
var life := 0.35
var _t := 0.0
var _phase := randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / life
	var a := 1.0 - k
	var flat := Vector2(1.0, 0.5)                       # squash circles into ground-plane ellipses
	draw_set_transform(Vector2.ZERO, 0.0, flat)
	draw_arc(Vector2.ZERO, 4.0 + 12.0 * k, 0.0, TAU, 24, Color(1, 1, 1, 0.45 * a), 1.5)
	draw_arc(Vector2.ZERO, 2.0 + 8.0 * k, 0.0, TAU, 20, Color(0.75, 0.95, 1.0, 0.7 * a), 1.0)
	# three wisps spiralling out
	for i in 3:
		var base := _phase + i * TAU / 3.0 + k * 3.5
		var pts := PackedVector2Array()
		for j in 7:
			var f := j / 6.0
			var ang := base + f * 1.6
			var rad := (3.0 + 11.0 * k) * (0.35 + 0.65 * f)
			pts.append(Vector2(cos(ang), sin(ang)) * rad)
		draw_polyline(pts, Color(0.9, 1.0, 1.0, 0.85 * a), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a short streak trailing behind the direction of travel
	var back := -direction * (4.0 + 10.0 * k)
	draw_line(Vector2(0, -2), back + Vector2(0, -2), Color(1, 1, 1, 0.5 * a), 1.0)
