class_name CrimsonSwarm
extends Node2D
## The Crimson Swarm spell: the staff fires the red beam up to a point above the target; from
## the beam's tip a swarm of missiles is thrown up like a fountain, each on a ballistic arc,
## and comes down onto a tight cluster of small circles around the target (the
## circles touch but never overlap). The missiles start slow and keep speeding up. Each one
## hits everything in its circle the moment it lands, and Rex's red flame
## (art/crimson_flame.png) bursts up there.
##
## With `stream` on (the Crimson Barrage spell) the knot hovers instead and shoots one missile
## every `interval` seconds, `count` in all; each lands on its own circle wherever the caster
## is aiming at the moment it leaves the knot (no further than `max_reach` from the caster).
##
## Place this node at the target spot and set `caster`, `launch_from` (global), `count`,
## `spot_radius` and `damage` (and the stream settings) before adding it. The rules (where the circles are, when each
## one lands, who it hits) are picked with Rng and run on the game tick through
## AttackTimeline; everything else is only drawing.

var caster: Node2D
var launch_from := Vector2.ZERO
var count := 10
var spot_radius := 6.0
var damage := 15.0
## Crimson Barrage: one missile at a time from a hovering knot, aimed at the cursor.
var stream := false
var interval := 0.5
var max_reach := 170.0

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
## Crimson Swarm's fountain: how high above the knot the missiles climb, and how far (about)
## each drifts out on its own side at the top.
const SWARM_MIN_H := 12.0
const SWARM_MAX_H := 18.0
const SWARM_SPREAD := 19.0
## Crimson Barrage: the knot hovers this high above the caster's feet and moves with them.
const KNOT_ABOVE := 38.0
## How far (world px) a missile drifts toward its circle while rising; the rest of the way is
## covered by the slam, so fountain trails stay short however far away the circle is.
const FOUNTAIN_TRAVEL := 12.0
## When the missiles start coming out of the tip (the beam fires at 0).
const EMIT_AT := 0.05
## Each bit of a missile's trail fades out this long after the missile passed it, so the
## start of a trail (by the knot) is gone by the time the spell ends and the rest follows.
const TRAIL_LIFE := 1.6
## The fountain part of a trail (drawn while rising) fades sooner than the slam part.
const FOUNTAIN_TRAIL_LIFE := 0.9
## Everything left fades over this long at the very end.
const TRAIL_FADE := 0.25
## The tightest known way to fit 15 circles (radius 1) inside one circle (its radius: 4.52).
## The cluster uses this, turned to a random angle, so the target area is as small and round
## as it can be. Other counts fall back to a honeycomb blob.
const PACK_15 := [Vector2(-3.457, -0.669), Vector2(1.213, -1.193), Vector2(1.541, -3.166),
		Vector2(-0.760, -1.522), Vector2(1.510, 0.784), Vector2(0.614, 3.467), Vector2(-2.535, -2.444),
		Vector2(-0.280, 1.678), Vector2(3.487, 0.487), Vector2(-1.682, 0.253), Vector2(-3.108, 1.656),
		Vector2(-0.432, -3.495), Vector2(-1.705, 3.081), Vector2(3.190, -1.490), Vector2(2.403, 2.574)]
## Pulls the packed circles a touch closer than touching (a smidge of overlap).
const PACK_SQUEEZE := 0.94
## As the missiles fall, the whole cluster turns counter-clockwise by this much: each missile
## starts out over the spot this far clockwise of its own circle and twists onto it.
const TWIST := deg_to_rad(65.0)
## The laser: the same as the Red Beam ability.
const LASER_COLOR := Color(1, 0.15, 0.12, 1)

## Beam colours (laser knot, missile trails): outer fringe, mid, core, head, hot centre.
## (Swap these to recolour the beams; the circles and fire use the colours below.)
const B_EDGE := Color(0.25, 0.01, 0.03)
const B_DARK := Color(0.55, 0.04, 0.05)
const B_MAIN := Color(0.9, 0.1, 0.08)
const B_HOT := Color(1.0, 0.42, 0.25)
const B_CORE := Color(1.0, 0.86, 0.7)
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
	_timeline = AttackTimeline.new()
	_tip = Vector2(0.0, -BURST_HEIGHT)
	var last := 0.0
	if stream:
		# one missile every `interval` seconds; where each lands is picked when it leaves
		for i in count:
			var b := _new_missile(EMIT_AT + float(i) * interval)
			_beams.append(b)
			_timeline.at(b["delay"], _launch.bind(i))
			_timeline.at(b["land"], _land.bind(i))
			last = maxf(last, b["land"])
	else:
		var spots := _pick_spots()
		# round the clock by where they hang, so each petal heads out on its own side
		spots.sort_custom(func(a, b): return a.rotated(TWIST).angle() < b.rotated(TWIST).angle())
		var petal0: float = (spots[0] as Vector2).rotated(TWIST).angle() if not spots.is_empty() else 0.0
		var n := spots.size()
		for i in n:
			var b := _new_missile(EMIT_AT + float(i) * 0.012 + Rng.randf_range(0.0, 0.015))
			# like a flower: every missile spreads out on its own side (evenly round the clock,
			# in the same order as where they hang), none straight up, then curls back in
			_aim(b, spots[i], _petal_angle(spots[i], i, n, petal0), _tip, BURST_HEIGHT,
					SWARM_MIN_H, SWARM_MAX_H, SWARM_SPREAD)
			_beams.append(b)
			_timeline.at(b["land"], _land.bind(i))
			last = maxf(last, b["land"])
	_timeline.lasts(last + FLAME_TIME + 0.3)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_fire_laser.call_deferred()


