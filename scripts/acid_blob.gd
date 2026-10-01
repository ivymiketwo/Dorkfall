class_name AcidBlob
extends Node2D
## Vorly's lobbed green blob. A big circle appears on the ground where the
## target was standing and the blob starts crawling toward its centre right
## away. When it arrives it bursts out to the size of the circle and hurts
## everything inside. Place this node at the circle's centre and set
## `launch_from` (a global position) before adding it to the scene.

@export var damage := 250.0
@export var radius := 90.0
@export var travel_time := 2.5
@export var arc_height := 20.0
@export var blob_size := 9.0
var launch_from := Vector2.ZERO

const BURST_TIME := 0.25
const FADE_TIME := 1.0
const RING := Color(0.45, 1.0, 0.25, 0.9)
const FILL := Color(0.30, 0.85, 0.15)

var _t := 0.0
var _burst := false
var _start := Vector2.ZERO          # blob start, local space
var _fx: Node2D
var _trail: Array = []              # [{p, age}]
var _trail_timer := 0.0
var _splash: Array = []             # thrown droplets after the burst


func _ready() -> void:
	_start = to_local(launch_from)
	_fx = Node2D.new()
	_fx.z_index = 5                 # blob and burst draw above characters
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func _progress() -> float:
	return clampf(_t / travel_time, 0.0, 1.0)


func _blob_pos() -> Vector2:
	var p := _progress()
	return _start.lerp(Vector2.ZERO, p) + Vector2(0, -sin(p * PI) * arc_height - 3.0)


func _process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	_t += delta
	if not _burst:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.07
			_trail.append({"p": _blob_pos() + Vector2(randf_range(-2, 2), 2), "age": 0.0})
		if _t >= travel_time:
			_explode()
	for d in _trail:
		d["age"] += delta
	_trail = _trail.filter(func(d): return d["age"] < 0.45)
	if _burst and _t >= travel_time + FADE_TIME:
		queue_free()
		return
	queue_redraw()
	_fx.queue_redraw()


func _explode() -> void:
	_burst = true
	for player in Players.all(get_tree()):
		if AttackRules.circle_hits(to_local(player.global_position), radius):
			AttackRules.deal(player, damage)
	for i in 26:
		_splash.append({"dir": Vector2.from_angle(randf() * TAU), "d": radius * randf_range(0.35, 1.05),
				"r": randf_range(1.6, 3.6), "h": randf_range(8.0, 24.0)})


func _draw() -> void:
	# --- ground marker (drawn under characters) ---
	if not _burst:
		var p := _progress()
		var pulse := 0.5 + 0.5 * sin(_t * 8.0)
		draw_circle(Vector2.ZERO, radius, Color(FILL.r, FILL.g, FILL.b, 0.12 + 0.10 * p))
		draw_circle(Vector2.ZERO, radius * p, Color(FILL.r, FILL.g, FILL.b, 0.22))   # fills as the blob nears
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, Color(RING.r, RING.g, RING.b, 0.65 + 0.3 * pulse), 1.5)
		draw_arc(Vector2.ZERO, radius - 3.0, 0.0, TAU, 56, Color(RING.r, RING.g, RING.b, 0.25), 1.0)
		# shadow of the blob on the ground
		var bp := _blob_pos()
		var ground := Vector2(bp.x, bp.y + sin(p * PI) * arc_height + 3.0)
		draw_set_transform(ground, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, blob_size * 0.9, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# (once it bursts the marker is gone; only the burst effects in _draw_fx remain)


func _draw_fx() -> void:
	if not _burst:
		# slimy trail
		for d in _trail:
			var a: float = 1.0 - d["age"] / 0.45
			_fx.draw_circle(d["p"], 2.2 * a + 0.6, Color(0.62, 0.78, 0.16, 0.6 * a))
		_draw_booger(_blob_pos())
		return
	var b := _t - travel_time
	# expanding burst out to the full marker size
	var k := clampf(b / BURST_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var ring_a := 1.0 - clampf((b - BURST_TIME) / 0.4, 0.0, 1.0)
	if ring_a > 0.0:
		_fx.draw_circle(Vector2.ZERO, radius * e, Color(0.55, 1.0, 0.3, 0.55 * ring_a * (1.0 - k * 0.6)))
		_fx.draw_arc(Vector2.ZERO, radius * e, 0.0, TAU, 56, Color(0.85, 1.0, 0.6, ring_a), 3.0)
		_fx.draw_arc(Vector2.ZERO, maxf(radius * e - 5.0, 0.1), 0.0, TAU, 56, Color(0.4, 0.9, 0.2, ring_a * 0.8), 2.0)
	# droplets thrown out and falling
	for s in _splash:
		var t := clampf(b / 0.7, 0.0, 1.0)
		if t >= 1.0:
			continue
		var pos: Vector2 = s["dir"] * s["d"] * (1.0 - pow(1.0 - minf(t * 1.6, 1.0), 2.0))
		pos.y -= sin(t * PI) * s["h"]
		_fx.draw_circle(pos, s["r"], Color(0.4, 0.9, 0.22, 1.0 - t))


## A lumpy, wiggling booger: a handful of blobs orbiting a centre, outlined
## together so they merge into one gooey shape that keeps changing.
func _draw_booger(c: Vector2) -> void:
	var lobes := 6
	var pts: Array[Vector2] = []
	var rs: Array[float] = []
	for i in lobes:
		var ph := float(i) * 1.7
		var ang := float(i) / float(lobes) * TAU + _t * 2.2 * (1.0 if i % 2 == 0 else -1.0)
		var reach := blob_size * (0.42 + 0.16 * sin(_t * 7.0 + ph))
		pts.append(c + Vector2.from_angle(ang) * reach * Vector2(1.0, 0.85))
		rs.append(blob_size * (0.52 + 0.14 * sin(_t * 9.0 + ph * 1.3)))
	var core := blob_size * (0.75 + 0.08 * sin(_t * 11.0))
	# stringy dangling bit
	var drip := blob_size * (0.7 + 0.5 * (0.5 + 0.5 * sin(_t * 5.0)))
	var dp := c + Vector2(sin(_t * 6.0) * 1.5, blob_size * 0.6)
	# outline pass
	_fx.draw_circle(c, core + 1.4, Color("4a5a12"))
	for i in lobes:
		_fx.draw_circle(pts[i], rs[i] + 1.4, Color("4a5a12"))
	_fx.draw_line(dp, dp + Vector2(0, drip), Color("4a5a12"), 4.0)
	_fx.draw_circle(dp + Vector2(0, drip), 2.6, Color("4a5a12"))
	# body pass
	_fx.draw_circle(c, core, Color("a9cc2c"))
	for i in lobes:
		_fx.draw_circle(pts[i], rs[i], Color("a9cc2c"))
	_fx.draw_line(dp, dp + Vector2(0, drip), Color("a9cc2c"), 2.2)
	_fx.draw_circle(dp + Vector2(0, drip), 1.6, Color("a9cc2c"))
	# darker underside + glossy highlights
	_fx.draw_circle(c + Vector2(0.8, 2.6), core * 0.62, Color("86a81f"))
	_fx.draw_circle(c + Vector2(-blob_size * 0.3, -blob_size * 0.32), blob_size * 0.26, Color("e6f68f"))
	_fx.draw_circle(c + Vector2(blob_size * 0.22, -blob_size * 0.05), blob_size * 0.12, Color("e6f68f"))

## Called if whoever cast this dies: gone instantly, no damage.
func _cancel() -> void:
	set_process(false)
	hide()
	queue_free()
