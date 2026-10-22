class_name VoidHole
extends Node2D
## The Void Staff's attack:
##   1. a thin black beam (2 px jet black with a 1 px dark blue-grey edge each side) shoots from the
##      staff's orb to where you aim (up to `max_range`),
##   2. at its end a small black orb blinks in and out of existence `blinks` times,
##   3. then a large black hole snaps into existence, perfectly still, for `hole_time` seconds:
##      purple specks fade in as they're pulled straight from its rim to one single point in its middle,
##      no spin; its edge pulses very slightly (`pulse`) and a purple ring
##      with a few swept-back spikes turns slowly round it.
##      Then it's simply gone.
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
## Seconds the small orb blinks before the hole opens, and how many times it blinks.
@export var blink_time := 0.6
@export var blinks := 3
@export var orb_radius := 2.5

@export_group("Black hole")
## Its size (world px), and how much its edge gently pulses in and out (world px; 0 = perfectly
## still) and how many pulses a second.
@export var hole_radius := 14.0
@export var pulse := 0.5
@export var pulses_per_second := 1.4
## The purple ring round its edge: how fast it turns (turns a second; + = clockwise), how many
## swept-back spikes it has, and how long they are: each one a random length between these two
## (art pixels), picked when the hole opens.
@export var ring_spin := 0.35
@export var spikes := 8
@export var spike_min_px := 2
@export var spike_max_px := 5
## Seconds it stays open.
@export var hole_time := 1.4
## It hurts everything inside it this often while open (first time just after it opens).
@export var tick_every := 0.4
## How many purple specks there are at any moment, and how big each is (art px square).
@export var specks := 22
@export var speck_px := 2
## Each speck starts on the rim after a random delay (between the two, so they don't all go at
## once), travels in to the middle in `travel_time` seconds (slow at first, speeding up), and
## stays there `rest_time` before it's gone. It's invisible on the rim and fades in as it moves:
## fully there after `fade_in` of the way (0.5 = halfway in).
@export var start_delay_min := 0.0
@export var start_delay_max := 0.6
@export var travel_time := 0.4
@export var fade_in := 0.5
@export var rest_time := 0.2

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 30.0

const BLACK := Color(0, 0, 0)
const EDGE := Color8(44, 52, 78)                  # the beam's dark blue-grey edge
const RING := Color8(124, 74, 196)                # purple ring
const RING_LIGHT := Color8(196, 170, 246)         # its bright inner line
const SPECKS := [Color8(150, 96, 224), Color8(174, 126, 240), Color8(128, 78, 202), Color8(196, 160, 250)]
const CAST_SOUND := preload("res://audio/ray_swoosh.wav")
const OPEN_SOUND := preload("res://audio/fireball_hit.wav")

var _timeline: AttackTimeline
var _from := Vector2.ZERO          # the staff's orb when cast (global)
var _at := Vector2.ZERO            # where the hole opens (global); this node sits there
var _beam: Node2D                  # the beam, drawn above everyone
var _spike_px: Array[int] = []    # each spike's length (art px)
var _specks: Array = []            # each {a: angle on the rim, end: where it lands, born, wait, col}


func _ready() -> void:
	_from = HeldWeapon.beam_origin(caster) if caster else global_position
	var aim: Vector2 = caster.aim_world - _from if caster else Vector2.RIGHT * max_range
	if aim.length() > max_range:
		aim = aim.normalized() * max_range
	_at = _from + aim
	_face(aim)
	global_position = _at              # sorted with everyone else by where the hole stands
	for i in spikes:
		_spike_px.append(randi_range(spike_min_px, maxi(spike_min_px, spike_max_px)))
	_beam = Node2D.new()
	_beam.z_index = 4
	_beam.draw.connect(_draw_beam)
	add_child(_beam)
	var open_at := blink_time
	var close_at := open_at + hole_time
	_timeline = AttackTimeline.new().lasts(close_at)
	_timeline.at(open_at, _open)
	var t := open_at + 0.05
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


## The hole's radius at time t: all or nothing (0 before it opens and once it's gone).
func _hole_radius(t: float) -> float:
	return hole_radius if t >= blink_time and t < blink_time + hole_time else 0.0


