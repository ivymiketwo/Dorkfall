class_name CrowSwarm
extends Node2D
## The scarecrow's attack: a circle darkens on the ground under its target, a swarm of crows
## bursts out of the scarecrow and swoops down onto the circle, hitting everyone inside the
## moment they arrive, then scatters and flies off. Place this node at the circle's centre and
## set `launch_from` (the scarecrow, global) before adding it.
##
## The rules (when it hits, who) run on the game tick through AttackTimeline/AttackRules;
## the crows are only drawing.

@export var damage := 50.0
@export var radius := 20.0
## Seconds from the circle appearing to the crows hitting.
@export var warn_time := 1.0
@export var crow_count := 12
var launch_from := Vector2.ZERO

## When the crows leave the scarecrow (they fly the rest of the warning).
const LAUNCH_AT := 0.25
const LEAVE_TIME := 0.9
const RING := Color(0.55, 0.12, 0.12)
const FILL := Color(0.25, 0.05, 0.08)
const DARK := Color(0.08, 0.07, 0.1)

var _t := 0.0
var _struck := false
var _timeline: AttackTimeline
var _crows: Array = []       # each: {from, ctrl, to, away, ph, delay}
var _fx: Node2D


func _ready() -> void:
	_timeline = AttackTimeline.new().at(warn_time, _strike).lasts(warn_time + LEAVE_TIME)
	var start := to_local(launch_from) + Vector2(0, -14)
	for i in crow_count:
		# each crow aims at its own spot inside the circle and curves in from the side
		var spot := Vector2.from_angle(randf() * TAU) * radius * sqrt(randf()) * 0.85
		var side := Vector2.from_angle(randf() * TAU) * randf_range(25.0, 45.0)
		var mid := start.lerp(spot, 0.5) + side + Vector2(0, -randf_range(18.0, 34.0))
		_crows.append({"from": start + Vector2(randf_range(-6, 6), randf_range(-4, 4)), "ctrl": mid, "to": spot,
				"away": Vector2.from_angle(randf() * TAU) * randf_range(110.0, 170.0) + Vector2(0, -60.0),
				"ph": randf() * TAU, "delay": randf_range(0.0, 0.12)})
	_fx = Node2D.new()
	_fx.z_index = 5             # crows fly above characters
	_fx.draw.connect(_draw_crows)
	add_child(_fx)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


func _strike() -> void:
	_struck = true
	for player in Players.all(get_tree()):
		if AttackRules.circle_hits(to_local(player.global_position), radius):
			AttackRules.deal(player, damage)


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


func _draw() -> void:
	if _struck:
		return
	var p := clampf(_t / warn_time, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 9.0)
	draw_circle(Vector2.ZERO, radius, Color(FILL.r, FILL.g, FILL.b, 0.2 + 0.15 * p))
	draw_circle(Vector2.ZERO, radius * p, Color(FILL.r, FILL.g, FILL.b, 0.25))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(RING.r, RING.g, RING.b, 0.6 + 0.3 * pulse), 1.5)


## Where a crow is now (local space), or null before it sets off.
func _crow_pos(c: Dictionary) -> Variant:
	var t0: float = LAUNCH_AT + c["delay"]
	if _t < t0:
		return null
	if _t < warn_time:
		var k := clampf((_t - t0) / (warn_time - t0), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k) * 0.3 + k * 0.7               # slow start, swoop in
		var a: Vector2 = c["from"].lerp(c["ctrl"], k)
		var b: Vector2 = c["ctrl"].lerp(c["to"], k)
		return a.lerp(b, k)
	var f := clampf((_t - warn_time) / LEAVE_TIME, 0.0, 1.0)
	return (c["to"] as Vector2) + (c["away"] as Vector2) * (f * f)  # scatter, speeding up


func _draw_crows() -> void:
	for c in _crows:
		var pos = _crow_pos(c)
		if pos == null:
			continue
		var a := 1.0
		if _t > warn_time:
			a = 1.0 - clampf((_t - warn_time - LEAVE_TIME * 0.5) / (LEAVE_TIME * 0.5), 0.0, 1.0)
		var vel: Vector2 = (c["to"] - c["from"]) if _t < warn_time else c["away"]
		_draw_crow(pos, signf(vel.x) if vel.x != 0.0 else 1.0, c["ph"], a)


## A little black bird (same look as the ones flying over the map), a bit bigger.
func _draw_crow(p: Vector2, flip: float, ph: float, a: float) -> void:
	p = p.snapped(Vector2(0.5, 0.5))
	var col := Color(DARK.r, DARK.g, DARK.b, a)
	var up := sin(_t * 22.0 + ph) > 0.0
	_fx.draw_rect(Rect2(p + Vector2(-2.0, -0.5), Vector2(4, 2)), col)                              # body
	_fx.draw_rect(Rect2(p + Vector2(2.0 * flip - (0.5 if flip > 0 else 1.5), -1.0), Vector2(1.5, 1.5)), col)  # head
	_fx.draw_rect(Rect2(p + Vector2(2.5 * flip + (1.0 if flip > 0 else -2.0), -0.5), Vector2(1, 0.5)),
			Color(0.75, 0.6, 0.2, a))                                                               # beak
	if up:
		_fx.draw_rect(Rect2(p + Vector2(-4.5, -2.5), Vector2(2.5, 1)), col)
		_fx.draw_rect(Rect2(p + Vector2(2.0, -2.5), Vector2(2.5, 1)), col)
		_fx.draw_rect(Rect2(p + Vector2(-2.5, -1.5), Vector2(1, 1)), col)
		_fx.draw_rect(Rect2(p + Vector2(1.5, -1.5), Vector2(1, 1)), col)
	else:
		_fx.draw_rect(Rect2(p + Vector2(-4.5, 1.0), Vector2(2.5, 1)), col)
		_fx.draw_rect(Rect2(p + Vector2(2.0, 1.0), Vector2(2.5, 1)), col)
	if not _struck:
		_fx.draw_rect(Rect2(p + Vector2(-2, 9), Vector2(4, 1)), Color(0, 0, 0, 0.12 * a))           # shadow


## Called if the scarecrow dies first: gone at once, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
