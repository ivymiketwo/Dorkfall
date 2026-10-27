class_name TwilightMissiles
extends Node2D
## The Twilight Staff's Q (hold it down): while Q is held, magic missiles keep leaving the staff's
## orb (`fire_rate` a second). Each one sets off a little to the side and curves in on the mouse
## cursor, following it as it moves; once it reaches the cursor it carries straight on the way it
## was going for `overshoot` world px, then fades. A missile hits the first monster it touches,
## while homing and on that last stretch. Costs `mana_per_second` all the time Q is held; runs out
## of mana = it stops. Missiles already flying finish their flight after you let go.
##
## Made by BasicAttack from abilities/twilight_missiles.tres (held = true; the ability holds the
## damage per missile, the start cost, mana per second and cooldown). Everything else is in this
## scene's Inspector. The rules (launching, steering, hits) run in _physics_process on the game
## tick; the rest is drawing. One node draws every missile. Sizes are world px.

@export var fire_rate := 4.0
@export var speed := 165.0
## How fast a missile can turn (radians a second) when it leaves, and how much faster it gets
## every second it flies (so it always closes in, never circles the cursor for ever).
@export var turn_start := 4.0
@export var turn_growth := 16.0
## Missiles leave up to this many degrees either side of the line to the cursor, alternating sides.
@export var launch_spread_deg := 55.0
## Counts as "reached the cursor" this close; then it flies on straight for `overshoot`.
@export var reach := 6.0
@export var overshoot := 34.0
## Gives up homing after this long and flies on straight.
@export var max_home_time := 1.6
@export var hit_radius := 5.0
@export var trail_len := 10

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 30.0
var mana_per_second := 40.0

const CORE := Color(1.0, 0.92, 1.0)
const GLOW := Color(0.78, 0.5, 1.0)
const TRAIL_HEAD := Color(0.95, 0.45, 0.85)
const TRAIL_TAIL := Color(0.3, 0.35, 0.95)

var _missiles: Array = []     # {p, dir, t, homing, left, trail: Array[Vector2], side}
var _bursts: Array = []       # {p, t}
var _stopping := false
var _fire_cd := 0.0
var _side := 1.0


func _ready() -> void:
	z_index = 5
	position = Vector2.ZERO


func is_running() -> bool:
	return not _stopping


func stop() -> void:
	_stopping = true


func _physics_process(delta: float) -> void:
	if caster == null or not is_instance_valid(caster):
		queue_free()
		return
	var stats := caster.get_node_or_null("Stats") as Stats
	if not _stopping:
		if stats == null or stats.health <= 0.0 or (caster.has_method("is_warding") and caster.is_warding()):
			stop()
		elif not stats.spend_mana(mana_per_second * delta):
			stats.warn_out_of_mana()
			stop()
		else:
			_fire_cd -= delta
			while _fire_cd <= 0.0:
				_launch()
				_fire_cd += 1.0 / fire_rate
	var target: Vector2 = caster.get("aim_world") if "aim_world" in caster else caster.global_position
	var hit_amount := damage * (stats.magic_mult() if stats else 1.0)
	var keep: Array = []
	for m in _missiles:
		m["t"] += delta
		if m["homing"]:
			var to: Vector2 = target - m["p"]
			if to.length() <= reach or m["t"] >= max_home_time:
				m["homing"] = false          # reached it: carry straight on
			else:
				var want := to.angle()
				var have: float = (m["dir"] as Vector2).angle()
				var turn: float = (turn_start + turn_growth * float(m["t"])) * delta
				var diff := angle_difference(have, want)
				m["dir"] = Vector2.from_angle(have + clampf(diff, -turn, turn))
		var step: Vector2 = m["dir"] * speed * delta
		m["p"] += step
		if not m["homing"]:
			m["left"] -= step.length()
		var trail: Array = m["trail"]
		trail.push_front(m["p"])
		if trail.size() > trail_len:
			trail.pop_back()
		var victim := _hit_at(m["p"])
		if victim:
			var st := victim.get_node("Stats") as Stats
			st.take_damage(hit_amount, caster)
			_bursts.append({"p": m["p"], "t": 0.0})
			continue
		if not m["homing"] and m["left"] <= 0.0:
			_bursts.append({"p": m["p"], "t": 0.12})   # a smaller puff where it fizzles out
			continue
		keep.append(m)
	_missiles = keep
	for b in _bursts:
		b["t"] += delta
	_bursts = _bursts.filter(func(b): return b["t"] < 0.3)
	if _stopping and _missiles.is_empty() and _bursts.is_empty():
		queue_free()
	queue_redraw()


func _launch() -> void:
	var from := HeldWeapon.beam_origin(caster)
	var target: Vector2 = caster.get("aim_world")
	var to := target - from
	var base := to.normalized() if to.length() > 1.0 else Vector2.DOWN
	if "facing" in caster:       # face the way you're casting
		caster.facing = (3 if base.x > 0 else 2) if absf(base.x) > absf(base.y) else (0 if base.y > 0 else 1)
	_side = -_side
	var a := deg_to_rad(launch_spread_deg) * randf_range(0.5, 1.0) * _side
	_missiles.append({"p": from, "dir": base.rotated(a), "t": 0.0, "homing": true, "left": overshoot,
			"trail": [from]})


## The first living monster a missile at `p` touches (its body, a little above its feet).
func _hit_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("monsters"):
		var m := n as Node2D
		if m == null or not AttackRules.can_hurt(caster, m):
			continue
		var st := m.get_node_or_null("Stats") as Stats
		if st == null or st.health <= 0.0:
			continue
		var body := m.global_position + Vector2(0, -7)
		if absf(p.x - body.x) <= hit_radius + 4.0 and absf(p.y - body.y) <= hit_radius + 8.0:
			return m
	return null


func _draw() -> void:
	var g := Vector2(0.25, 0.25)
	for m in _missiles:
		var trail: Array = m["trail"]
		for k in range(trail.size() - 1, 0, -1):
			var f := float(k) / float(maxi(trail_len - 1, 1))
			var c := TRAIL_HEAD.lerp(TRAIL_TAIL, f)
			c.a = 0.85 * (1.0 - f)
			var s := 1.75 - 1.0 * f
			draw_rect(Rect2(to_local(trail[k]).snapped(g) - Vector2(s, s) / 2.0, Vector2(s, s)), c)
		var p := to_local(m["p"]).snapped(g)
		draw_rect(Rect2(p - Vector2(2.25, 2.25), Vector2(4.5, 4.5)), Color(GLOW, 0.22))
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), Color(GLOW, 0.6))
		draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), GLOW)
		draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), CORE)
	for b in _bursts:
		var f: float = b["t"] / 0.3
		var c := GLOW.lerp(TRAIL_TAIL, f)
		c.a = 1.0 - f
		var r := 1.5 + 8.0 * f
		var p := to_local(b["p"]).snapped(g)
		for k in 6:
			var d := Vector2.from_angle(k * TAU / 6.0 + 0.4) * r
			draw_rect(Rect2((p + d).snapped(g) - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), c)
		if f < 0.4:
			draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(CORE, 1.0 - f * 2.5))
