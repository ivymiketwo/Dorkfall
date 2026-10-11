class_name CrimsonSwarm
extends Node2D
## The Crimson Swarm spell: the staff fires the red beam up to a point above the target; from
## the beam's tip a swarm of missiles is thrown up like a fountain, each on a ballistic arc,
## and comes down onto a tight cluster of small circles around the target (the
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
const BURST_HEIGHT := 40.0
## When the missiles start coming out of the tip (the beam fires at 0).
const EMIT_AT := 0.05
## Each bit of a missile's trail fades out this long after the missile passed it, so the
## start of a trail (by the knot) is gone by the time the spell ends and the rest follows.
const TRAIL_LIFE := 1.6
## Everything left fades over this long at the very end.
const TRAIL_FADE := 0.25
## The tightest known way to fit 15 circles (radius 1) inside one circle (its radius: 4.52).
## The cluster uses this, turned to a random angle, so the target area is as small and round
## as it can be. Other counts fall back to a honeycomb blob.
const PACK_15 := [Vector2(-3.457, -0.669), Vector2(1.213, -1.193), Vector2(1.541, -3.166),
		Vector2(-0.760, -1.522), Vector2(1.510, 0.784), Vector2(0.614, 3.467), Vector2(-2.535, -2.444),
		Vector2(-0.280, 1.678), Vector2(3.487, 0.487), Vector2(-1.682, 0.253), Vector2(-3.108, 1.656),
		Vector2(-0.432, -3.495), Vector2(-1.705, 3.081), Vector2(3.190, -1.490), Vector2(2.403, 2.574)]
## As the missiles fall, the whole cluster turns counter-clockwise by this much: each missile
## starts out over the spot this far clockwise of its own circle and twists onto it.
const TWIST := deg_to_rad(65.0)
## The laser: the same as the Red Beam ability.
const LASER_COLOR := Color(1, 0.15, 0.12, 1)

const EDGE := Color(0.25, 0.01, 0.03)
const DARK := Color(0.55, 0.04, 0.05)
const RED := Color(0.9, 0.1, 0.08)
const HOT := Color(1.0, 0.42, 0.25)
const CORE := Color(1.0, 0.86, 0.7)

var _timeline: AttackTimeline
var _t := 0.0
var _start := Vector2.ZERO       # launch point, local space
var _tip := Vector2.ZERO         # the beam's tip, local space
var _beams: Array = []           # each missile: {spot, vy, ay, apex, delay, float, slam, flight, land, flick}
var _fx: Node2D                  # beams and flames, drawn above characters


func _ready() -> void:
	_start = to_local(launch_from)
	var spots := _pick_spots()
	_timeline = AttackTimeline.new()
	var last := 0.0
	_tip = Vector2(0.0, -BURST_HEIGHT)
	# missiles fan out of the tip in every direction but straight down (left ones land on the
	# left circles), each on a clean ballistic arc
	spots.sort_custom(func(a, b): return a.x < b.x)
	var n := spots.size()
	for i in n:
		var spot: Vector2 = spots[i]
		# a fountain: every missile is thrown up out of the knot to its own height, then falls
		# onto its circle. The arc is a parabola: y = tip.y + vy*u + ay*u*u, x straight across.
		var drop := spot.y - _tip.y                       # how far below the knot it lands
		var h := Rng.randf_range(14.0, 30.0)             # how high above the knot it climbs
		var vy := -2.0 * h - 2.0 * sqrt(h * h + h * drop)
		var ay := drop - vy
		var delay := EMIT_AT + float(i) * 0.012 + Rng.randf_range(0.0, 0.015)
		var float_t := Rng.randf_range(0.4, 0.46)        # drifting up and lingering at the top
		var slam := Rng.randf_range(0.12, 0.16)          # then slamming down
		var flight := float_t + slam
		var b := {"spot": spot,
				"vy": vy, "ay": ay, "apex": -vy / (2.0 * ay),
				# drifts out to its side on the way up, falls back in onto its circle
				"out": (float(i) / float(maxi(n - 1, 1)) * 2.0 - 1.0) * Rng.randf_range(18.0, 28.0),
				"delay": delay, "float": float_t, "slam": slam, "flight": flight, "land": delay + flight,
				"flick": randf() * 10.0}
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


