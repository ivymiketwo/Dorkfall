extends StaticBody2D
## A dairy cow wandering in its Paddock: it stands about for a while (looking one way or
## another), then ambles to another spot on the pasture. It stops rather than walk into you.
## It's solid (you walk round it, not through it). Made by paddock.gd.
## Art: art/cow.png from tools/pack_cows.py (row 0 standing, rows 1-4 walking; columns / rows in
## the player's facing order down, up, left, right), drawn at half size like all character art.

const SHEET := preload("res://art/cow.png")
const FW := 88
const FH := 64
const FEET := 63
const WALK_FRAMES := 8
const WALK_FPS := 8.0
const SPEED := 9.0                    # world px per second: a slow amble
const PERSONAL_SPACE := 22.0          # stops when the player is this close to where it's going

var paddock: Node2D
var rng_seed := 0

var _rng := RandomNumberGenerator.new()
var _sprite: Sprite2D
var _body: CollisionShape2D
var _facing := 0                      # 0 down, 1 up, 2 left, 3 right
var _target := Vector2.ZERO
var _walking := false
var _wait := 0.0
var _anim := 0.0


func _ready() -> void:
	_rng.seed = rng_seed
	_facing = _rng.randi() % 4
	_wait = _rng.randf_range(0.5, 6.0)
	_sprite = Sprite2D.new()
	_sprite.texture = SHEET
	_sprite.hframes = WALK_FRAMES
	_sprite.vframes = 5
	_sprite.centered = false
	_sprite.offset = Vector2(-FW / 2.0, -FEET)
	_sprite.scale = Vector2(0.5, 0.5)
	add_child(_sprite)
	_body = CollisionShape2D.new()
	_body.shape = CapsuleShape2D.new()
	add_child(_body)
	_shape_for_facing()
	_show()


func _physics_process(delta: float) -> void:
	if not _walking:
		_wait -= delta
		if _wait <= 0.0:
			var t: Vector2 = paddock.random_spot(_rng)
			if position.distance_to(t) > 12.0 and paddock.clear_walk(position, t):
				_target = t
				_walking = true
				_face(t - position)
			else:
				_wait = _rng.randf_range(0.5, 2.0)
		return
	var to := _target - position
	if to.length() < 1.0:
		_stop()
		return
	var step := to.normalized() * minf(SPEED * delta, to.length())
	var next := position + step
	if _player_near(next):
		_stop()
		return
	position = next
	_face(to)
	_anim += delta


func _process(_delta: float) -> void:
	_show()


func _stop() -> void:
	_walking = false
	_anim = 0.0
	_wait = _rng.randf_range(2.0, 8.0)
	if _rng.randf() < 0.4:
		_facing = _rng.randi() % 4          # turns to look somewhere else
		_shape_for_facing()


func _face(v: Vector2) -> void:
	var f := (3 if v.x > 0 else 2) if absf(v.x) > absf(v.y) else (0 if v.y > 0 else 1)
	if f != _facing:
		_facing = f
		_shape_for_facing()


## A long body when seen from the side, a short one from the front or back.
func _shape_for_facing() -> void:
	var cs := _body
	if cs == null:
		return
	var cap := cs.shape as CapsuleShape2D
	cap.radius = 4.0
	cap.height = 26.0 if _facing >= 2 else 12.0
	cs.rotation = PI * 0.5 if _facing >= 2 else 0.0
	cs.position = Vector2(0, -3)


func _player_near(p: Vector2) -> bool:
	var pl := Players.local(get_tree())
	return pl != null and (pl.global_position - (paddock as Node2D).to_global(p)).length() < PERSONAL_SPACE


func _show() -> void:
	if _walking:
		_sprite.frame = (1 + _facing) * WALK_FRAMES + int(_anim * WALK_FPS) % WALK_FRAMES
	else:
		_sprite.frame = _facing
	queue_redraw()


func _draw() -> void:
	# a soft shadow under the cow (drawn before its picture)
	var side := _facing >= 2
	var rx := 15.0 if side else 8.0
	var ry := 3.2
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry - 1.0))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.22))
