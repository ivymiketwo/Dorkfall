class_name WindCone
extends Node2D
## Vorly's finishing move. A huge cone is painted on the ground pointing at
## where the target stood; it fills up over `warn_time`, then a gust of green
## wind blasts out across the whole cone and hurts anyone it sweeps over.
## Place this node at the cone's tip and set `angle` (radians) before adding it.

@export var damage := 200.0
@export var length := 160.0            # about half the screen width
@export var spread_deg := 50.0
@export var warn_time := 1.1
@export var sweep_time := 0.5          # how long the gust takes to reach the far edge
@export var linger_time := 0.55
var angle := 0.0

const RING := Color(0.55, 1.0, 0.30)
const FILL := Color(0.35, 0.85, 0.20)

var _t := 0.0
var _gust := false
var _timeline: AttackTimeline   ## when the gust sweeps (rules); drawing reads _t
var _hit := {}
var _fx: Node2D
var _streaks: Array = []
var _bits: Array = []
var _eddies: Array = []


func _ready() -> void:
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var half := deg_to_rad(spread_deg) * 0.5
	for i in 64:
		_streaks.append({"a": randf_range(-half * 0.95, half * 0.95), "d": randf_range(0.0, 0.25),
				"len": randf_range(40.0, 100.0), "w": randf_range(0.0, TAU),
				"spd": randf_range(0.8, 1.25)})
	for i in 16:
		_eddies.append({"a": randf_range(-half * 0.85, half * 0.85), "r": randf_range(0.15, 0.92) * length,
				"size": randf_range(5.0, 9.5), "spin": 1.0 if randf() < 0.5 else -1.0, "ph": randf() * TAU})
	for i in 70:
		_bits.append({"a": randf_range(-half, half), "d": randf_range(0.0, 0.3),
				"s": randf_range(1.0, 2.2), "w": randf_range(0.0, TAU), "spd": randf_range(0.7, 1.2)})
	_timeline = AttackTimeline.new().during(warn_time, warn_time + sweep_time + linger_time, _sweep)


func _half() -> float:
	return deg_to_rad(spread_deg) * 0.5


