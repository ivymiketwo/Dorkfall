extends CharacterBody2D
## Skeleton wizard: a robed skeleton that keeps its distance and throws fireballs. Each cast
## puts a red warning circle on the ground under its target; the fireball leaves the
## wizard's hand partway through the throw and lands on the circle when the warning ends.
##
## This script is the BRAIN (state, targeting, the cast, loot, respawn). It draws nothing;
## everything you see is in skeleton_wizard_look.gd, which only reads the state below.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Skeleton Wizard"
## Which quests count this kill (see Quests.kind_of).
@export var quest_kind := "skeleton_wizard"
@export var level := 20
@export var xp_reward := 40

@export_group("Movement")
@export var wander_speed := 10.0
@export var chase_speed := 30.0
@export var wander_radius := 36.0
@export var aggro_range := 130.0
@export var leash_range := 260.0
## It stops walking closer at this distance and throws from there...
@export var cast_range := 110.0
## ...and backs off if you get this close.
@export var keep_away := 45.0

@export_group("Fireball")
@export var fireball_damage := 80.0
@export var fireball_radius := 18.0
## Seconds from the circle appearing to the fireball landing.
@export var fireball_warn := 1.4
@export var fireball_cooldown := 2.6

@export_group("Death")
@export var respawn_time := 20.0
@export var drop_item: Item
@export var drop_min := 30
@export var drop_max := 70

signal respawned

const FIREBALL := preload("res://scripts/wizard_fireball.gd")
const DEATH_ANIM := 1.6
## Throw animation: 7 frames at this speed (the look plays the same timing).
const CAST_FPS := 10.0
const CAST_FRAMES := 7
## Per facing (down, up, left, right): the last throw frame with fire in the hand, and where
## that fire is (world px from the wizard's feet). The fireball leaves from there as that
## frame ends. Measured from the red pixels in art/skeleton_wizard_src (attack frames).
const HAND := [
	{"frame": 3, "at": Vector2(-2.5, -15.75)},
	{"frame": 4, "at": Vector2(0.5, -28.1)},
	{"frame": 3, "at": Vector2(-9.2, -16.4)},
	{"frame": 3, "at": Vector2(8.7, -16.2)},
]

var state := State.WANDER
## 0 down, 1 up, 2 left, 3 right (the look picks its row from this).
var face := 0
## Seconds into the current throw (-1 = not throwing).
var cast_t := -1.0
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _cast_timer := 0.0
var _respawn_timer := 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	_home = position
	_wander_target = position
	_cast_timer = Rng.randf_range(0.8, 2.0)
	var lv := maxi(level - 3, 0)
	stats.max_health *= 1.0 + 0.25 * float(lv)
	stats.refill()
	xp_reward = int(round(float(xp_reward) * (1.0 + 0.33 * float(lv))))
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func is_casting() -> bool:
	return cast_t >= 0.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_cast_timer -= delta
	if cast_t >= 0.0:
		cast_t += delta
		if cast_t >= CAST_FRAMES / CAST_FPS:
			cast_t = -1.0

	var player := Players.nearest(get_tree(), global_position, true)
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
				_wander_target = position if Rng.chance(0.5) else \
						_home + Vector2.from_angle(Rng.randf() * TAU) * Rng.randf_range(6.0, wander_radius)
				_wander_timer = Rng.randf_range(1.5, 4.0)
			if position.distance_to(_wander_target) > 3.0:
				move = position.direction_to(_wander_target)
		State.CHASE:
			speed = chase_speed
			if not is_casting():
				if dist <= cast_range and _cast_timer <= 0.0:
					_start_cast(player)
				elif dist > cast_range * 0.85:
					move = to_player / dist
				elif dist < keep_away:
					move = -to_player / dist
					speed = chase_speed * 0.7
		State.RETURN:
			speed = chase_speed
			move = position.direction_to(_home)
			stats.heal(stats.max_health * 0.3 * delta)

	if is_casting():
		move = Vector2.ZERO
	elif move != Vector2.ZERO:
		face = _face_of(move if state != State.CHASE or dist >= keep_away else -move)
	velocity = move * speed
	move_and_slide()


static func _face_of(dir: Vector2) -> int:
	if absf(dir.x) > absf(dir.y):
		return 2 if dir.x < 0.0 else 3
	return 0 if dir.y > 0.0 else 1


func _start_cast(target: Node2D) -> void:
	face = _face_of(target.global_position - global_position)
	cast_t = 0.0
	_cast_timer = fireball_cooldown
	var hand: Dictionary = HAND[face]
	var f: WizardFireball = FIREBALL.new()
	f.damage = fireball_damage * (1.0 + 0.1 * float(maxi(level - 20, 0)))
	f.radius = fireball_radius
	f.warn_time = fireball_warn
	f.launch_at = (float(hand["frame"]) + 1.0) / CAST_FPS
	f.launch_from = global_position + hand["at"]
	f.global_position = target.global_position
	AttackGuard.bind(f, self)
	_add_ground_attack(f)


## Adds an attack to the scene root, just above the ground art (painted on the ground).
func _add_ground_attack(node: Node2D) -> void:
	var root := get_parent().get_parent()
	root.add_child(node)
	var ground := root.get_node_or_null("GroundArt")
	if ground:
		root.move_child(node, ground.get_index() + 1)


func _on_damaged(_amount: float) -> void:
	if state == State.WANDER:
		state = State.CHASE


func _on_died() -> void:
	state = State.DEAD
	KillCredit.award(stats, level, xp_reward, self, null, 0.0)
	cast_t = -1.0
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	Loot.spawn(get_parent(), position, Loot.roll([Loot.entry(drop_item, drop_min, drop_max)]), stats)
	_respawn_timer = DEATH_ANIM + respawn_time


func _respawn() -> void:
	position = _home
	stats.refill()
	shape.disabled = false
	state = State.WANDER
	_cast_timer = Rng.randf_range(0.8, 2.0)
	respawned.emit()


## Called by SleepRegions when this monster's region wakes up after `seconds` asleep.
func slept(seconds: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= seconds
