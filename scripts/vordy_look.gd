extends Node
## Everything you SEE of Vorly: walk frames, waddle, belly breathing, squash and stretch while
## casting, the red hit flash, the belly-up death flop, fading out and back in.
## The brain (vordy.gd) never touches this; this only listens to it. A server simply has no Look.

const BASE_SCALE := Vector2(0.5, 0.5)   # sprite art is 2x, drawn at half scale

var _t := 0.0
var _dead := false

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
	sprite.flip_h = brain.facing_right
	if brain.velocity != Vector2.ZERO:
		sprite.frame = int(_t * 5.0) % 2
		sprite.rotation = sin(_t * 10.0) * 0.07   # waddle
	else:
		sprite.frame = 0
		sprite.rotation = 0.0
		if not brain.is_casting():
			sprite.scale.y = BASE_SCALE.y * (1.0 + sin(_t * 2.5) * 0.03)   # belly breathing


func _on_hit(_amount: float) -> void:
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_bite() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(1.15, 0.9), 0.08)
	tw.tween_property(sprite, "scale", BASE_SCALE, 0.12)


func _on_cast(kind: String, duration: float) -> void:
	var tw := create_tween()
	match kind:
		"slam":   # rears up while charging, slams down when the smoke goes off
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(0.9, 1.12), duration - 0.23)
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(1.2, 0.85), 0.08)
			tw.tween_property(sprite, "scale", BASE_SCALE, 0.15)
		"blob":   # hocks it up: rears back, then lurches forward as it launches
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(0.92, 1.15), 0.25)
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(1.18, 0.88), 0.1)
			tw.tween_property(sprite, "scale", BASE_SCALE, 0.15)
		"gust":   # sucks in a huge breath (puffing up), then blows it all out
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(1.3, 1.22), brain.gust_warn)
			tw.tween_property(sprite, "scale", BASE_SCALE * Vector2(0.85, 0.9), 0.1)
			tw.tween_property(sprite, "scale", BASE_SCALE, maxf(duration - brain.gust_warn - 0.1, 0.05))


func _on_died() -> void:
	_dead = true
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
	sprite.flip_v = false
	sprite.scale = BASE_SCALE
	create_tween().tween_property(brain, "modulate:a", 1.0, 0.8)