func _front() -> float:
	return length * clampf((_t - warn_time) / sweep_time, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


## Every tick from the gust until it dies out: the leading edge sweeps outwards and hits
## each player once.
func _sweep(_progress: float) -> void:
	_gust = true
	var front := length * clampf((_timeline.t - warn_time) / sweep_time, 0.0, 1.0)
	for player in Players.all(get_tree()):
		if _hit.has(player):
			continue
		var lp := to_local(player.global_position)
		if AttackRules.cone_hits(lp, front, length, angle, _half()):
			_hit[player] = true
			AttackRules.deal(player, damage, AttackGuard.caster_of(self), global_position)


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


func _sector(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	var h := _half()
	for i in 21:
		pts.append(Vector2.from_angle(angle - h + 2.0 * h * float(i) / 20.0) * radius)
	return pts


func _draw() -> void:
	# Warning marker (drawn under characters).
	var h := _half()
	if _t < warn_time:
		var k := _t / warn_time
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		draw_colored_polygon(_sector(length), Color(FILL.r, FILL.g, FILL.b, 0.13 + 0.10 * k))
		if k > 0.02:
			draw_colored_polygon(_sector(length * k), Color(FILL.r, FILL.g, FILL.b, 0.20))   # fills outward
		var edge := Color(RING.r, RING.g, RING.b, 0.65 + 0.3 * pulse)
		var outline := _sector(length)
		outline.append(Vector2.ZERO)
		draw_polyline(outline, edge, 1.5)
		# a few chevrons hint at the wind direction
		for c in 3:
			var r := length * (0.30 + 0.25 * c)
			var a0 := angle - h * 0.55
			var a1 := angle + h * 0.55
			draw_arc(Vector2.ZERO, r, a0, a1, 20, Color(RING.r, RING.g, RING.b, 0.22), 1.0)
	# (once the gust starts the marker is gone; only the wind effects in _draw_fx remain)


func _draw_fx() -> void:
	if _t < warn_time:
		return
	var h := _half()
	var dir := Vector2.from_angle(angle)
	var perp := dir.orthogonal()
	var b := _t - warn_time
	var total := sweep_time + linger_time
	var front := _front()
	var wash_a := clampf(1.0 - b / total, 0.0, 1.0)
	# a dense body of wind: soft layers trailing behind the front
	for i in 4:
		var r := front - float(i) * 15.0
		if r > 2.0:
			_fx.draw_colored_polygon(_sector(r), Color(0.5, 0.95, 0.35, (0.13 - 0.025 * float(i)) * wash_a))
	# long straight speed lines, thin at the tail and thick at the head
	for s in _streaks:
		var t: float = (b - s["d"]) * s["spd"] / sweep_time
		if t < 0.0 or t > 1.4:
			continue
		var head: float = minf(length * t, length * 1.03)
		var tail: float = maxf(length * t - s["len"], 0.0)
		if head <= tail:
			continue
		var a: float = 1.0 - clampf((t - 1.0) / 0.4, 0.0, 1.0)
		var d := Vector2.from_angle(angle + s["a"])
		var mid: float = lerpf(tail, head, 0.6)
		_fx.draw_line(d * tail, d * mid, Color(0.7, 1.0, 0.5, 0.45 * a), 1.0)
		_fx.draw_line(d * mid, d * head, Color(0.35, 0.8, 0.2, 0.5 * a), 4.0)
		_fx.draw_line(d * mid, d * head, Color(0.9, 1.0, 0.7, 0.95 * a), 1.6)
	# curling eddies whipped up as the front passes
	for e in _eddies:
		var born: float = float(e["r"]) / length * sweep_time
		var t: float = (b - born) / 0.5
		if t < 0.0 or t > 1.0:
			continue
		var c: Vector2 = Vector2.from_angle(angle + e["a"]) * float(e["r"]) + dir * (26.0 * t)
		var rot: float = float(e["ph"]) + float(e["spin"]) * b * 12.0
		var pts := PackedVector2Array()
		for i in 22:
			var f := float(i) / 21.0
			pts.append(c + Vector2.from_angle(rot + float(e["spin"]) * f * 8.5) * float(e["size"]) * f)
		var a := sin(t * PI)
		_fx.draw_polyline(pts, Color(0.3, 0.75, 0.18, 0.5 * a), 4.0)
		_fx.draw_polyline(pts, Color(0.9, 1.0, 0.7, 0.95 * a), 1.4)
	# the shock front
	if front > 4.0 and b < sweep_time + 0.12:
		var fa := 1.0 - clampf((b - sweep_time) / 0.12, 0.0, 1.0)
		_fx.draw_arc(Vector2.ZERO, front, angle - h, angle + h, 32, Color(0.5, 0.95, 0.3, 0.5 * fa), 6.0)
		_fx.draw_arc(Vector2.ZERO, front, angle - h, angle + h, 32, Color(0.95, 1.0, 0.8, fa), 1.6)
	# leaves, dust and grit blown along
	for m in _bits:
		var t: float = (b - m["d"]) * m["spd"] / (sweep_time * 1.3)
		if t < 0.0 or t > 1.2:
			continue
		var r: float = length * t
		var wob: float = sin(r * 0.15 + m["w"]) * 7.0
		var pos := Vector2.from_angle(angle + m["a"]) * r + perp * wob
		var a: float = 1.0 - clampf((t - 0.85) / 0.35, 0.0, 1.0)
		if int(m["w"] * 10.0) % 3 == 0:
			var sz: float = m["s"] * 1.6
			var rot: float = b * 9.0 + m["w"]
			var pts := PackedVector2Array()
			for c in [Vector2(sz, 0), Vector2(0, sz * 0.55), Vector2(-sz, 0), Vector2(0, -sz * 0.55)]:
				pts.append(pos + c.rotated(rot))
			_fx.draw_colored_polygon(pts, Color(0.45, 0.9, 0.25, a))
		elif int(m["w"] * 10.0) % 3 == 1:
			_fx.draw_circle(pos, m["s"] * 2.4 * (0.6 + t), Color(0.55, 0.75, 0.4, 0.22 * a))
		else:
			_fx.draw_rect(Rect2(pos - Vector2(m["s"], m["s"]) * 0.5, Vector2(m["s"], m["s"])), Color(0.7, 1.0, 0.45, a))

## Called if whoever cast this dies: gone instantly, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