## Where the circles go (local space, centred on the target): for 15, the tightest round
## packing (PACK_15) at a random angle; otherwise a honeycomb blob (neighbours touching).
func _pick_spots() -> Array:
	if count == PACK_15.size():
		var turn := Rng.randf() * TAU
		var out: Array = []
		for q in PACK_15:
			out.append((q as Vector2).rotated(turn) * spot_radius * 1.001)   # (rounding: never overlap)
		return out
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


## How far along its curve (0..1) missile `b` is `r` seconds after leaving the knot: it floats
## up and over, slowing at the top of the fountain (about 0.25 s), then slams down fast.
static func _progress(b: Dictionary, r: float) -> float:
	if r <= 0.0:
		return 0.0
	var apex: float = b["apex"]
	if r < b["float"]:
		var k: float = r / b["float"]
		return apex * (1.0 - pow(1.0 - k, 3.0))          # up to the top of its arc, lingering there
	var k := clampf((r - b["float"]) / b["slam"], 0.0, 1.0)
	return apex + (1.0 - apex) * k * k                   # then down, faster and faster


## The other way round: seconds after leaving the knot when missile `b` was at arc position `u`.
static func _time_at(b: Dictionary, u: float) -> float:
	var apex: float = b["apex"]
	if u <= apex:
		return float(b["float"]) * (1.0 - pow(maxf(1.0 - u / apex, 0.0), 1.0 / 3.0))
	return float(b["float"]) + float(b["slam"]) * sqrt(clampf((u - apex) / (1.0 - apex), 0.0, 1.0))


## Where missile `b` is at arc position `u` (0 = the knot, 1 = its circle): a parabola up and
## down, swinging out to its side near the top and back in as it falls, while the whole
## cluster twists counter-clockwise onto the circles.
func _path(b: Dictionary, u: float) -> Vector2:
	var spot: Vector2 = b["spot"]
	var apex: float = b["apex"]
	# the sideways drift peaks around the top of the arc and is gone at both ends
	var shape := log(0.5) / log(clampf(apex + 0.1, 0.2, 0.8))
	var drift := float(b["out"]) * sin(PI * pow(u, shape))
	# split into where it is over the ground and how high it is, so the twist turns only the
	# ground position (round the cluster's middle, right under the knot)
	var screen_y := _tip.y + float(b["vy"]) * u + float(b["ay"]) * u * u
	var height := spot.y * u - screen_y          # height above the ground (the arc's own shape)
	var fall := clampf((u - apex) / maxf(1.0 - apex, 0.01), 0.0, 1.0)
	# over the ground: out to its circle's distance from the middle by the top of the arc, then
	# swung round at that distance while falling, so each trail draws a twisting spiral
	var reach := clampf(u / maxf(apex, 0.01), 0.0, 1.0)
	reach = 1.0 - (1.0 - reach) * (1.0 - reach)
	var ground := (spot * reach).rotated(TWIST * (1.0 - fall)) + Vector2(drift, 0.0)
	return Vector2(ground.x, ground.y - height)


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
	for b in _beams:
		if _t > b["delay"]:
			_draw_missile(b, _t - b["delay"])
		var since: float = _t - b["land"]
		if since >= 0.0 and since < FLAME_TIME:
			_draw_flame(b["spot"], since, b["flick"])


## A missile: its trail from the knot to the bright head. Each part fades a while after the
## missile passed it, so the trail disappears from the knot end first.
func _draw_missile(b: Dictionary, r: float) -> void:
	var head := _progress(b, r)
	if head <= 0.001:
		return
	var fade := clampf((_timeline.end_time - _t) / TRAIL_FADE, 0.0, 1.0)
	var n := 28
	var prev := _path(b, 0.0)
	for j in range(1, n + 1):
		var u := head * float(j) / float(n)
		var p := _path(b, u)
		var age := r - _time_at(b, u)                             # how long ago the missile was here
		var a := (0.55 + 0.45 * float(j) / float(n)) * fade * (1.0 - pow(clampf(age / TRAIL_LIFE, 0.0, 1.0), 2.0))
		# feathered, darker toward the edge for contrast: dark outer fringe, deep red, bright core
		_fx.draw_line(prev, p, Color(EDGE.r, EDGE.g, EDGE.b, 0.4 * a), 3.0)
		_fx.draw_line(prev, p, Color(DARK.r, DARK.g, DARK.b, 0.7 * a), 2.0)
		_fx.draw_line(prev, p, Color(RED.r, RED.g, RED.b, a), 1.0)
		prev = p
	if head < 1.0:
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
