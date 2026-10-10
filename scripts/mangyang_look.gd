extends Node
## Everything you SEE of a Mangyang (the hopping scarecrow): idle and hop animations in 4
## directions, hit flash, toppling over, fading out and back in. The brain (mangyang.gd) never
## touches this. A server has no Look.
## Sheet: art/mangyang.png, 80px cells, 7 columns x 5 rows.
##   row 0: idle (cols 0-3 = down, up, left, right)
##   rows 1-4: hop, 7 frames (down, up, left, right); the brain's `hop` (0..1) picks the frame

var _death_tween: Tween

@onready var brain: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = brain.get_node("Sprite2D")


func _ready() -> void:
	brain.respawned.connect(_on_respawn)
	var st := brain.get_node("Stats") as Stats
	st.damaged.connect(_on_hit)
	st.died.connect(_on_died)


func _process(_delta: float) -> void:
	if brain.state == brain.State.DEAD:
		return
	var f: int = brain.face
	if brain.hop > 0.0 and not brain.is_throwing():
		sprite.frame_coords = Vector2i(mini(int(brain.hop * 7.0), 6), 1 + f)
	else:
		sprite.frame_coords = Vector2i(f, 0)


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	sprite.frame_coords = Vector2i(brain.face, 0)
	sprite.rotation = 0.0
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "rotation", PI * 0.5 * (-1.0 if brain.face == 2 else 1.0), 0.25)
	_death_tween.tween_interval(0.8)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	sprite.rotation = 0.0
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
