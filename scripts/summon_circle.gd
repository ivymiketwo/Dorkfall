class_name SummonCircle
extends RefCounted
## The blue summoning circle drawn on the ground under the player (home teleport, ward).
## Only drawing: call `SummonCircle.draw(canvas_item, ...)` from a draw callback.

## Colours: fill, outer ring, inner ring, star, ticks, motes.
const BLUE := [Color(0.15, 0.35, 0.85), Color(0.55, 0.8, 1.0), Color(0.35, 0.65, 1.0),
		Color(0.7, 0.88, 1.0), Color(0.8, 0.92, 1.0), Color(0.7, 0.9, 1.0)]
const RED := [Color(0.75, 0.06, 0.06), Color(1.0, 0.42, 0.34), Color(0.9, 0.16, 0.12),
		Color(1.0, 0.55, 0.45), Color(1.0, 0.7, 0.6), Color(1.0, 0.6, 0.45)]


static func ring(c: Vector2, r: float, rot: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := rot + TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.5))     # squashed: seen from above at an angle
	return pts


## `t` = seconds since it appeared (spins and fades in with it), `fade` = overall opacity,
## `motes` = how many sparks rise from it.
static func draw(ci: CanvasItem, radius: float, t: float, fade: float, motes: int, colors: Array = BLUE) -> void:
	var fade_in := clampf(t / 0.35, 0.0, 1.0) * fade
	var pulse := 0.75 + 0.25 * sin(t * 6.0)
	var c := Vector2(0, -1)
	ci.draw_colored_polygon(ring(c, radius, 0.0, 28), _a(colors[0], 0.20 * fade_in * pulse))
	ci.draw_polyline(ring(c, radius, 0.0, 40), _a(colors[1], 0.9 * fade_in), 1.0)
	ci.draw_polyline(ring(c, radius * 0.82, 0.0, 40), _a(colors[2], 0.7 * fade_in), 1.0)
	# rotating runic star and ticks
	var rot := t * 1.1
	var star := PackedVector2Array()
	for i in 6:
		var a := rot + TAU * float(i) / 6.0
		star.append(c + Vector2(cos(a) * radius * 0.78, sin(a) * radius * 0.78 * 0.5))
	for i in 6:
		ci.draw_line(star[i], star[(i + 2) % 6], _a(colors[3], 0.8 * fade_in), 1.0)
	for i in 12:
		var a := -rot * 0.7 + TAU * float(i) / 12.0
		var p1 := c + Vector2(cos(a) * radius * 0.86, sin(a) * radius * 0.86 * 0.5)
		var p2 := c + Vector2(cos(a) * radius * 0.98, sin(a) * radius * 0.98 * 0.5)
		ci.draw_line(p1, p2, _a(colors[4], 0.9 * fade_in), 1.0)
	# rising motes
	for i in motes:
		var seed_a := float(i) * 2.399
		var life := fposmod(t * (0.9 + 0.4 * fmod(float(i) * 0.37, 1.0)) + float(i) * 0.31, 1.0)
		var a := seed_a + t * 0.5
		var rr := radius * (0.25 + 0.65 * fmod(float(i) * 0.61, 1.0))
		var p := c + Vector2(cos(a) * rr, sin(a) * rr * 0.5) + Vector2(0, -life * 24.0)
		ci.draw_rect(Rect2(p, Vector2(1, 1)), _a(colors[5], (1.0 - life) * fade_in))


static func _a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
