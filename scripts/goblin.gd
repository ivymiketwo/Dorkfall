extends CharacterBody2D
## Goblin: a small, weak forest raider that comes in big numbers (enchanted forest). Not a
## dodging fight like the other monsters: there is no warning on the ground, it just runs at you
## faster than you walk and punches. Each one dies in a couple of hits; the danger is the ones
## that get through. When one spots you (or gets hit) it shouts, and the goblins around it join
## in, so they come in waves.
##
## This script is the BRAIN: state, targeting, the punch, loot, respawn. It draws nothing, so a
## server can run it headless. Everything visible is in goblin_look.gd.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Goblin"
## Which quests count this kill. See Quests.kind_of.
@export var quest_kind := "goblin"
@export var level := 24
@export var xp_reward := 60

@export_group("Movement")
@export var wander_speed := 14.0
## Running at you. The player walks at 70.
@export var chase_speed := 92.0
@export var wander_radius := 40.0
@export var aggro_range := 110.0
## Goblins this close to one that spots you (or gets hit) join the chase.
@export var call_range := 85.0
@export var leash_range := 380.0

@export_group("Punch")
## Starts a punch when you're this close (from its feet to yours).
@export var punch_range := 22.0
## The punch hits if you're still this close, roughly in front of it, when the fist lands.
@export var punch_reach := 24.0
@export var punch_arc_deg := 160.0
@export var punch_damage := 30.0
## The whole punch, and when in it the fist lands (seconds). No warning beyond the swing itself.
## It keeps running at you while it swings, so walking away doesn't dodge it: you have to kill it
## (or out-run it with momentum).
@export var punch_time := 0.28
@export var punch_hit_at := 0.12
## Stops closing in when this near (so a crowd doesn't climb into you).
@export var crowd_distance := 9.0
## Seconds between punches (random in this range, so a crowd doesn't punch in step).
@export var punch_cooldown_min := 0.55
@export var punch_cooldown_max := 0.95

@export_group("Death")
@export var respawn_time := 25.0
@export var drop_item: Item
@export var drop_min := 6
@export var drop_max := 16

## One-shot events for the look script (and, later, for network clients).
signal respawned
signal punched(side: int)

## How long the fall-and-fade plays before the respawn countdown starts (seconds).
const DEATH_ANIM := 0.9

var state := State.WANDER
## Last direction it moved or punched in (the look picks its art from this).
var facing := Vector2.DOWN
## Direction of the current punch, and which hand (0 = as drawn, 1 = mirrored).
var punch_dir := Vector2.DOWN
var punch_side := 0
## Seconds into the current punch (-1 = not punching).
var punch_t := -1.0
var _hit_done := false
var _punch_timer := 0.0
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _respawn_timer := 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	add_to_group("goblins")
	_home = position
	_wander_target = position
	_wander_timer = Rng.randf_range(0.0, 3.0)
	stats.refill()
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func is_punching() -> bool:
	return punch_t >= 0.0


func is_running() -> bool:
	return state == State.CHASE or state == State.RETURN


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_punch_timer -= delta

	var player := Players.nearest(get_tree(), global_position, true)
	var to_player := player.global_position - global_position if player else Vector2.INF
	var dist := to_player.length()
	var from_home := position.distance_to(_home)

	if punch_t >= 0.0:
		_punch_step(delta, player, to_player, dist)
		return

	match state:
		State.WANDER:
			if dist < aggro_range:
				_aggro()
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
			if dist <= punch_range and _punch_timer <= 0.0:
				_start_punch(to_player / maxf(dist, 0.01))
				_punch_step(0.0, player, to_player, dist)
				return
			if dist > crowd_distance:
				move = to_player / dist
			else:
				facing = to_player
		State.RETURN:
			speed = chase_speed
			move = position.direction_to(_home)
			stats.heal(stats.max_health * 0.5 * delta)

	if move != Vector2.ZERO:
		facing = move
	velocity = move * speed
	move_and_slide()


## Spotted you: chase, and shout to the goblins around (they join in, but don't shout on).
func _aggro() -> void:
	if state != State.WANDER:
		return
	state = State.CHASE
	_punch_timer = maxf(_punch_timer, 0.0)
	for g in get_tree().get_nodes_in_group("goblins"):
		if g != self and g.state == State.WANDER and \
				(g as Node2D).global_position.distance_to(global_position) <= call_range:
			g.state = State.CHASE


func _start_punch(dir: Vector2) -> void:
	punch_t = 0.0
	_hit_done = false
	punch_dir = dir
	facing = dir
	punch_side = Rng.randi_range(0, 1)
	punched.emit(punch_side)


## The swing: keeps running at the target (and turning to it) until the fist lands, so a player
## who just walks away still gets hit.
func _punch_step(delta: float, target: Node2D, to_target: Vector2, dist: float) -> void:
	punch_t += delta
	velocity = Vector2.ZERO
	if target != null and dist > crowd_distance:
		velocity = to_target / dist * chase_speed
		if not _hit_done:
			punch_dir = to_target / dist
			facing = punch_dir
	move_and_slide()
	if not _hit_done and punch_t >= punch_hit_at:
		_hit_done = true
		for p in Players.alive(get_tree()):
			var rel: Vector2 = p.global_position - global_position
			if rel.length() <= punch_reach and \
					absf(angle_difference(punch_dir.angle(), rel.angle())) <= deg_to_rad(punch_arc_deg) * 0.5:
				AttackRules.deal(p, punch_damage, self, global_position)
	if punch_t >= punch_time:
		punch_t = -1.0
		_punch_timer = Rng.randf_range(punch_cooldown_min, punch_cooldown_max)


func _on_damaged(_amount: float) -> void:
	if state == State.WANDER:
		_aggro()


func _on_died() -> void:
	state = State.DEAD
	KillCredit.award(stats, level, xp_reward, self, null, 0.0)
	punch_t = -1.0
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
	_punch_timer = 0.0
	respawned.emit()


## Called by SleepRegions when this monster's region wakes up after `seconds` asleep:
## time still passed, so a respawn countdown catches up.
func slept(seconds: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= seconds
