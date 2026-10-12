extends Node
## Everything you SEE of a troll: idle, walk, throw and death in 4 directions, hit flash and
## fading out after death. Reads troll.gd, never changes it.
## Sheet: art/troll.png, 80px cells, 7 columns x 16 rows; rows = anim*4 + facing
## (down, up, left, right). Anims: idle (1 frame), walk (6), throw (7), death (7).
## Originals in art/troll_src.

const WALK_FPS := 8.0
const IDLE := 0
const WALK := 4
const THROW := 8
const DEATH := 12

var _t := 0.0
var _dead_t := -1.0
var _death_tween: Tween

@onready var brain: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = brain.get_node("Sprite2D")


func _ready() -> void:
	_t = randf() * 10.0
	brain.respawned.connect(_on_respawn)
	var st := brain.get_node("Stats") as Stats
	st.damaged.connect(_on_hit)
	st.died.connect(_on_died)


func _process(delta: float) -> void:
	var f: int = brain.face
	if brain.state == brain.State.DEAD:
		if _dead_t >= 0.0:
			_dead_t += delta
			sprite.frame_coords = Vector2i(mini(int(_dead_t * brain.DEATH_FPS), 6), DEATH + f)
		return
	_t += delta
	if brain.is_casting():
		var col := mini(int(brain.cast_t * brain.CAST_FPS), brain.CAST_FRAMES - 1)
		sprite.frame_coords = Vector2i(col, THROW + f)
	elif brain.velocity != Vector2.ZERO:
		var step := int(_t * WALK_FPS) % 6
		if brain.backing:
			step = 5 - step
		sprite.frame_coords = Vector2i(step, WALK + f)
	else:
		sprite.frame_coords = Vector2i(0, IDLE + f)


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	_dead_t = 0.0
	sprite.frame_coords = Vector2i(0, DEATH + int(brain.face))
	_death_tween = create_tween()
	_death_tween.tween_interval(1.4)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	_dead_t = -1.0
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
