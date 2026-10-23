class_name LineYank
extends Node2D
## The Yank Line (a staff's Q / E / R spell, see Item.spells): like a grappling hook, minus the hook.
##   1. a purple line is flung from the staff's orb in a high arc to where you aimed (up to
##      `max_range`, or short of a wall in the way), trailing behind its weighted tip,
##   2. it drops onto the ground loose and wiggly (still tied to the staff),
##   3. snaps tight,
##   4. and yanks you along it at `yank_speed` to where the tip landed. You keep `keep` of that speed
##      when you get there and slide to a stop, unless you hop (Space hops straight out of the
##      pull at full speed, and a hop the moment you land keeps it all, see player.gd).
##
## The pull itself is player rules (Player.yank_to on the game tick); this node only draws the
## line and times the steps. Timings and sizes are in scenes/spells/line_yank.tscn's Inspector;
## mana and cooldown in the ability (abilities/yank_line.tres).

@export_group("Throw")
## How far the line reaches at most (world px).
@export var max_range := 170.0
## Seconds the tip takes to fly out, and how high its arc goes (world px).
@export var fly_time := 0.2
@export var arc_height := 30.0

@export_group("On the ground")
## Seconds it lies loose and wiggly, then seconds to pull tight.
@export var lie_time := 0.08
@export var tighten_time := 0.06
## How far the loose line snakes to each side (world px), and roughly how long one bend is.
@export var wiggle := 2.5
@export var bend_length := 18.0

@export_group("Yank")
## How fast it pulls you (world px a second; walking is 70).
@export var yank_speed := 600.0
## How much of that speed you keep when you arrive (1 = all of it).
@export var keep := 0.8
## It gives up after this long (seconds), e.g. if something stops you.
@export var give_up_time := 0.7

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 0.0

const ROPE_DARK := Color8(58, 24, 96)
const ROPE := Color8(150, 82, 224)
const ROPE_LIGHT := Color8(214, 176, 255)
const THROW_SOUND := preload("res://audio/ray_swoosh.wav")
const SNAP_SOUND := preload("res://audio/jump.wav")

var _timeline: AttackTimeline
var _from := Vector2.ZERO          # the orb when cast (global)
var _at := Vector2.ZERO            # where the tip lands (global)
var _pulled := false
var _fade := -1.0                  # seconds into fading out (-1 = not yet)
var _phase := randf() * TAU
var _line: Node2D


func _ready() -> void:
	_from = HeldWeapon.beam_origin(caster) if caster else global_position
	var feet := caster.global_position if caster else global_position
	var aim: Vector2 = (caster.aim_world if caster else feet + Vector2.RIGHT * max_range) - feet
	if aim.length() > max_range:
		aim = aim.normalized() * max_range
	_at = feet + aim
	_at = _stop_at_walls(feet, _at)
	if caster != null and "facing" in caster and aim.length() > 1.0:
		caster.facing = (3 if aim.x > 0 else 2) if absf(aim.x) > absf(aim.y) else (0 if aim.y > 0 else 1)
	global_position = _at
	_line = Node2D.new()
	_line.z_index = 4
	_line.draw.connect(_draw_line)
	add_child(_line)
	var pull_at := fly_time + lie_time + tighten_time
	_timeline = AttackTimeline.new().lasts(1.0e9)          # ends when the pull is over
	_timeline.at(fly_time, _landed)
	_timeline.at(pull_at, _pull)
	_sound(THROW_SOUND, _from, 1.5, -4.0)


## The tip can't fly through walls: it lands just short of the first one on the way.
func _stop_at_walls(a: Vector2, b: Vector2) -> Vector2:
	var q := PhysicsRayQueryParameters2D.create(a, b, caster.collision_mask if caster is CollisionObject2D else 1)
	var skip: Array[RID] = []
	if caster is CollisionObject2D:
		skip.append(caster.get_rid())
	for i in 8:
		q.exclude = skip
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return b
		if hit["collider"] is CharacterBody2D or hit["collider"] is Area2D:
			skip.append(hit["rid"])                  # monsters and the like don't stop it
			continue
		var p: Vector2 = hit["position"]
		return p - (b - a).normalized() * 5.0
	return b


# --- rules (game tick) ---

