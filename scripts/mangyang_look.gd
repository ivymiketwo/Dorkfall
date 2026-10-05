extends Node
## Everything you SEE of a Mangyang: walk wobble, the throwing pose, hit flash, toppling over,
## fading out and back in. The brain (mangyang.gd) never touches this. A server has no Look.

var _t := 0.0
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
	if brain.state == brain.State.DEAD:
		return
	_t += delta
	if brain.facing.x != 0.0:
		sprite.flip_h = brain.facing.x > 0.0   # art faces left
	if brain.is_throwing():
		sprite.frame = 2
		sprite.rotation = 0.0
	elif brain.velocity != Vector2.ZERO:
		sprite.frame = int(_t * 6.0) % 2
		sprite.rotation = sin(_t * 12.0) * 0.08
	else:
		sprite.frame = 0
		sprite.rotation = 0.0


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	sprite.rotation = 0.0
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "rotation", PI * 0.5 * (1.0 if sprite.flip_h else -1.0), 0.25)
	_death_tween.tween_interval(0.8)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	sprite.rotation = 0.0
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
