class_name CrimsonSwarm
extends Node2D
## The Crimson Swarm spell: the staff fires the red beam up to a point above the target; from
## the beam's tip a swarm of missiles bursts out in loops (like the petals of a flower), then
## curves back and comes down onto a tight cluster of small circles around the target (the
## circles touch but never overlap). The missiles start slow and keep speeding up. Each one
## hits everything in its circle the moment it lands, and Rex's red flame
## (art/crimson_flame.png) bursts up there.
##
## Place this node at the target spot and set `caster`, `launch_from` (global), `count`,
## `spot_radius` and `damage` before adding it. The rules (where the circles are, when each
## one lands, who it hits) are picked with Rng and run on the game tick through
## AttackTimeline; everything else is only drawing.

var caster: Node2D
var launch_from := Vector2.ZERO
var count := 10
var spot_radius := 6.0
var damage := 15.0

const HIT_SOUND := preload("res://audio/fireball_hit.wav")
const FLAME_TEX := preload("res://art/crimson_flame.png")
## art/crimson_flame.png (made by tools/gen_crimson_flame.py): 26x30 art px frames,
## 0-2 burst, 3-8 flicker loop, 9-11 die down. Drawn at half size (1 art px = 0.5 world px).
const FLAME_FW := 26
const FLAME_FH := 30
const BURST_FPS := 25.0
const LOOP_FPS := 15.0
const DIE_FPS := 16.0
const FLAME_TIME := 0.75
## The beam's tip (where the missiles burst out) is this high above the target.
const BURST_HEIGHT := 50.0
## When the missiles start coming out of the tip (the beam fires at 0).
const EMIT_AT := 0.05
## A missile's tail, as a share of its flight time (it stretches into a streak as it speeds up).
const TRAIL := 0.3
## Smoke left behind by each missile: a puff every SMOKE_STEP seconds, lasting SMOKE_LIFE.
const SMOKE_STEP := 0.02
const SMOKE_LIFE := 0.5
const SMOKE := Color(0.62, 0.58, 0.58)
## The laser: the same as the Red Beam ability.
const LASER_COLOR := Color(1, 0.15, 0.12, 1)

const DARK := Color(0.55, 0.04, 0.05)
const RED := Color(0.9, 0.1, 0.08)
const HOT := Color(1.0, 0.42, 0.25)
const CORE := Color(1.0, 0.86, 0.7)

var _timeline: AttackTimeline
var _t := 0.0
var _start := Vector2.ZERO       # launch point, local space
var _tip := Vector2.ZERO         # the beam's tip, local space
var _beams: Array = []           # each missile: {spot, p1, p2, delay, flight, land, flick}
var _fx: Node2D                  # beams and flames, drawn above characters


func _ready() -> void:
	_start = to_local(launch_from)
	var spots := _pick_spots()
	_timeline = AttackTimeline.new()
	var last := 0.0
	_tip = Vector2(0.0, -BURST_HEIGHT)
	# missiles fan out of the tip in every direction but straight down (left ones land on the
	# left circles, so the loops don't tangle), loop round and come down onto their circles
	spots.sort_custom(func(a, b): return a.x < b.x)
	var n := spots.size()
	for i in n:
		var spot: Vector2 = spots[i]
		var f := float(i) / float(maxi(n - 1, 1))
		var ang := deg_to_rad(-90.0 + (f - 0.5) * 290.0 + Rng.randf_range(-12.0, 12.0))
		var delay := EMIT_AT + float(i) * 0.012 + Rng.randf_range(0.0, 0.015)
		var flight := Rng.randf_range(0.62, 0.78)
		var b := {"spot": spot,
				"p1": _tip + Vector2.from_angle(ang) * Rng.randf_range(48.0, 70.0),
				"p2": spot + Vector2(Rng.randf_range(-3.0, 3.0), -Rng.randf_range(22.0, 32.0)),
				"delay": delay, "flight": flight, "land": delay + flight, "flick": randf() * 10.0,
				"wob": randf() * TAU}
		_beams.append(b)
		_timeline.at(b["land"], _land.bind(i))
		last = maxf(last, b["land"])
	_timeline.lasts(last + FLAME_TIME + 0.3)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_fire_laser.call_deferred()


