extends Node
## Everything you SEE of a skeleton wizard: idle, walk and throw animations in 4 directions,
## hit flash, sinking down and fading on death. Reads skeleton_wizard.gd, never changes it.
## Sheet: art/skeleton_wizard.png, 80px cells, 8 columns x 9 rows.
##   row 0: idle (cols 0-3 = down, up, left, right)
##   rows 1-4: walk, 8 frames (down, up, left, right)
##   rows 5-8: throw, 7 frames (down, up, left, right)

const WALK_FPS := 9.0

var _t := 0.0
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
	var f: int = brain.face
	if brain.is_casting():
		var col := mini(int(brain.cast_t * brain.CAST_FPS), brain.CAST_FRAMES - 1)
		sprite.frame_coords = Vector2i(col, 5 + f)
	elif brain.velocity != Vector2.ZERO:
		sprite.frame_coords = Vector2i(int(_t * WALK_FPS) % 8, 1 + f)
	else:
		sprite.frame_coords = Vector2i(f, 0)


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	sprite.frame_coords = Vector2i(brain.face, 0)
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "scale", _base_scale * Vector2(1.0, 0.4), 0.18)
	_death_tween.tween_interval(0.8)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	sprite.scale = _base_scale
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
