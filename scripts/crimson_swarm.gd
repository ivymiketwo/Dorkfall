class_name CrimsonSwarm
extends Node2D
## The Crimson Swarm spell: a swarm of snaking red beams leaves the staff and lands on a
## cluster of small circles around the target spot (circles never overlap). Each beam hits
## everything in its circle the moment it lands, and a small red torch flame bursts up there.
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
const FLAME_TIME := 0.6
const TRAIL := 0.32             # how much of its path a beam's tail covers
const GAP := 1.0                # world px kept between neighbouring circles

## Flame colours, outside to inside.
const DARK := Color(0.55, 0.04, 0.05)
const RED := Color(0.9, 0.1, 0.08)
const HOT := Color(1.0, 0.42, 0.25)
const CORE := Color(1.0, 0.86, 0.7)

var _timeline: AttackTimeline
var _t := 0.0
var _start := Vector2.ZERO       # launch point, local space
var _beams: Array = []           # each: {spot, ctrl, delay, flight, land, swirl, turns, ph, landed, flick}
var _fx: Node2D                  # beams and flames, drawn above characters


func _ready() -> void:
	_start = to_local(launch_from)
	var spots := _pick_spots()
	_timeline = AttackTimeline.new()
	var last := 0.0
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var delay := float(i) * 0.035 + Rng.randf_range(0.0, 0.03)
		var flight := Rng.randf_range(0.42, 0.58)
		var mid := _start.lerp(spot, 0.5)
		var along := (spot - _start).normalized() if spot.distance_to(_start) > 1.0 else Vector2.DOWN
		var side := Vector2(-along.y, along.x) * Rng.randf_range(6.0, 18.0) * (1.0 if i % 2 == 0 else -1.0)
		var b := {"spot": spot, "ctrl": mid + side + Vector2(0, -Rng.randf_range(6.0, 16.0)),
				"delay": delay, "flight": flight, "land": delay + flight,
				"swirl": Rng.randf_range(5.0, 8.0), "turns": Rng.randf_range(2.0, 3.0),
				"ph": Rng.randf() * TAU, "landed": false, "flick": randf() * TAU}
		_beams.append(b)
		_timeline.at(b["land"], _land.bind(i))
		last = maxf(last, b["land"])
	_timeline.lasts(last + FLAME_TIME + 0.3)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


## Up to `count` non-overlapping circles packed around the target (local space).
func _pick_spots() -> Array:
	var spots: Array = []
	var min_d := spot_radius * 2.0 + GAP
	var area := float(count) * PI * pow(min_d * 0.5, 2.0) / 0.5      # loose random packing
	var reach := sqrt(area / PI)
	var tries := 0
	while spots.size() < count:
		tries += 1
		if tries % 60 == 0:
			reach += 2.0                    # crowded: let the cluster spread a little wider
		var p := Vector2.from_angle(Rng.randf() * TAU) * reach * sqrt(Rng.randf())
		var ok := true
		for q in spots:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if ok:
			spots.append(p)
	return spots


func _physics_process(delta: float) -> void:
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


## A beam lands: everything standing in its circle takes the hit.
func _land(i: int) -> void:
	var b: Dictionary = _beams[i]
	b["landed"] = true
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


## Where beam `b` is `u` (0..1) of the way along its path: a curve from the staff to its
## circle, with a loop-de-loop swirl on top that dies away at both ends.
func _path(b: Dictionary, u: float) -> Vector2:
	var a: Vector2 = _start.lerp(b["ctrl"], u)
	var c: Vector2 = (b["ctrl"] as Vector2).lerp(b["spot"], u)
	var base := a.lerp(c, u)
	var swirl: Vector2 = Vector2.from_angle(b["ph"] + u * TAU * b["turns"]) * float(b["swirl"]) * sin(PI * u)
	return base + Vector2(swirl.x, swirl.y * 0.6)


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
			draw_arc(spot, spot_radius, 0.0, TAU, 20, Color(HOT.r, HOT.g, HOT.b, 0.55 + 0.3 * k), 1.0)
		else:
			var f := 1.0 - clampf(since / (FLAME_TIME + 0.3), 0.0, 1.0)
			draw_circle(spot, spot_radius, Color(0.12, 0.02, 0.02, 0.45 * f))      # scorch
			var ring := clampf(since / 0.18, 0.0, 1.0)
			if ring < 1.0:
				draw_arc(spot, spot_radius * (1.0 + ring * 0.6), 0.0, TAU, 20, Color(CORE.r, CORE.g, CORE.b, 1.0 - ring), 1.0)


