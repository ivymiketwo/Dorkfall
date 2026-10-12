class_name TrollRock
extends Node2D
## A troll club attack: a red circle on the ground that hits everyone inside it when the warning
## runs out, with a puff of dust and flying chips.
##   thrown = true:  the knocked rock. The troll's club hits the ground at `launch_from` (a global
##                   position) `launch_at` seconds after the circle appears; a chunk of rock flies
##                   from there in a high tumbling arc and lands on the circle's centre.
##   thrown = false: the smash itself; the circle is where the club lands, no rock.
## Place this node at the circle's centre and set the fields before adding it to the scene.
##
## Rules (when it lands, who it hits) run on the game tick through AttackTimeline/AttackRules;
## everything else here is only drawing.

@export var damage := 100.0
@export var radius := 22.0
## Seconds from the circle appearing to the rock landing.
@export var warn_time := 1.0
@export var thrown := true
var launch_from := Vector2.ZERO
var launch_at := 0.4

const ROCK_TEX := preload("res://art/troll_rock.png")
const THROW_SOUND := preload("res://audio/ray_swoosh.wav")
const HIT_SOUND := preload("res://audio/fireball_hit.wav")
const RING := Color(0.95, 0.2, 0.15)
const FILL := Color(0.95, 0.12, 0.1)
## How high the arc goes above the straight line (world px), more for longer throws.
const ARC_MIN := 18.0
const ARC_PER_PX := 0.25
const DUST_TIME := 0.5
const PUFF_TIME := 0.35

var _t := 0.0
var _landed := false
var _timeline: AttackTimeline
var _rock: Sprite2D
var _start := Vector2.ZERO           # launch point in local space
var _arc := 0.0
var _fx: Node2D                      # rock + dust, drawn above characters


func _ready() -> void:
	if not thrown:
		launch_from = global_position
		launch_at = warn_time + 1.0          # never flies
	_start = to_local(launch_from)
	_arc = ARC_MIN + _start.length() * ARC_PER_PX
	_timeline = AttackTimeline.new().at(warn_time, _land).lasts(warn_time + DUST_TIME)
	_rock = Sprite2D.new()
	_rock.texture = ROCK_TEX
	_rock.hframes = 4
	_rock.scale = Vector2(0.5, 0.5)
	_rock.z_index = 5
	_rock.visible = false
	add_child(_rock)
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var was := _timeline.t
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if was < launch_at and _t >= launch_at:
		_sound(HIT_SOUND, -12.0, _start)     # the club hitting the ground
		_sound(THROW_SOUND, -8.0, _start)
	if over:
		queue_free()


func _land() -> void:
	_landed = true
	for player in Players.all(get_tree()):
		if AttackRules.circle_hits(to_local(player.global_position), radius):
			AttackRules.deal(player, damage)
	_sound(HIT_SOUND, -4.0)


func _flight() -> float:
	return clampf((_t - launch_at) / maxf(warn_time - launch_at, 0.01), 0.0, 1.0)


func _process(_delta: float) -> void:
	var flying := _t >= launch_at and not _landed
	_rock.visible = flying
	if flying:
		var k := _flight()
		_rock.position = _start.lerp(Vector2.ZERO, k) + Vector2(0, -4.0 * _arc * k * (1.0 - k))
		_rock.frame = int(k * 10.0) % 4          # tumbles: a quarter turn per frame
	queue_redraw()
	_fx.queue_redraw()


func _draw() -> void:
	if _landed:
		return
	# the warning circle on the ground: fills in as the rock gets close
	var p := clampf(_t / warn_time, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 10.0)
	draw_circle(Vector2.ZERO, radius, Color(FILL.r, FILL.g, FILL.b, 0.14 + 0.1 * p))
	draw_circle(Vector2.ZERO, radius * p, Color(FILL.r, FILL.g, FILL.b, 0.22))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(RING.r, RING.g, RING.b, 0.65 + 0.3 * pulse), 1.5)
	# the rock's shadow, growing as it comes down
	if thrown and _t >= launch_at:
		var k := _flight()
		var sh := _start.lerp(Vector2.ZERO, k)
		draw_set_transform(sh, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 2.0 + 2.5 * k, Color(0, 0, 0, 0.25 + 0.2 * k))
		draw_set_transform(Vector2.ZERO)


func _draw_fx() -> void:
	# where the club hit the ground and knocked the rock loose: a small puff
	var pa := _t - launch_at
	if thrown and pa >= 0.0 and pa < PUFF_TIME:
		var pk := pa / PUFF_TIME
		_fx.draw_set_transform(_start, 0.0, Vector2(1.0, 0.6))
		_fx.draw_arc(Vector2.ZERO, 4.0 + 8.0 * pk, 0.0, TAU, 24, Color(0.78, 0.76, 0.74, 0.7 * (1.0 - pk)), 1.5)
		_fx.draw_set_transform(Vector2.ZERO)
	if not _landed:
		return
	var age := _t - warn_time
	var k := clampf(age / DUST_TIME, 0.0, 1.0)
	var a := 1.0 - k
	if a <= 0.0:
		return
	var e := 1.0 - pow(1.0 - k, 3.0)
	# dust ring rolling outwards, squashed (seen from above at an angle)
	_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	_fx.draw_circle(Vector2.ZERO, radius * (0.4 + 0.8 * e), Color(0.62, 0.6, 0.6, 0.35 * a))
	_fx.draw_arc(Vector2.ZERO, radius * (0.4 + 0.8 * e), 0.0, TAU, 36, Color(0.78, 0.76, 0.74, 0.7 * a), 2.0)
	_fx.draw_set_transform(Vector2.ZERO)
	# chips of rock flying out and falling
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for i in 8:
		var ang := r.randf() * TAU
		var sp := r.randf_range(14.0, 30.0)
		var up := r.randf_range(14.0, 26.0)
		var pos := Vector2(cos(ang) * sp * k, sin(ang) * sp * k * 0.6 - up * k + 40.0 * k * k)
		var s := 1.0 if i % 3 else 1.5
		_fx.draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0.42, 0.43, 0.47, a))


func _sound(stream: AudioStream, volume: float, at := Vector2.ZERO) -> void:
	var s := AudioStreamPlayer2D.new()
	s.stream = stream
	s.volume_db = volume
	s.finished.connect(s.queue_free)
	get_parent().add_child(s)
	s.global_position = global_position + at
	s.play()


## Called if the troll dies first: gone at once, no damage (same rule as every telegraph).
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
