class_name BoulderRain
extends Node2D
## A barrage of falling boulders. Every spot gets a red circle on the ground at
## once; each boulder then drops at its own slightly different moment. The
## circle vanishes the instant its boulder lands and hurts anyone inside it.

@export var radius := 12.0
@export var warn_time := 1.1     ## earliest a boulder can land
@export var spread := 0.8        ## extra random delay on top (keeps the timing tight)
@export var damage := 90.0
const FALL_TIME := 0.42
const FALL_HEIGHT := 120.0

var spots: Array[Vector2] = []   ## global positions
var radii: Array[float] = []     ## per-spot radius (falls back to `radius`)
var caster: Node
var _t := 0.0
var _land: Array[float] = []
var _shape: Array[PackedVector2Array] = []
var _done: Array[bool] = []
var _debris: Array = []          ## [pos, age, seed]
var _fx: Node2D


func _r(i: int) -> float:
	return radii[i] if i < radii.size() else radius


func _ready() -> void:
	_fx = Node2D.new()           # boulders and debris are drawn above characters
	_fx.z_index = 6
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in spots.size():
		_land.append(warn_time + rng.randf() * spread)
		_done.append(false)
		var pts := PackedVector2Array()
		var n := 9
		for k in n:
			var a := TAU * float(k) / float(n)
			pts.append(Vector2.from_angle(a) * _r(i) * rng.randf_range(0.62, 0.86))
		_shape.append(pts)


func _process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	_t += delta
	var alive := false
	for i in spots.size():
		if not _done[i]:
			alive = true
			if _t >= _land[i]:
				_done[i] = true
				_impact(i)
	for d in _debris:
		d[1] += delta
	_debris = _debris.filter(func(d): return d[1] < 0.45)
	if not alive and _debris.is_empty():
		queue_free()
		return
	queue_redraw()
	_fx.queue_redraw()


func _impact(i: int) -> void:
	_debris.append([spots[i], 0.0, i])
	for player in Players.all(get_tree()):
		var p: Vector2 = player.global_position + AttackRules.CHEST - spots[i]
		if AttackRules.circle_hits(p, _r(i) + 2.0):
			AttackRules.deal(player, damage)


func _draw() -> void:
	for i in spots.size():
		if _done[i]:
			continue
		var c := to_local(spots[i])
		var k := clampf(_t / _land[i], 0.0, 1.0)
		var rr := _r(i)
		draw_circle(c, rr, Color(1.0, 0.85, 0.2, 0.14 + 0.12 * k))
		draw_circle(c, rr * k, Color(0.95, 0.12, 0.1, 0.22 + 0.3 * k))
		draw_arc(c, rr, 0.0, TAU, 24, Color(0.95, 0.2, 0.15, 0.75), 1.0)


func _draw_fx() -> void:
	# falling boulders (only during the last moments before landing)
	for i in spots.size():
		if _done[i]:
			continue
		var left := _land[i] - _t
		if left > FALL_TIME:
			continue
		var f := 1.0 - left / FALL_TIME              # 0 high up .. 1 landing
		var e := f * f
		var c := to_local(spots[i]) + Vector2(0, -FALL_HEIGHT * (1.0 - e))
		var sc := 0.7 + 0.5 * e
		var pts := PackedVector2Array()
		for p in _shape[i]:
			pts.append(c + p * sc * 1.25)
		_fx.draw_colored_polygon(pts, Color(0.1, 0.09, 0.12))
		var inner := PackedVector2Array()
		for p in _shape[i]:
			inner.append(c + p * sc * 1.05)
		_fx.draw_colored_polygon(inner, Color(0.42, 0.4, 0.46))
		var hi := PackedVector2Array([c + _shape[i][6] * sc, c + _shape[i][7] * sc, c + _shape[i][8] * sc, c + _shape[i][0] * sc * 0.4])
		_fx.draw_colored_polygon(hi, Color(0.6, 0.58, 0.64))
		# motion streak
		_fx.draw_line(c + Vector2(0, -_r(i) * sc), c + Vector2(0, -_r(i) * sc - 18.0 * (1.0 - e)), Color(0.7, 0.68, 0.75, 0.5), 2.0)
	# impact debris + dust
	for d in _debris:
		var c := to_local(d[0] as Vector2)
		var age: float = d[1]
		var a := 1.0 - age / 0.45
		var dr := _r(int(d[2]))
		_fx.draw_arc(c, dr * (0.5 + 1.6 * age / 0.45), 0.0, TAU, 20, Color(0.75, 0.7, 0.62, a * 0.6), 2.0)
		var r := RandomNumberGenerator.new()
		r.seed = int(d[2]) * 977 + 5
		for k in 6:
			var ang := r.randf() * TAU
			var sp := r.randf_range(10.0, 26.0)
			var pos := c + Vector2.from_angle(ang) * sp * age * 2.0 + Vector2(0, 30.0 * age * age - 8.0 * age)
			_fx.draw_rect(Rect2(pos - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.5, 0.48, 0.54, a))


## Called if the caster dies: everything vanishes, no damage.
func _cancel() -> void:
	set_process(false)
	hide()
	queue_free()
