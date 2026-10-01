class_name HopRing
extends Node2D
## The "press Space now" marker: a red ring on the ground that snaps shut over `life`
## seconds. It appears the instant you land, so the window stays a quick reflex.

var life := 0.15
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var r := lerpf(15.0, 5.0, k)
	var pulse := 0.75 + 0.25 * sin(_t * 40.0)
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.6))     # lie flat on the ground
	draw_circle(Vector2.ZERO, r, Color(1, 0.1, 0.1, 0.22 * pulse))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(1, 0.25, 0.2, 0.95), 1.5, false)
	draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, Color(1, 0.85, 0.8, 0.8), 1.0, false)   # the target it closes onto
