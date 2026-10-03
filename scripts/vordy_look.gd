extends Node
## Everything you SEE of Vorly: 4-way idle/walk art, the sitting "big attack" animation while
## casting, the red hit flash, the belly-up death flop, fading out and back in.
## The brain (vordy.gd) never touches this; this only listens to it. A server simply has no Look.

const BASE_SCALE := Vector2(1.5, 1.5)
## Sheet art/vorly_dragon.png: 80px cells, 8 columns x 6 rows.
## Row 0: idle, one frame per direction (cols 0-3 = down, right, up, left).
## Rows 1-4: walk (8 frames) down, up, left, right.  Rows 5 + 10-12: sit-down "big attack" (8 frames) down, up, left, right.
## Rows 6-9: melee bite (7 frames, the swipe lands on frame 4) down, up, left, right.
const WALK_ROW := {"down": 1, "up": 2, "left": 3, "right": 4}
const MELEE_ROW := {"down": 6, "up": 7, "left": 8, "right": 9}
const SIT_ROW := {"down": 5, "up": 10, "left": 11, "right": 12}
const IDLE_COL := {"down": 0, "right": 1, "up": 2, "left": 3}

var _t := 0.0
var _dead := false
var _cast_t := 0.0
var _cast_len := 0.0
var _cast_kind := ""
var _cast_dir := "down"

@onready var brain: Vordy = get_parent()
@onready var sprite: Sprite2D = brain.get_node("Sprite2D")


func _ready() -> void:
	brain.cast_started.connect(_on_cast)
	brain.bitten.connect(_on_bite)
	brain.respawned.connect(_on_respawn)
	var st := brain.get_node("Stats") as Stats
	st.damaged.connect(_on_hit)
	st.died.connect(_on_died)


func _process(delta: float) -> void:
	_t += delta
	if _dead:
		return
	sprite.flip_h = false
	sprite.rotation = 0.0
	var dir := _dir_name()
	if _cast_len > 0.0:
		_cast_t += delta
		if _cast_kind == "bite":
			# swipe lands exactly when the red wedge is full
			var pre := brain.ANIM_LEAD + brain.bite_warn
			var mf := clampi(int(_cast_t / pre * 4.0), 0, 3) if _cast_t < pre else clampi(4 + int((_cast_t - pre) / brain.BITE_RECOVER * 3.0), 4, 6)
			sprite.frame_coords = Vector2i(mf, MELEE_ROW[_cast_dir])
		elif _cast_kind == "barrage":
			# sits down, then stays sat for the whole barrage
			sprite.frame_coords = Vector2i(clampi(int(_cast_t / brain.BARRAGE_SIT * 8.0), 0, 7), SIT_ROW[dir])   # turns to face whoever he is shooting
		else:
			var f := clampi(int(_cast_t / _cast_len * 8.0), 0, 7)
			sprite.frame_coords = Vector2i(f, SIT_ROW[_cast_dir])
		if _cast_t >= _cast_len:
			_cast_len = 0.0
		return
	if brain.velocity != Vector2.ZERO:
		sprite.frame_coords = Vector2i(int(_t * 10.0) % 8, WALK_ROW[dir])
	else:
		sprite.frame_coords = Vector2i(IDLE_COL[dir], 0)
		if not brain.is_casting():
			sprite.scale.y = BASE_SCALE.y * (1.0 + sin(_t * 2.5) * 0.03)   # belly breathing


func _dir_name() -> String:
	var f := brain.facing
	if absf(f.x) > absf(f.y):
		return "right" if f.x > 0.0 else "left"
	return "down" if f.y >= 0.0 else "up"


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_bite() -> void:
	pass   # the bite is a "bite" cast now (big-attack animation), nothing extra to do


func _on_cast(kind: String, duration: float) -> void:
	# the bite has its own swipe; the red orb uses the sit-up "big attack" row; nothing else has art yet
	if kind != "bite" and kind != "blob" and kind != "barrage":
		return
	# big attacks use the sitting "big attack" animation stretched over the cast; the bite has its own
	_cast_kind = kind
	_cast_dir = _dir_name()
	_cast_t = 0.0
	_cast_len = maxf(duration, 0.1)
	sprite.scale = BASE_SCALE


func _on_died() -> void:
	_dead = true
	_cast_len = 0.0
	# flops over belly-up with his feet in the air, then fades out
	sprite.rotation = 0.0
	var tw := create_tween()
	tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(1.25, 0.5), 0.15)
	tw.tween_callback(func(): sprite.flip_v = true)
	tw.tween_property(sprite, "scale", BASE_SCALE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(brain, "modulate:a", 0.0, 1.0)


func _on_respawn() -> void:
	_dead = false
	_cast_len = 0.0
	sprite.flip_v = false
	sprite.scale = BASE_SCALE
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.8)
