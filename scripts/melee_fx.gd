class_name MeleeFx
extends Node2D
## The visible swing: a sweeping arc for a sword, a quick thrust for a staff bash.

var kind := "staff"
var direction := Vector2.RIGHT
var reach := 24.0
var arc := 90.0
var life := 0.18
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / life
	var a := 1.0 - k
	var base := direction.angle()
	if kind == "sword":
		var half := deg_to_rad(arc) * 0.5
		var cur := lerpf(-half, half, k)                     # blade sweeps across the arc
		var tip := Vector2.from_angle(base + cur) * reach
		# trailing crescent
		var trail := PackedVector2Array()
		for i in 9:
			var an := lerpf(-half, cur, i / 8.0)
			trail.append(Vector2.from_angle(base + an) * reach)
		if trail.size() > 1:
			draw_polyline(trail, Color(0.85, 0.92, 1.0, 0.7 * a), 3.0)
			draw_polyline(trail, Color(1, 1, 1, a), 1.0)
		draw_line(Vector2.from_angle(base + cur) * 4.0, tip, Color(0.9, 0.93, 1.0), 2.0)   # blade
		draw_line(Vector2.from_angle(base + cur) * 3.0, Vector2.from_angle(base + cur) * 5.0, Color("e8c030"), 3.0)
	elif kind == "fist":
		var ext := reach * sin(k * PI)
		var end := direction * (3.0 + ext)
		draw_circle(end, 2.5, Color("f0c8a0"))
		draw_arc(end, 3.5, 0.0, TAU, 12, Color(1, 1, 1, a * 0.6), 1.0)
	else:
		# staff bash: thrust out and back, with a little impact star at the end
		var ext := reach * sin(k * PI)
		var end := direction * (4.0 + ext)
		draw_line(direction * 2.0, end, Color("8a5a2a"), 2.0)
		draw_circle(end, 2.2, Color("4a9aff"))
		draw_circle(end, 1.0, Color.WHITE)
		if k > 0.35 and k < 0.75:
			var star := direction * reach
			for i in 4:
				var an := i * PI * 0.5 + PI * 0.25
				draw_line(star, star + Vector2.from_angle(an) * 4.0, Color(1, 0.9, 0.5, a), 1.0)