func _draw_fx() -> void:
	for b in _beams:
		var u: float = (_t - b["delay"]) / b["flight"]
		if u > 0.0 and u < 1.0 + TRAIL:
			_draw_beam(b, u)
		var since: float = _t - b["land"]
		if since >= 0.0 and since < FLAME_TIME:
			_draw_flame(b["spot"], since / FLAME_TIME, b["flick"])


## The beam: a fading red tail behind a bright head. After it lands the tail catches up.
func _draw_beam(b: Dictionary, u: float) -> void:
	var head := minf(u, 1.0)
	var tail := maxf(u - TRAIL, 0.0)
	if head - tail <= 0.001:
		return
	var n := 12
	var prev := _path(b, tail)
	for k in range(1, n + 1):
		var v := lerpf(tail, head, float(k) / float(n))
		var p := _path(b, v)
		var a := float(k) / float(n)            # 0 at the tail, 1 at the head
		_fx.draw_line(prev, p, Color(DARK.r, DARK.g, DARK.b, 0.5 * a), 2.0)
		_fx.draw_line(prev, p, Color(RED.r, RED.g, RED.b, a), 1.0)
		prev = p
	if u < 1.0:
		var hp := _path(b, head).snapped(Vector2(0.5, 0.5))
		_fx.draw_rect(Rect2(hp - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), HOT)
		_fx.draw_rect(Rect2(hp - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), CORE)


## A small, intense torch flame bursting up from a circle. `k` = 0..1 through its life.
func _draw_flame(at: Vector2, k: float, flick: float) -> void:
	# shoots up fast, holds, then sinks and thins out
	var grow := 1.0 - pow(1.0 - clampf(k / 0.18, 0.0, 1.0), 3.0)
	var sink := 1.0 - clampf((k - 0.55) / 0.45, 0.0, 1.0)
	var h := 13.0 * grow * (0.35 + 0.65 * sink)
	var w := spot_radius * 0.75 * (0.5 + 0.5 * sink)
	if h < 1.0:
		return
	var rows := int(h * 2.0)                      # one row per screen pixel
	for r in rows:
		var y := float(r) / float(rows)           # 0 at the base, 1 at the tip
		var sway := sin(_t * 30.0 + flick + y * 5.0) * 1.2 * y
		var half := w * pow(1.0 - y, 0.8) * (0.85 + 0.15 * sin(_t * 41.0 + flick + y * 9.0))
		var py := at.y - float(r) * 0.5
		var cx := at.x + sway
		_row(cx, py, half, DARK)
		_row(cx, py, half * 0.72, RED)
		if y < 0.75:
			_row(cx, py, half * 0.42, HOT)
		if y < 0.4:
			_row(cx, py, half * 0.2, CORE)
	# a few embers flicking up off the top
	for e in 3:
		var life := fposmod(k * 1.6 + float(e) * 0.33, 1.0)
		var ex := at.x + sin(flick + float(e) * 2.1 + life * 6.0) * 3.0
		var ey := at.y - h * 0.6 - life * 10.0
		_fx.draw_rect(Rect2(Vector2(ex, ey).snapped(Vector2(0.5, 0.5)), Vector2(0.5, 0.5)),
				Color(HOT.r, HOT.g, HOT.b, (1.0 - life) * sink))


func _row(cx: float, y: float, half: float, col: Color) -> void:
	if half < 0.25:
		return
	var x0 := snappedf(cx - half, 0.5)
	var x1 := snappedf(cx + half, 0.5)
	_fx.draw_rect(Rect2(x0, y - 0.5, maxf(x1 - x0, 0.5), 0.5), col)
