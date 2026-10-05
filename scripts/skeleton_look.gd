extends Node
## Everything you SEE of a skeleton (and Lord Kilset): walk wobble, sword poses, hit flash,
## collapsing into bones, fading out and back in. The brain (skeleton.gd) never touches this;
## this only reads its state and listens to it. A server simply has no Look.

var _t := 0.0
var _base_scale := Vector2.ONE
var _death_tween: Tween

@onready var brain: CharacterBody2D = get_parent()
@onready var sprite: Sprite2D = brain.get_node("Sprite2D")


func _ready() -> void:
	_t = randf() * 10.0
	var boss: float = brain.boss_scale
	if boss != 1.0:
		sprite.scale *= boss
		var plate := brain.get_node_or_null("Nameplate") as Node2D
		if plate:
			plate.position.y *= boss
	_base_scale = sprite.scale
	brain.respawned.connect(_on_respawn)
	var st := brain.get_node("Stats") as Stats
	st.damaged.connect(_on_hit)
	st.died.connect(_on_died)


func _process(delta: float) -> void:
	if brain.state == brain.State.DEAD:
		return
	_t += delta
	_animate(brain.velocity if not brain.is_lunging() else Vector2.ZERO)


## Picks the frame. Pirates override this (pirate_look.gd).
func _animate(move: Vector2) -> void:
	sprite.rotation = 0.0
	if brain.facing.x != 0.0:
		sprite.flip_h = brain.facing.x > 0.0   # art faces left
	if brain.is_lunging() or brain.is_recovering():
		sprite.frame = 3                 # sword thrust
	elif brain.is_winding():
		sprite.frame = 2                 # sword cocked back
	elif move != Vector2.ZERO:
		sprite.frame = int(_t * 6.0) % 2
		sprite.rotation = sin(_t * 12.0) * 0.06
	else:
		sprite.frame = 0


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	# collapses into a heap of bones, then fades (the brain waits DEATH_ANIM before counting down)
	sprite.rotation = 0.0
	sprite.frame = 0
	_death_tween = create_tween()
	_death_tween.tween_property(sprite, "scale", _base_scale * Vector2(1.0, 0.4), 0.18)
	_death_tween.tween_interval(0.8)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	if _death_tween:
		_death_tween.kill()
	sprite.rotation = 0.0
	sprite.scale = _base_scale
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.6)
