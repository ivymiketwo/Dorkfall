extends CharacterBody2D
## Mangyang: a low-level animated scarecrow that hops about. Wanders near its spot, chases
## when you get close, then darkens a circle under you and sends a swarm of crows at it.
##
## This script is the BRAIN: state, targeting, the throw, loot, respawn. It draws nothing
## (same pattern as vordy.gd). Everything visible lives in mangyang_look.gd.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Mangyang"
## Which quests count this kill. See Quests.kind_of.
@export var quest_kind := "mangyang"
@export var level := 1
## XP for killing it at equal level (30 kills = level 2).
@export var xp_reward := 10

@export_group("Movement")
@export var wander_speed := 14.0
@export var chase_speed := 30.0
@export var wander_radius := 30.0
@export var aggro_range := 90.0
@export var leash_range := 208.0

@export_group("Crow swarm")
@export var throw_range := 85.0
@export var throw_cooldown := 3.5
@export var throw_damage := 50.0
@export var swarm_radius := 20.0
## Seconds from the circle appearing to the crows hitting (the scarecrow stands still meanwhile).
@export var throw_warn := 1.0

@export_group("Death")
@export var respawn_time := 5.0
@export var drop_item: Item
## Chase drop (a pet, say): rolled once per kill; each account can only ever get it once.
@export var unique_drop: Item
@export_range(0.0, 1.0) var unique_drop_chance := 0.0
@export var drop_min := 1
@export var drop_max := 7

## One-shot events for the look script (and, later, for network clients).
signal respawned

const SWARM := preload("res://scripts/crow_swarm.gd")
## It moves in hops: one hop = HOP_TIME seconds; it only covers ground while in the air.
const HOP_TIME := 0.7
const HOP_AIR := Vector2(0.55, 0.86)    ## part of the hop spent in the air (frames 5-6 of 7)
## How long the topple-and-fade plays before the respawn countdown starts (seconds).
const DEATH_ANIM := 1.65

var state := State.WANDER
## Last direction it moved or threw in.
var facing := Vector2.LEFT
## 0 down, 1 up, 2 left, 3 right (the look picks its row from this).
var face := 0
## How far through the current hop (0..1); the look shows the matching frame.
var hop := 0.0
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _throw_timer := 0.0
var _throwing := 0.0     # seconds left in the wind-up (0 = not throwing)
var _respawn_timer := 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	_home = position
	_wander_target = position
	_throw_timer = Rng.randf_range(1.0, 3.0)
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func is_throwing() -> bool:
	return _throwing > 0.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_throw_timer -= delta
	if _throwing > 0.0:
		_throwing -= delta

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
	if move != Vector2.ZERO:
		facing = move
		face = _face_of(move)
		hop = fmod(hop + delta / HOP_TIME, 1.0)
		# hops: covers its ground while in the air, barely moves while crouched on the ground
		var air := hop >= HOP_AIR.x and hop < HOP_AIR.y
		speed *= 1.0 / (HOP_AIR.y - HOP_AIR.x) * 0.9 if air else 0.1
	elif hop > 0.0:
		hop = minf(hop + delta / HOP_TIME, 1.0)    # finish the hop it's in, then stand
		if hop >= 1.0:
			hop = 0.0
	velocity = move * speed
	move_and_slide()


static func _face_of(dir: Vector2) -> int:
	if absf(dir.x) > absf(dir.y):
		return 2 if dir.x < 0.0 else 3
	return 0 if dir.y > 0.0 else 1


func _start_throw(dir: Vector2) -> void:
	_throw_timer = throw_cooldown
	_throwing = throw_warn
	facing = dir
	face = _face_of(dir)
	var target := Players.nearest(get_tree(), global_position, true)
	var k: CrowSwarm = SWARM.new()
	k.damage = throw_damage
	k.radius = swarm_radius
	k.warn_time = throw_warn
	k.launch_from = global_position
	k.global_position = target.global_position if target else global_position + dir * 40.0
	AttackGuard.bind(k, self)
	var root := get_parent().get_parent()
	root.add_child(k)
	var ground := root.get_node_or_null("GroundArt")
	if ground == null:
		ground = root.get_node_or_null("Ground")
	if ground:
		root.move_child(k, ground.get_index() + 1)   # painted on the ground, under everyone


func _on_damaged(_amount: float) -> void:
	if state == State.WANDER:
		state = State.CHASE


func _on_died() -> void:
	state = State.DEAD
	KillCredit.award(stats, level, xp_reward, self, unique_drop, unique_drop_chance)
	_throwing = 0.0
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	Loot.spawn(get_parent(), position, Loot.roll([Loot.entry(drop_item, drop_min, drop_max)]), stats)
	_respawn_timer = DEATH_ANIM + respawn_time


func _respawn() -> void:
	position = _home
	reset_physics_interpolation()   # appear at home at once, no slide
	stats.refill()
	shape.disabled = false
	state = State.WANDER
	_throw_timer = Rng.randf_range(1.0, 3.0)
	respawned.emit()

## Called by SleepRegions when this monster's region wakes up after `seconds` asleep:
## time still passed, so a respawn countdown catches up.
func slept(seconds: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= seconds