## The red beam from the staff to the burst point (only a flash: it doesn't hurt anything).
func _fire_laser() -> void:
	var host := caster.get_parent() if caster != null and is_instance_valid(caster) else get_parent()
	var to := to_global(_tip) - launch_from
	var fx := BeamFx.new()
	fx.global_position = launch_from
	fx.direction = to.normalized() if to.length() > 1.0 else Vector2.UP
	fx.length = to.length()
	fx.tint = LASER_COLOR
	fx.lightning = true
	fx.z_index = 4
	host.add_child(fx)


## `count` circles packed edge to edge (a honeycomb, so neighbours touch exactly), in a
## slightly irregular blob centred on the target (local space).
func _pick_spots() -> Array:
	var d := spot_radius * 2.0
	var rot := Rng.randf() * TAU
	var centre := Vector2.from_angle(Rng.randf() * TAU) * d * 0.5 * Rng.randf()
	var cells: Array = []
	for j in range(-5, 6):
		for i in range(-5, 6):
			var p := (Vector2(d, 0.0) * float(i) + Vector2(d * 0.5, d * 0.8660254) * float(j)).rotated(rot)
			cells.append({"p": p, "score": p.distance_to(centre) + Rng.randf() * d * 0.45})
	cells.sort_custom(func(a, b): return a["score"] < b["score"])
	var spots: Array = []
	var mid := Vector2.ZERO
	for k in mini(count, cells.size()):
		spots.append(cells[k]["p"])
		mid += cells[k]["p"]
	mid /= float(spots.size())
	for k in spots.size():
		spots[k] -= mid                 # the blob's middle lands on the mouse
	return spots


func _physics_process(delta: float) -> void:
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


## A beam lands: everything standing in its circle takes the hit.
func _land(i: int) -> void:
	var b: Dictionary = _beams[i]
	var at := to_global(b["spot"])
	var shape := CircleShape2D.new()
	shape.radius = spot_radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	var seen := {}
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var body := hit["collider"] as Node2D
		if body == null or seen.has(body) or not AttackRules.can_hurt(caster, body):
			continue
		seen[body] = true
		AttackRules.deal(body, damage, caster)
	if i % 3 == 0:                       # a few crackles, not ten at once
		var s := AudioStreamPlayer2D.new()
		s.stream = HIT_SOUND
		s.volume_db = -12.0
		s.pitch_scale = randf_range(1.3, 1.7)
		s.finished.connect(s.queue_free)
		get_parent().add_child(s)
		s.global_position = at
		s.play()


