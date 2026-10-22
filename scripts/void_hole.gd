class_name VoidHole
extends Node2D
## The Void Staff's attack:
##   1. a thin black beam (2 px jet black with a 1 px dark blue-grey edge each side) shoots from the
##      staff's orb to where you aim (up to `max_range`),
##   2. at its end a small black orb appears and blinks `blinks` times,
##   3. then it swells into a large black hole that lingers for `hole_time` seconds while specks of
##      dark blue are sucked violently in from all round it, and collapses.
## Everything inside the hole takes `damage` every `tick_every` seconds while it's open.
##
## Made by BasicAttack from the Void Staff's ability (abilities/void_hole.tres, which points at
## scenes/spells/void_hole.tscn). Timings and sizes are in that scene's Inspector; the ability
## holds the damage, mana and cooldown. The rules (where it lands, when it opens and who it hits)
## run on the game tick through AttackTimeline; the rest is only drawing. Sizes are world px
## (1 world px = 2 art px).

@export_group("Beam")
## How far the beam reaches at most (world px).
@export var max_range := 140.0
## Seconds the beam stays out.
@export var beam_time := 0.3

@export_group("Orb")
## Seconds the small orb blinks before it swells, and how many times it blinks.
@export var blink_time := 0.6
@export var blinks := 3
@export var orb_radius := 2.5

@export_group("Black hole")
## Its size once open (world px), and how long it takes to swell to it.
@export var hole_radius := 14.0
@export var grow_time := 0.15
## Seconds it stays open, and how long it takes to collapse at the end.
@export var hole_time := 1.4
@export var collapse_time := 0.15
## It hurts everything inside it this often while open (first time just after it opens).
@export var tick_every := 0.4
## How many blue specks are falling in at any moment.
@export var specks := 18

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 30.0

const BLACK := Color(0, 0, 0)
const EDGE := Color8(44, 52, 78)                  # the beam's dark blue-grey edge
const BLUES := [Color8(44, 64, 150), Color8(58, 84, 184), Color8(36, 52, 128), Color8(74, 104, 204)]
const CAST_SOUND := preload("res://audio/ray_swoosh.wav")
const OPEN_SOUND := preload("res://audio/fireball_hit.wav")

var _timeline: AttackTimeline
var _from := Vector2.ZERO          # the staff's orb when cast (global)
var _at := Vector2.ZERO            # where the hole opens (global); this node sits there
var _beam: Node2D                  # the beam, drawn above everyone
var _specks: Array = []            # each {a: start angle, r0: start radius, born: t, life: s, col}


func _ready() -> void:
	_from = HeldWeapon.beam_origin(caster) if caster else global_position
	var aim: Vector2 = caster.aim_world - _from if caster else Vector2.RIGHT * max_range
	if aim.length() > max_range:
		aim = aim.normalized() * max_range
	_at = _from + aim
	_face(aim)
	global_position = _at              # sorted with everyone else by where the hole stands
	_beam = Node2D.new()
	_beam.z_index = 4
	_beam.draw.connect(_draw_beam)
	add_child(_beam)
	var open_at := blink_time
	var close_at := open_at + grow_time + hole_time
	_timeline = AttackTimeline.new().lasts(close_at + collapse_time)
	_timeline.at(open_at, _open)
	var t := open_at + grow_time * 0.5
	while t < close_at:
		_timeline.at(t, _hurt)
		t += tick_every
	_sound(CAST_SOUND, _from, 0.55, -2.0)


func _face(v: Vector2) -> void:
	if caster != null and "facing" in caster and v.length() > 1.0:
		caster.facing = (3 if v.x > 0 else 2) if absf(v.x) > absf(v.y) else (0 if v.y > 0 else 1)


# --- rules (game tick) ---

func _physics_process(delta: float) -> void:
	if _timeline.tick(delta):
		queue_free()


func _open() -> void:
	_sound(OPEN_SOUND, _at, 0.45, 0.0)


func _hurt() -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var stats := caster.get_node_or_null("Stats") as Stats
	var amount := damage * (stats.magic_mult() if stats else 1.0)
	var shape := CircleShape2D.new()
	shape.radius = hole_radius + 2.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, _at)
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var seen := {}
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 64):
		var b := hit["collider"] as Node
		if b == null or seen.has(b):
			continue
		seen[b] = true
		var t := b.get_node_or_null("Stats") as Stats
		if t:
			t.take_damage(amount, caster)


