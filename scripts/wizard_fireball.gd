class_name WizardFireball
extends Node2D
## The skeleton wizard's fireball. A red circle appears on the ground where the target was
## standing; partway through the wizard's throw a fireball leaves his hand and flies to the
## circle's centre, landing exactly when the warning runs out. Everyone inside the circle then
## takes the hit. Place this node at the circle's centre; set `launch_from` (a global position)
## and `launch_at` (seconds after the circle appears) before adding it to the scene.
##
## Rules (when it lands, who it hits) run on the game tick through AttackTimeline/AttackRules;
## everything else here is only drawing.

@export var damage := 80.0
@export var radius := 18.0
## Seconds from the circle appearing to the fireball landing.
@export var warn_time := 1.4
var launch_from := Vector2.ZERO
var launch_at := 0.4

const FIREBALL_TEX := preload("res://art/fireball_8dir.png")
const CAST_SOUND := preload("res://audio/fireball_cast.wav")
const HIT_SOUND := preload("res://audio/fireball_hit.wav")
const RING := Color(1.0, 0.3, 0.15)
const FILL := Color(0.95, 0.2, 0.08)
const BURST_TIME := 0.3

var _t := 0.0
var _landed := false
var _timeline: AttackTimeline
var _ball: Sprite2D
var _start := Vector2.ZERO           # launch point in local space
var _fx: Node2D                      # burst, drawn above characters
var _trail: Array = []
var _trail_timer := 0.0


func _ready() -> void:
	_start = to_local(launch_from)
	_timeline = AttackTimeline.new().at(warn_time, _land).lasts(warn_time + 0.6)
	_ball = Sprite2D.new()
	_ball.texture = FIREBALL_TEX
	_ball.hframes = 8
	_ball.scale = Vector2(0.5, 0.5)
	_ball.z_index = 5
	_ball.visible = false
	var dir := (Vector2.ZERO - _start)
	_ball.frame = posmod(roundi((90.0 - rad_to_deg(dir.angle())) / 45.0), 8)   # S, SE, E, NE, N, NW, W, SW
	add_child(_ball)
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
		_sound(CAST_SOUND)
	if over:
		queue_free()


func _land() -> void:
	_landed = true
	for player in Players.all(get_tree()):
		if AttackRules.circle_hits(to_local(player.global_position), radius):
			AttackRules.deal(player, damage)
	_sound(HIT_SOUND)


func _flight() -> float:
	return clampf((_t - launch_at) / maxf(warn_time - launch_at, 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	var flying := _t >= launch_at and not _landed
	_ball.visible = flying
	if flying:
		_ball.position = _start.lerp(Vector2.ZERO, _flight())
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.05
			_trail.append({"p": _ball.position + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), "age": 0.0})
	for d in _trail:
		d["age"] += delta
	_trail = _trail.filter(func(d): return d["age"] < 0.35)
	queue_redraw()
	_fx.queue_redraw()


func _draw() -> void:
	if _landed:
		return
	# the warning circle on the ground: fills in as the fireball gets close
	var p := clampf(_t / warn_time, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 10.0)
	draw_circle(Vector2.ZERO, radius, Color(FILL.r, FILL.g, FILL.b, 0.14 + 0.1 * p))
	draw_circle(Vector2.ZERO, radius * p, Color(FILL.r, FILL.g, FILL.b, 0.22))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(RING.r, RING.g, RING.b, 0.65 + 0.3 * pulse), 1.5)


func _draw_fx() -> void:
	for d in _trail:
		var a: float = 1.0 - d["age"] / 0.35
		_fx.draw_circle(d["p"], 1.8 * a + 0.5, Color(1.0, 0.45, 0.12, 0.55 * a))
	if not _landed:
		return
	var b := _t - warn_time
	var k := clampf(b / BURST_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var a := 1.0 - clampf((b - BURST_TIME * 0.5) / 0.35, 0.0, 1.0)
	if a <= 0.0:
		return
	_fx.draw_circle(Vector2.ZERO, radius * e, Color(1.0, 0.4, 0.1, 0.5 * a * (1.0 - k * 0.5)))
	_fx.draw_circle(Vector2.ZERO, radius * e * 0.55, Color(1.0, 0.85, 0.5, 0.6 * a * (1.0 - k)))
	_fx.draw_arc(Vector2.ZERO, radius * e, 0.0, TAU, 40, Color(1.0, 0.8, 0.5, a), 2.0)


func _sound(stream: AudioStream) -> void:
	var s := AudioStreamPlayer2D.new()
	s.stream = stream
	s.volume_db = -3.1
	s.finished.connect(s.queue_free)
	get_parent().add_child(s)
	s.global_position = _ball.global_position if stream == CAST_SOUND else global_position
	s.play()


## Called if the wizard dies first: gone at once, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
