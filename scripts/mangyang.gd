extends CharacterBody2D
## Mangyang: a low-level straw scarecrow with a butcher's cleaver. Wanders near
## its spot, chases when you get close, then telegraphs a long rectangle in
## front of it and throws the cleaver down it.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Mangyang"
@export var level := 1
## XP for killing it at equal level (30 kills = level 2).
@export var xp_reward := 10

@export_group("Movement")
@export var wander_speed := 14.0
@export var chase_speed := 30.0
@export var wander_radius := 30.0
@export var aggro_range := 90.0
@export var leash_range := 208.0

@export_group("Knife throw")
@export var throw_range := 85.0
@export var throw_cooldown := 3.5
@export var throw_damage := 50.0
@export var throw_length := 110.0
@export var throw_width := 14.0
@export var throw_warn := 0.9

@export_group("Death")
@export var respawn_time := 5.0
@export var drop_item: Item
## Chase drop (a pet, say): rolled once per kill; each account can only ever get it once.
@export var unique_drop: Item
@export_range(0.0, 1.0) var unique_drop_chance := 0.0
@export var drop_min := 1
@export var drop_max := 7

const KNIFE := preload("res://scripts/knife_throw.gd")
const PICKUP := preload("res://scenes/pickup.tscn")
const BASE_SCALE := Vector2(0.5, 0.5)

var state := State.WANDER
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _throw_timer := 0.0
var _throwing := 0.0     # seconds left in the wind-up (0 = not throwing)
var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	_home = position
	_wander_target = position
	_t = randf() * 10.0
	_throw_timer = randf_range(1.0, 3.0)
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_t += delta
	_throw_timer -= delta
	if _throwing > 0.0:
		_throwing -= delta

	var player := Players.nearest(get_tree(), global_position)
	var to_player := player.global_position - global_position if player else Vector2.INF
	var dist := to_player.length()
	var from_home := position.distance_to(_home)

	match state:
		State.WANDER:
			if dist < aggro_range:
				state = State.CHASE
		State.CHASE:
			if player == null or from_home > leash_range:
				state = State.RETURN
		State.RETURN:
			if from_home < 6.0:
				state = State.WANDER

	var move := Vector2.ZERO
	var speed := wander_speed
	match state:
		State.WANDER:
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_wander_target = position if randf() < 0.5 else \
						_home + Vector2.from_angle(randf() * TAU) * randf_range(6.0, wander_radius)
				_wander_timer = randf_range(1.5, 4.0)
			if position.distance_to(_wander_target) > 3.0:
				move = position.direction_to(_wander_target)
		State.CHASE:
			speed = chase_speed
			if _throwing <= 0.0:
				if dist <= throw_range and _throw_timer <= 0.0:
					_start_throw(to_player / dist)
				elif dist > throw_range * 0.7:
					move = to_player / dist
		State.RETURN:
			speed = chase_speed
			move = position.direction_to(_home)
			stats.heal(stats.max_health * 0.3 * delta)

	if _throwing > 0.0:
		move = Vector2.ZERO
	velocity = move * speed
	move_and_slide()
	_animate(move, to_player)


func _start_throw(dir: Vector2) -> void:
	_throw_timer = throw_cooldown
	_throwing = throw_warn
	var k: KnifeThrow = KNIFE.new()
	k.direction = dir
	k.damage = throw_damage
	k.length = throw_length
	k.width = throw_width
	k.warn_time = throw_warn
	k.caster = self
	k.global_position = global_position + Vector2(0, -8)
	AttackGuard.bind(k, self)
	var root := get_parent().get_parent()
	root.add_child(k)
	var ground := root.get_node_or_null("GroundArt")
	if ground == null:
		ground = root.get_node_or_null("Ground")
	if ground:
		root.move_child(k, ground.get_index() + 1)   # painted on the ground, under everyone
	sprite.flip_h = dir.x > 0.0   # art faces left


func _animate(move: Vector2, to_player: Vector2) -> void:
	if _throwing > 0.0:
		sprite.frame = 2
		sprite.rotation = 0.0
		return
	if move.x != 0.0:
		sprite.flip_h = move.x > 0.0
	if move != Vector2.ZERO:
		sprite.frame = int(_t * 6.0) % 2
		sprite.rotation = sin(_t * 12.0) * 0.08
	else:
		sprite.frame = 0
		sprite.rotation = 0.0


func _on_damaged(_amount: float) -> void:
	if state == State.WANDER:
		state = State.CHASE
	sprite.modulate = Color(1.0, 0.45, 0.45)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _on_died() -> void:
	state = State.DEAD
	KillCredit.award(stats, level, xp_reward, self, unique_drop, unique_drop_chance)
	_throwing = 0.0
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	Loot.spawn(get_parent(), position, Loot.roll([Loot.entry(drop_item, drop_min, drop_max)]))
	sprite.rotation = 0.0
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", PI * 0.5 * (1.0 if sprite.flip_h else -1.0), 0.25)
	tw.tween_interval(0.8)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_interval(respawn_time)
	tw.tween_callback(_respawn)


func _respawn() -> void:
	position = _home
	sprite.rotation = 0.0
	stats.refill()
	shape.disabled = false
	state = State.WANDER
	_throw_timer = randf_range(1.0, 3.0)
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