func _update_specks(t: float) -> void:
	_specks = _specks.filter(func(s): return t - s["born"] < s["wait"] + travel_time + rest_time)
	while _specks.size() < specks:
		var end := Vector2.ZERO                   # every speck ends on the very same point
		_specks.append({
			"a": randf() * TAU, "end": end, "born": t,
			"wait": randf_range(start_delay_min, start_delay_max), "col": SPECKS[randi() % SPECKS.size()],
		})


func _draw() -> void:
	var t := _timeline.t
	if t < blink_time:
		# the little orb blinks in and out of existence (there for most of each beat, then gone)
		var beat := blink_time / maxf(blinks, 1)
		if t > beam_time * 0.3 and fmod(t, beat) < beat * 0.6:
			_disc(Vector2.ZERO, orb_radius + 0.5, EDGE)
			_disc(Vector2.ZERO, orb_radius, BLACK)
		return
	var r := _hole_radius(t)
	if r <= 0.0:
		return
	_blob(r, t)
	# specks: leave the rim unseen, fade in as they're pulled straight in, then rest in the middle
	for s: Dictionary in _specks:
		var age: float = t - s["born"] - s["wait"]
		if age < 0.0:
			continue
		var rim := Vector2.from_angle(s["a"]) * (r - speck_px * 0.5 - pulse)
		var k := clampf(age / maxf(travel_time, 0.001), 0.0, 1.0)
		var p := rim.lerp(s["end"], k * k)              # slow at first, faster as it falls in
		var col: Color = s["col"]
		col.a = clampf(k / maxf(fade_in, 0.001), 0.0, 1.0)
		_px(p - Vector2.ONE * speck_px * 0.25, col, speck_px * 0.5)


func _draw_beam() -> void:
	var t := _timeline.t
	if t >= beam_time:
		return
	var a := 1.0 if t < beam_time * 0.6 else 1.0 - (t - beam_time * 0.6) / (beam_time * 0.4)
	var from := _from - _at
	# a 2 px jet black line with a 1 px dark blue-grey edge on each side (art px: half a world px)
	_beam.draw_line(from, Vector2.ZERO, Color(EDGE, a), 2.0)
	_beam.draw_line(from, Vector2.ZERO, Color(BLACK, a), 1.0)


## The hole: a black disc whose edge gently pulses in and out.
func _blob(r: float, t: float) -> void:
	var open_for := t - blink_time
	var edge := r + pulse * sin(open_for * TAU * pulses_per_second)
	_disc(Vector2.ZERO, edge + 1.0, RING)          # 2 art px of purple round the black
	_disc(Vector2.ZERO, edge + 0.5, RING_LIGHT)    # with a 1 art px bright line inside it
	_disc(Vector2.ZERO, edge, BLACK)
	# spikes combed back against the spin: each leaves the ring and curls away behind it
	var turn := open_for * TAU * ring_spin
	var dir := signf(ring_spin) if ring_spin != 0.0 else 1.0
	for i in _spike_px.size():
		var n: int = _spike_px[i]                      # pixels long
		var length := n * 0.5                          # world px
		var sweep := length * 0.8 / maxf(edge, 1.0)    # how far round the ring it reaches
		var a := turn + TAU * i / maxf(_spike_px.size(), 1)
		for k in n:
			var f := float(k) / maxf(n - 1, 1)
			var ang := a - dir * sweep * f
			var rad := edge + 1.0 + f * length * 0.6        # peels away from the ring
			var p := Vector2.from_angle(ang) * rad
			if k == 0 and n >= 4:                      # a thicker root on the longer ones
				_px(p - Vector2.from_angle(ang) * 0.5, RING)
			_px(p, RING_LIGHT if f < 0.5 else RING)


## A solid disc on whole art pixels (no smoothing).
func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col)


## One art pixel (half a world px; `size` 1.0 = 2x2 art px), snapped to the art pixel grid.
func _px(p: Vector2, col: Color, size := 0.5) -> void:
	var q := (p * 2.0).floor() / 2.0
	draw_rect(Rect2(q, Vector2(size, size)), col)