## A missile's timing: it leaves the knot at `delay`, floats up and lingers, then slams down.
func _new_missile(delay: float) -> Dictionary:
	var float_t := Rng.randf_range(0.4, 0.46)        # drifting up and lingering at the top
	var slam := Rng.randf_range(0.12, 0.16)          # then slamming down
	return {"delay": delay, "float": float_t, "slam": slam, "flight": float_t + slam,
			"land": delay + float_t + slam, "flick": randf() * 10.0, "aimed": false}


## Gives missile `b` its circle (local space) and its arc: thrown up out of the knot to its own
## height, then falling onto the circle (a parabola: y = tip.y + vy*u + ay*u*u), drifting out
## toward `petal` (an angle) near the top.
func _aim(b: Dictionary, spot: Vector2, petal: float, tip: Vector2, knot_height: float,
		min_h: float, max_h: float, spread: float) -> void:
	b["tip"] = tip                                    # where it leaves the knot (local space)
	b["g"] = tip + Vector2(0.0, knot_height)          # the ground right under the knot
	var drop := spot.y - tip.y                        # how far below the knot it lands
	var h := Rng.randf_range(min_h, max_h)           # how high above the knot it climbs
	var vy := -2.0 * h - 2.0 * sqrt(h * h + h * maxf(drop, 0.0))
	var ay := drop - vy
	b["spot"] = spot
	b["vy"] = vy
	b["ay"] = ay
	b["apex"] = -vy / (2.0 * ay)
	b["out"] = Vector2.from_angle(petal) * Rng.randf_range(spread * 0.87, spread * 1.13) * Vector2(1.0, 0.5)
	# the twist sweeps at most about as far as it does across the swarm's cluster, however far
	# from the knot this circle is
	var rel: Vector2 = spot - b["g"]
	b["twist"] = TWIST * clampf(27.0 / maxf(rel.length(), 1.0), 0.0, 1.0)
	# only a short way toward the circle while rising (at most FOUNTAIN_TRAVEL)
	b["rise_reach"] = clampf(FOUNTAIN_TRAVEL / maxf(rel.length(), 1.0), 0.0, 0.5)
	b["aimed"] = true


## Crimson Barrage: missile `i` leaves the knot, aimed where the caster is aiming right now.
func _launch(i: int) -> void:
	var b: Dictionary = _beams[i]
	var target := to_global(Vector2.ZERO)
	if caster != null and is_instance_valid(caster):
		var to: Vector2 = caster.aim_world - caster.global_position
		if to.length() > max_reach:
			to = to.normalized() * max_reach
		target = caster.global_position + to
	var spot := to_local(target)
	var tip := _knot()
	var rel := spot - (tip + Vector2(0.0, KNOT_ABOVE))
	# drifts out to the side it is heading (straight down / close by gets a random side)
	var petal := rel.angle() if rel.length() > 4.0 else Rng.randf() * TAU
	_aim(b, spot, petal, tip, KNOT_ABOVE, 14.0, 24.0, 0.0)
	# the barrage's missiles go straight up out of the knot, then slam over to the target
	b["out"] = Vector2.ZERO
	b["rise_reach"] = 0.0


## Where the knot is (local space): over the target for the swarm; above the caster (moving
## with them) for the barrage.
func _knot() -> Vector2:
	if stream and caster != null and is_instance_valid(caster):
		return to_local(caster.global_position) + Vector2(0.0, -KNOT_ABOVE)
	return _tip


## The red beam from the staff to the burst point (only a flash: it doesn't hurt anything).
func _fire_laser() -> void:
	var host := caster.get_parent() if caster != null and is_instance_valid(caster) else get_parent()
	var to := to_global(_knot()) - launch_from
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
			out.append((q as Vector2).rotated(turn) * spot_radius * PACK_SQUEEZE)
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