func _physics_process(delta: float) -> void:
	_timeline.tick(delta)
	if caster == null or not is_instance_valid(caster):
		queue_free()
		return
	if _pulled and _fade < 0.0 and not caster.get("yanking"):
		_fade = 0.0
	if _fade >= 0.0:
		_fade += delta
		if _fade > 0.15:
			queue_free()


func _landed() -> void:
	_sound(SNAP_SOUND, _at, 0.6, -10.0)


func _pull() -> void:
	if caster == null or not is_instance_valid(caster) or not caster.has_method("yank_to"):
		_fade = 0.0
		return
	_pulled = true
	caster.yank_to(_at, yank_speed, give_up_time, keep)
	_sound(SNAP_SOUND, _from, 1.4, -6.0)


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
	_line.queue_redraw()


## The line from the staff's orb (where it is now) to the tip, as points (global).
func _points() -> PackedVector2Array:
	var t := _timeline.t
	var s := _from
	if caster and is_instance_valid(caster):
		s = HeldWeapon.beam_origin(caster)
		if caster.has_method("drawn_offset"):
			s += caster.drawn_offset()                  # the orb where it's drawn this frame
	var pts := PackedVector2Array()
	var length := s.distance_to(_at)
	var n := maxi(int(length / 1.5), 4)
	var side := (_at - s).orthogonal().normalized() if length > 0.5 else Vector2.RIGHT
	if t < fly_time:
		# in flight: the line follows the path the tip took, sagging down behind it
		var k := t / fly_time
		var reach := 1.0 - pow(1.0 - k, 2.0)              # fast out, slowing as it comes down
		for i in n + 1:
			var u := float(i) / n
			var f := u * reach                          # how far along the flight this bit is
			var p := s.lerp(_at, f)
			var h := arc_height * 4.0 * f * (1.0 - f)
			h *= 1.0 - 0.6 * (reach - f)                 # older line has dropped further
			p.y -= h
			p += side * sin(u * 9.0 + t * 30.0 + _phase) * 1.2 * u * (1.0 - u)
			pts.append(p)
		return pts
	# on the ground: snaking loosely until it's pulled tight, then dead straight
	var amp := wiggle
	var tight_from := fly_time + lie_time
	if t >= tight_from:
		amp *= clampf(1.0 - (t - tight_from) / maxf(tighten_time, 0.001), 0.0, 1.0)
	elif t < fly_time + 0.05:
		amp *= (t - fly_time) / 0.05 * 0.6 + 0.4            # settles into its bends as it lands
	var bends := maxf(length / maxf(bend_length, 1.0), 1.0)
	var drift := (t - fly_time) * 5.0
	for i in n + 1:
		var u := float(i) / n
		var env := sin(PI * u)                           # tied at both ends
		var w := sin(u * bends * TAU + _phase + drift) + 0.4 * sin(u * bends * 2.3 * TAU + _phase * 1.7)
		pts.append(s.lerp(_at, u) + side * w * amp * env)
	return pts


func _draw_line() -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var a := 1.0 if _fade < 0.0 else clampf(1.0 - _fade / 0.15, 0.0, 1.0)
	var pts := _points()
	for i in pts.size():
		pts[i] -= global_position
	var taut := _timeline.t >= fly_time + lie_time + tighten_time
	_line.draw_polyline(pts, Color(ROPE_DARK, a), 1.0)
	_line.draw_polyline(pts, Color(ROPE_LIGHT if taut else ROPE, a), 0.5)
	# the weighted tip
	var tip := pts[pts.size() - 1]
	_line.draw_circle(tip, 1.5, Color(ROPE_DARK, a))
	_line.draw_circle(tip, 0.9, Color(ROPE_LIGHT, a))
	# a little purple puff where it lands
	var since := _timeline.t - fly_time
	if since >= 0.0 and since < 0.25:
		var k := since / 0.25
		_line.draw_set_transform(tip, 0.0, Vector2(1.0, 0.5))
		_line.draw_arc(Vector2.ZERO, 2.0 + 7.0 * k, 0.0, TAU, 20, Color(ROPE_LIGHT, 0.6 * (1.0 - k) * a), 1.0)
		_line.draw_set_transform(Vector2.ZERO)