func _sound(stream: AudioStream, at: Vector2, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = at
	p.play()


# --- drawing only ---

func _process(_delta: float) -> void:
	var t := _timeline.t
	if _hole_radius(t) > 0.0:
		_update_specks(t)
	queue_redraw()
	_beam.queue_redraw()


## The hole's radius at time t (0 before it opens and after it's gone).
func _hole_radius(t: float) -> float:
	var open_at := blink_time
	var close_at := open_at + grow_time + hole_time
	if t < open_at:
		return 0.0
	if t < open_at + grow_time:
		var x := (t - open_at) / grow_time
		return lerpf(orb_radius, hole_radius, 1.0 - pow(1.0 - x, 3.0))
	if t < close_at:
		return hole_radius + 0.5 * sin(t * 9.0)          # a slight throb
	return hole_radius * clampf(1.0 - (t - close_at) / collapse_time, 0.0, 1.0)


func _update_specks(t: float) -> void:
	var close_at := blink_time + grow_time + hole_time
	_specks = _specks.filter(func(s): return t - s["born"] < s["life"])
	while _specks.size() < specks and t < close_at:
		_specks.append({
			"a": randf() * TAU, "r0": hole_radius * randf_range(1.3, 2.2),
			"born": t - randf() * 0.3 if _specks.is_empty() else t, "life": randf_range(0.3, 0.55),
			"spin": randf_range(1.5, 3.0) * (1.0 if randf() < 0.85 else -1.0),
			"col": BLUES[randi() % BLUES.size()],
		})


func _draw() -> void:
	var t := _timeline.t
	if t < blink_time:
		# the little orb, blinking (on most of each beat, off for the rest)
		var beat := blink_time / maxf(blinks, 1)
		if t > beam_time * 0.3 and fmod(t, beat) < beat * 0.65:
			_disc(Vector2.ZERO, orb_radius + 0.5, EDGE)
			_disc(Vector2.ZERO, orb_radius, BLACK)
		return
	var r := _hole_radius(t)
	if r <= 0.0:
		return
	# specks: start outside the sphere and are flung inwards, faster and faster, spinning round
	for s: Dictionary in _specks:
		var k := clampf((t - s["born"]) / s["life"], 0.0, 1.0)
		var dist: float = s["r0"] * (1.0 - pow(k, 2.6))
		var ang: float = s["a"] + s["spin"] * pow(k, 2.0) * 2.0
		var p := Vector2(cos(ang), sin(ang)) * dist
		var col: Color = s["col"]
		if dist > r:
			_px(p, col, 1.0)                 # still outside: a 2x2 speck
		else:
			_px(p, col.lightened(0.15))      # over the black: one pixel
		# a short streak behind it once it's moving fast
		if k > 0.45:
			var back := Vector2(cos(ang - s["spin"] * 0.15), sin(ang - s["spin"] * 0.15)) * minf(dist * 1.18 + 0.5, s["r0"])
			_px(back, Color(col, 0.6))
	_disc(Vector2.ZERO, r, BLACK)
	# specks already over the sphere are drawn again on top of it
	for s: Dictionary in _specks:
		var k := clampf((t - s["born"]) / s["life"], 0.0, 1.0)
		var dist: float = s["r0"] * (1.0 - pow(k, 2.6))
		if dist <= r - 0.5:
			var ang: float = s["a"] + s["spin"] * pow(k, 2.0) * 2.0
			_px(Vector2(cos(ang), sin(ang)) * dist, s["col"])


func _draw_beam() -> void:
	var t := _timeline.t
	if t >= beam_time:
		return
	var a := 1.0 if t < beam_time * 0.6 else 1.0 - (t - beam_time * 0.6) / (beam_time * 0.4)
	var from := _from - _at
	# a 2 px jet black line with a 1 px dark blue-grey edge on each side (art px: half a world px)
	_beam.draw_line(from, Vector2.ZERO, Color(EDGE, a), 2.0)
	_beam.draw_line(from, Vector2.ZERO, Color(BLACK, a), 1.0)


## A solid disc on whole art pixels (no smoothing).
func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)


## One art pixel (half a world px; `size` 1.0 = 2x2 art px), snapped to the art pixel grid.
func _px(p: Vector2, col: Color, size := 0.5) -> void:
	var q := (p * 2.0).floor() / 2.0
	draw_rect(Rect2(q, Vector2(size, size)), col)