## Which way petal `i` of `n` spreads: evenly round the clock, nudged toward where its missile
## hangs so neighbours don't cross.
static func _petal_angle(spot: Vector2, i: int, n: int, start: float) -> float:
	var even := start + TAU * float(i) / float(n)
	var hang := spot.rotated(TWIST)
	if hang.length() < 1.0:
		return even
	return even + angle_difference(even, hang.angle()) * 0.5


func _physics_process(delta: float) -> void:
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


## A beam lands: everything standing in its circle takes the hit.
func _land(i: int) -> void:
	var b: Dictionary = _beams[i]
	if not b["aimed"]:
		return
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
	var tip: Vector2 = b["tip"]
	var g: Vector2 = b["g"]
	var rel := spot - g
	var apex: float = b["apex"]
	# the petal drift eases in from nothing (so every missile leaves the knot going up), peaks
	# at the top of the arc, and eases out again by the time it lands
	var bump: float
	if u < apex:
		var x := u / maxf(apex, 0.01)
		bump = x * x * (3.0 - 2.0 * x)
	else:
		var x := (u - apex) / maxf(1.0 - apex, 0.01)
		bump = 1.0 - x * x * (3.0 - 2.0 * x)
	var drift: Vector2 = (b["out"] as Vector2) * bump
	# split into where it is over the ground and how high it is, so the twist turns only the
	# ground position (round the point under the knot)
	var screen_y := tip.y + float(b["vy"]) * u + float(b["ay"]) * u * u
	var height := (g.y + rel.y * u) - screen_y   # height above the ground (the arc's own shape)
	var fall := clampf((u - apex) / maxf(1.0 - apex, 0.01), 0.0, 1.0)
	# over the ground: while rising it only edges a little way toward its circle (keeping the
	# fountain short); the slam covers the rest, swinging round counter-clockwise as it goes
	var rise_reach: float = b["rise_reach"]
	var reach: float
	if u < apex:
		reach = rise_reach * sin(0.5 * PI * u / maxf(apex, 0.01))
	else:
		reach = rise_reach + (1.0 - rise_reach) * fall
	var turn := fall * fall * (3.0 - 2.0 * fall)
	var ground := g + (rel * reach).rotated(float(b["twist"]) * (1.0 - turn)) + drift
	return Vector2(ground.x, ground.y - height)


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


## On the ground: the circles show where the beams will land and fill in as they arrive,
## then leave a fading scorch mark.
func _draw() -> void:
	for b in _beams:
		if not b["aimed"]:
			continue
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
	if stream:
		last_out = EMIT_AT + float(count) * interval - 0.2      # hovers the whole time
	if _t < last_out + 0.2:
		var k := 1.0 - clampf((_t - last_out) / 0.2, 0.0, 1.0)
		var r := (2.5 + 0.5 * sin(_t * 50.0)) * k
		var kp := _knot()
		_fx.draw_circle(kp, r + 1.0, Color(B_DARK.r, B_DARK.g, B_DARK.b, 0.6))
		_fx.draw_circle(kp, r, B_MAIN)
		_fx.draw_circle(kp, r * 0.5, B_CORE)
	for b in _beams:
		if not b["aimed"]:
			continue
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
		# the fountain part fades first; the slam part carries on the same fade from its top down
		# to the ground (the top of the slam goes with the fountain, the bottom lasts longest)
		var apex: float = b["apex"]
		var down := clampf((u - apex) / maxf(1.0 - apex, 0.01), 0.0, 1.0)
		var life := lerpf(FOUNTAIN_TRAIL_LIFE, TRAIL_LIFE, down)
		var a := (0.55 + 0.45 * float(j) / float(n)) * fade * (1.0 - pow(clampf(age / life, 0.0, 1.0), 2.0))
		# the fountain part is a pixel thinner, widening over the top of the arc
		var thick := clampf((u - apex * 0.7) / (apex * 0.6), 0.0, 1.0) * 0.5
		# feathered, darker toward the edge for contrast: dark outer fringe, deep red, bright core
		_fx.draw_line(prev, p, Color(B_EDGE.r, B_EDGE.g, B_EDGE.b, 0.4 * a), 2.0 + thick)
		_fx.draw_line(prev, p, Color(B_DARK.r, B_DARK.g, B_DARK.b, 0.7 * a), 1.0 + thick)
		_fx.draw_line(prev, p, Color(B_MAIN.r, B_MAIN.g, B_MAIN.b, a), 0.5)
		prev = p
	if head < 1.0:
		var hp := _path(b, head).snapped(Vector2(0.5, 0.5))
		_fx.draw_rect(Rect2(hp - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), B_HOT)
		_fx.draw_rect(Rect2(hp - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), B_CORE)


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
