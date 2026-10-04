extends Area2D
## Fireball projectile. Flies straight and explodes on impact (anything solid),
## dealing area damage to everything with a Stats child inside the blast.
## Fizzles harmlessly if it runs out of range. Flies over water.

var direction := Vector2.RIGHT
var speed := 215.0
var damage := 40.0
var caster: Node
var lifetime := 2.0
## Blast radius in pixels; damage falls off to half at the edge.
var aoe_radius := 30.0

const CAST_SOUND := preload("res://audio/fireball_cast.wav")
const FX_DB := -3.1   # 30% quieter
const HIT_SOUND := preload("res://audio/fireball_hit.wav")
## Cast sound handed over by whoever launched us (it started at the beginning of the wind-up).
var cast_player: AudioStreamPlayer2D
var _cast_player: AudioStreamPlayer2D
var _hit_player: AudioStreamPlayer2D

var _done := false
var _ring := -1.0   # blast ring animation, 0..1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_face()
	# the cast sound rides along with the fireball until it hits something
	if cast_player != null and is_instance_valid(cast_player):
		_cast_player = cast_player
	else:
		_cast_player = AudioStreamPlayer2D.new()
		_cast_player.stream = CAST_SOUND
		_cast_player.volume_db = FX_DB
		_cast_player.finished.connect(_cast_player.queue_free)
		get_parent().add_child.call_deferred(_cast_player)   # outlives us if we fizzle
		_cast_player.play.call_deferred()
		_cast_player.position = position


## Picks the sprite frame for the flight direction. Frames run S, SE, E, NE, N, NW, W, SW.
func _face() -> void:
	var deg := rad_to_deg(direction.angle())
	$Sprite2D.frame = posmod(roundi((90.0 - deg) / 45.0), 8)


func _physics_process(delta: float) -> void:
	if _done:
		return
	position += direction * speed * delta
	_face()
	if _cast_player != null and is_instance_valid(_cast_player):
		_cast_player.global_position = global_position
	lifetime -= delta
	if lifetime <= 0.0:
		_explode(false)


func _on_body_entered(body: Node2D) -> void:
	if _done or body == caster:
		return
	_explode(true)


func _blast() -> void:
	var space := get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = aoe_radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var from_player := caster != null and caster.is_in_group("player")
	var seen := {}
	for hit in space.intersect_shape(q, 32):
		var body := hit["collider"] as Node
		if body == null or seen.has(body):
			continue
		seen[body] = true
		if from_player == false and not body.is_in_group("player"):
			continue   # monsters' fireballs only hurt the player
		var target_stats := body.get_node_or_null("Stats") as Stats
		if target_stats:
			var d := global_position.distance_to((body as Node2D).global_position + Vector2(0, -8))
			var falloff := lerpf(1.0, 0.5, clampf(d / aoe_radius, 0.0, 1.0))
			target_stats.take_damage(damage * falloff, caster, false, global_position)


func _explode(with_damage: bool) -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	if with_damage:
		# impact: cut the cast sound and play the hit sound. (A fizzle lets the cast sound finish instead.)
		if _cast_player != null and is_instance_valid(_cast_player):
			_cast_player.queue_free()
		_hit_player = AudioStreamPlayer2D.new()
		_hit_player.stream = HIT_SOUND
		_hit_player.volume_db = FX_DB
		add_child(_hit_player)
		_hit_player.play()
		call_deferred("_blast")
		# blast ring
		create_tween().tween_method(_set_ring, 0.0, 1.0, 0.25)
	$Sprite2D.hide()
	$Trail.emitting = false
	$Burst.emitting = true
	await get_tree().create_timer(0.6).timeout
	while _hit_player != null and _hit_player.playing:
		await get_tree().create_timer(0.1).timeout   # stay alive until the sounds finish
	queue_free()


func _set_ring(v: float) -> void:
	_ring = v
	queue_redraw()


func _draw() -> void:
	if _ring < 0.0:
		return
	var r := aoe_radius * _ring
	var a := 1.0 - _ring
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.55, 0.1, 0.35 * a))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, a), 2.0)