## How far along its curve (0..1) a missile is, `k` (0..1) of the way through its flight:
## it leaves the beam's tip slowly and keeps speeding up until it hits.
static func _progress(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 0.25 * k + 0.75 * k * k * k


## Where missile `b` is at curve position `u`: out of the tip, round in a loop, and down
## onto its circle (the last stretch comes straight down).
func _path(b: Dictionary, u: float) -> Vector2:
	var p1: Vector2 = b["p1"]
	var p2: Vector2 = b["p2"]
	var p3: Vector2 = b["spot"]
	var v := 1.0 - u
	var base := _tip * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + p3 * (u * u * u)
	# a jittery missile wobble (drawing only), gone by the time it comes down
	var w := sin(u * 40.0 + b["wob"]) * 1.5 * (1.0 - u)
	return base + Vector2(w, w * 0.6)


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


## On the ground: the circles show where the beams will land and fill in as they arrive,
## then leave a fading scorch mark.
func _draw() -> void:
	for b in _beams:
		var spot: Vector2 = b["spot"]
		var since: float = _t - b["land"]
		if since < 0.0:
			var k := clampf((_t - b["delay"]) / b["flight"], 0.0, 1.0)
			draw_circle(spot, spot_radius, Color(RED.r, RED.g, RED.b, 0.12 + 0.12 * k))
			draw_circle(spot, spot_radius * k, Color(RED.r, RED.g, RED.b, 0.18))
			draw_arc(spot, spot_radius - 0.5, 0.0, TAU, 20, Color(HOT.r, HOT.g, HOT.b, 0.55 + 0.3 * k), 1.0)
		else:
			var f := 1.0 - clampf(since / (FLAME_TIME + 0.3), 0.0, 1.0)
			draw_circle(spot, spot_radius, Color(0.12, 0.02, 0.02, 0.45 * f))      # scorch
			var ring := clampf(since / 0.18, 0.0, 1.0)
			if ring < 1.0:
				draw_arc(spot, spot_radius * (1.0 + ring * 0.6), 0.0, TAU, 20, Color(CORE.r, CORE.g, CORE.b, 1.0 - ring), 1.0)


func _draw_fx() -> void:
	# the knot of light at the beam's tip while the missiles pour out of it
	var last_out: float = _beams[-1]["delay"] if not _beams.is_empty() else 0.0
	if _t < last_out + 0.2:
		var k := 1.0 - clampf((_t - last_out) / 0.2, 0.0, 1.0)
		var r := (2.5 + 0.5 * sin(_t * 50.0)) * k
		_fx.draw_circle(_tip, r + 1.0, Color(DARK.r, DARK.g, DARK.b, 0.6))
		_fx.draw_circle(_tip, r, RED)
		_fx.draw_circle(_tip, r * 0.5, CORE)
	_draw_smoke()
	for b in _beams:
		var k: float = (_t - b["delay"]) / b["flight"]
		if k > 0.0 and k < 1.0 + TRAIL:
			_draw_missile(b, k)
		var since: float = _t - b["land"]
		if since >= 0.0 and since < FLAME_TIME:
			_draw_flame(b["spot"], since, b["flick"])


## Missile-massacre smoke: every missile leaves a trail of grey puffs that swell and fade.
func _draw_smoke() -> void:
	for b in _beams:
		var t0: float = b["delay"]
		var end: float = minf(_t, b["land"])
		var j := 0
		while t0 + float(j) * SMOKE_STEP <= end:
			var at := t0 + float(j) * SMOKE_STEP
			var age := _t - at
			j += 1
			if age > SMOKE_LIFE:
				continue
			var k := age / SMOKE_LIFE
			var pos := _path(b, _progress((at - t0) / b["flight"])) + Vector2(0, -k * 3.0)
			var r := 0.7 + k * 2.6
			_fx.draw_circle(pos.snapped(Vector2(0.5, 0.5)), r, Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.4 * (1.0 - k)))


## A missile: a bright head with a fading tail covering the last part of its flight, so the
## tail is short while it is slow and stretches into a streak as it speeds up. After it
## lands the tail catches up.
func _draw_missile(b: Dictionary, k: float) -> void:
	var head := _progress(k)
	var tail := _progress(k - TRAIL)
	if head - tail <= 0.001:
		return
	var n := 16
	var prev := _path(b, tail)
	for j in range(1, n + 1):
		var p := _path(b, lerpf(tail, head, float(j) / float(n)))
		var a := float(j) / float(n)            # 0 at the tail, 1 at the head
		_fx.draw_line(prev, p, Color(DARK.r, DARK.g, DARK.b, 0.5 * a), 2.0)
		_fx.draw_line(prev, p, Color(RED.r, RED.g, RED.b, a), 1.0)
		prev = p
	if k < 1.0:
		var hp := _path(b, head).snapped(Vector2(0.5, 0.5))
		_fx.draw_rect(Rect2(hp - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), HOT)
		_fx.draw_rect(Rect2(hp - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), CORE)


## Rex's flame: bursts up, flickers, dies down. `since` = seconds since it landed.
func _draw_flame(at: Vector2, since: float, flick: float) -> void:
	var burst := 3.0 / BURST_FPS
	var die_at := FLAME_TIME - 3.0 / DIE_FPS
	var frame: int
	if since < burst:
		frame = int(since * BURST_FPS)
	elif since < die_at:
		frame = 3 + posmod(int((since - burst) * LOOP_FPS + flick), 6)
	else:
		frame = 9 + mini(int((since - die_at) * DIE_FPS), 2)
	var size := Vector2(FLAME_FW, FLAME_FH) * 0.5
	var pos := (at + Vector2(-size.x * 0.5, -size.y + 2.0)).snapped(Vector2(0.5, 0.5))   # base just below the circle's middle
	_fx.draw_texture_rect_region(FLAME_TEX, Rect2(pos, size), Rect2(frame * FLAME_FW, 0, FLAME_FW, FLAME_FH))
