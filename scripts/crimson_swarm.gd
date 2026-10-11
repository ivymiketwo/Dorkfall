class_name CrimsonSwarm
extends Node2D
## The Crimson Swarm spell: a swarm of snaking red beams shoots up out of the staff, arcs over
## and slams straight down onto a tight cluster of small circles around the target spot (the
## circles touch but never overlap). Each beam hits everything in its circle the moment it
## lands, and Rex's red flame (art/crimson_flame.png) bursts up there.
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
## Part of the flight spent climbing (the rest is the slam down).
const RISE := 0.55
## How much of the curve the climb covers.
const RISE_PATH := 0.6
## Tail length, in flight time.
const TRAIL := 0.22

const DARK := Color(0.55, 0.04, 0.05)
const RED := Color(0.9, 0.1, 0.08)
const HOT := Color(1.0, 0.42, 0.25)
const CORE := Color(1.0, 0.86, 0.7)

var _timeline: AttackTimeline
var _t := 0.0
var _start := Vector2.ZERO       # launch point, local space
var _beams: Array = []           # each: {spot, p1, p2, delay, flight, land, swirl, turns, ph, flick}
var _fx: Node2D                  # beams and flames, drawn above characters


func _ready() -> void:
	_start = to_local(launch_from)
	var spots := _pick_spots()
	_timeline = AttackTimeline.new()
	var last := 0.0
	var reach := 0.0
	for s in spots:
		reach = maxf(reach, (s as Vector2).length())
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var delay := float(i) * 0.04 + Rng.randf_range(0.0, 0.03)
		var flight := Rng.randf_range(0.8, 0.95)
		# up out of the staff, over the top, then straight down onto its circle
		var apex := minf(_start.y, spot.y) - Rng.randf_range(55.0, 75.0)
		var toward := Vector2(0.0 - _start.x, 0.0) * Rng.randf_range(0.15, 0.35)   # leans toward the cluster
		var b := {"spot": spot,
				"p1": Vector2(_start.x + toward.x + Rng.randf_range(-14.0, 14.0), apex - Rng.randf_range(0.0, 15.0)),
				"p2": Vector2(spot.x + Rng.randf_range(-reach, reach) * 0.4, apex - Rng.randf_range(0.0, 10.0)),
				"delay": delay, "flight": flight, "land": delay + flight,
				"swirl": Rng.randf_range(3.0, 5.0), "turns": Rng.randf_range(1.2, 2.0),
				"ph": Rng.randf() * TAU, "flick": randf() * 10.0}
		_beams.append(b)
		_timeline.at(b["land"], _land.bind(i))
		last = maxf(last, b["land"])
	_timeline.lasts(last + FLAME_TIME + 0.3)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


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


## How far along its curve (0..1) a beam is, `s` (0..1) of the way through its flight:
## a quick climb that slows at the top, then a slam that keeps speeding up.
static func _progress(s: float) -> float:
	if s < RISE:
		var k := s / RISE
		return RISE_PATH * (1.0 - (1.0 - k) * (1.0 - k))
	var k := (s - RISE) / (1.0 - RISE)
	return RISE_PATH + (1.0 - RISE_PATH) * k * k * k


## Where beam `b` is at curve position `u`: up out of the staff, over, and straight down
## (the last stretch is vertical). The climb snakes; the slam is straight.
func _path(b: Dictionary, u: float) -> Vector2:
	var p0 := _start
	var p1: Vector2 = b["p1"]
	var p2: Vector2 = b["p2"]
	var p3: Vector2 = b["spot"]
	var v := 1.0 - u
	var base := p0 * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + p3 * (u * u * u)
	var climb := clampf(u / RISE_PATH, 0.0, 1.0)
	var swirl: Vector2 = Vector2.from_angle(b["ph"] + climb * TAU * b["turns"]) * float(b["swirl"]) * sin(PI * climb)
	return base + swirl


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
	for b in _beams:
		var s: float = (_t - b["delay"]) / b["flight"]
		if s > 0.0 and s < 1.0 + TRAIL:
			_draw_beam(b, s)
		var since: float = _t - b["land"]
		if since >= 0.0 and since < FLAME_TIME:
			_draw_flame(b["spot"], since, b["flick"])


## The beam: a fading red tail behind a bright head. The tail covers the last part of the
## flight, so it stretches into a long streak as the beam slams down. After it lands the
## tail catches up.
func _draw_beam(b: Dictionary, s: float) -> void:
	var head := minf(s, 1.0)
	var tail := maxf(s - TRAIL, 0.0)
	if head - tail <= 0.001:
		return
	var n := 16
	var prev := _path(b, _progress(tail))
	for k in range(1, n + 1):
		var p := _path(b, _progress(lerpf(tail, head, float(k) / float(n))))
		var a := float(k) / float(n)            # 0 at the tail, 1 at the head
		_fx.draw_line(prev, p, Color(DARK.r, DARK.g, DARK.b, 0.5 * a), 2.0)
		_fx.draw_line(prev, p, Color(RED.r, RED.g, RED.b, a), 1.0)
		prev = p
	if s < 1.0:
		var hp := _path(b, _progress(head)).snapped(Vector2(0.5, 0.5))
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
