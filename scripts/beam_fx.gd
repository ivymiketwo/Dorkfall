class_name BeamFx
extends Node2D
## The flash left behind by an instant beam: a thin bright line that fades fast.
## With `lightning` on, a thin swirl of crackling bolts winds around the beam.

var length := 100.0
var direction := Vector2.RIGHT
var tint := Color(0.35, 0.85, 1.0)
var lightning := false
var life := 0.22
var _t := 0.0
const SWOOSH := preload("res://audio/ray_swoosh.wav")
var _sound: AudioStreamPlayer2D
var _bolts: Array = []      # each: PackedVector2Array, rebuilt a few times a second


func _ready() -> void:
	_sound = AudioStreamPlayer2D.new()      # every ray makes the same swoosh
	_sound.stream = SWOOSH
	_sound.pitch_scale = randf_range(0.95, 1.05)
	add_child(_sound)
	_sound.play()
	if lightning:
		life = 0.32
		_rebuild()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		if not _sound.playing:
			queue_free()
		else:
			visible = false     # flash is over; stay alive until the swoosh finishes
		return
	if lightning and int(_t * 45.0) != int((_t - delta) * 45.0):
		_rebuild()
	queue_redraw()


func _rebuild() -> void:
	# Two bolts twisting around the beam in opposite phase, with a little jitter.
	_bolts.clear()
	var n := maxi(int(length / 3.0), 4)
	var phase := randf() * TAU
	for b in 2:
		var pts := PackedVector2Array()
		for i in n + 1:
			var f := float(i) / n
			var along := f * length
			var swirl := sin(f * length * 0.4 + phase + b * PI) * 2.6
			var jitter := randf_range(-0.7, 0.7)
			var env := clampf(minf(f, 1.0 - f) * 8.0, 0.0, 1.0)   # pinch at both ends
			pts.append(Vector2(along, (swirl + jitter) * env))
		_bolts.append(pts)


func _draw() -> void:
	var a := 1.0 - _t / life
	var end := direction * length
	var glow := tint
	var mid := tint.lerp(Color.WHITE, 0.2)
	var hot := tint.lerp(Color.WHITE, 0.6)
	draw_line(Vector2.ZERO, end, Color(glow.r, glow.g, glow.b, 0.35 * a), 4.0)     # glow
	draw_line(Vector2.ZERO, end, Color(mid.r, mid.g, mid.b, 0.9 * a), 2.0)
	draw_line(Vector2.ZERO, end, Color(1, 1, 1, a), 1.0)                            # core
	draw_circle(Vector2.ZERO, 2.5 * a + 0.5, Color(hot.r, hot.g, hot.b, a))
	draw_circle(end, 2.0 * a + 0.5, Color(hot.r, hot.g, hot.b, a))
	if lightning:
		var rot := direction.angle()
		for pts: PackedVector2Array in _bolts:
			var world := PackedVector2Array()
			for p in pts:
				world.append(p.rotated(rot))
			draw_polyline(world, Color(glow.r, glow.g, glow.b, 0.45 * a), 2.0)
			draw_polyline(world, Color(hot.r, hot.g, hot.b, 0.95 * a), 1.0)
