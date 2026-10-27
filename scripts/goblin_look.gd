extends Node
## Everything you SEE of a goblin: walking, running, punching (each punch randomly thrown with the
## left or the right hand: the mirrored rows of the sheet), hit flash, falling over and fading.
## Reads the brain (goblin.gd) and listens to it; a server simply has no Look.
##
## Sheet art/goblin.png (tools/pack_goblin.py): 64 px cells, 6 columns, rows = animation * 4 +
## facing (down, up, left, right): 0 walk (6 frames, frame 0 = standing), 4 run (4), 8 punch (6),
## 12 the same punch mirrored (6).

const COLS := 6
const ROW_WALK := 0
const ROW_RUN := 4
const ROW_PUNCH := 8
const ROW_PUNCH_MIRROR := 12
const WALK_FPS := 9.0
const RUN_FPS := 13.0

var _t := 0.0
var _face := 0
var _base_scale := Vector2.ONE
var _death_tween: Tween

@onready var brain: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = brain.get_node("Sprite2D")


func _ready() -> void:
	_t = randf() * 10.0
	_base_scale = sprite.scale
	brain.respawned.connect(_on_respawn)
	var st := brain.get_node("Stats") as Stats
	st.damaged.connect(_on_hit)
	st.died.connect(_on_died)


func _process(delta: float) -> void:
	if brain.state == brain.State.DEAD:
		return
	_t += delta
	var dir: Vector2 = brain.punch_dir if brain.is_punching() else brain.facing
	if dir != Vector2.ZERO:
		if absf(dir.x) > absf(dir.y):
			_face = 2 if dir.x < 0.0 else 3
		else:
			_face = 0 if dir.y > 0.0 else 1
	var row := ROW_WALK
	var col := 0
	if brain.is_punching():
		row = ROW_PUNCH_MIRROR if brain.punch_side == 1 else ROW_PUNCH
		col = clampi(int(brain.punch_t / brain.punch_time * float(COLS)), 0, COLS - 1)
	elif brain.velocity.length() > 1.0:
		if brain.is_running():
			row = ROW_RUN
			col = int(_t * RUN_FPS) % 4
		else:
			col = int(_t * WALK_FPS) % COLS
	sprite.frame = (row + _face) * COLS + col


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	# tips over sideways, then fades (the brain waits DEATH_ANIM before counting down)
	var side := -1.0 if _face == 2 else 1.0
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "rotation", side * PI * 0.5, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_interval(0.25)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.45)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	sprite.rotation = 0.0
	sprite.scale = _base_scale
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
