class_name Vordy
extends CharacterBody2D
## Vorly: a fat, not-very-bright dragon. Waddles around his spot,
## chases you if you get close, bites, and burps weak green fireballs.
## Gets bored and waddles home if you lead him too far away.
##
## This script is his BRAIN: state, targeting, spells, damage, loot. It draws nothing and
## never touches his sprite, so a server can run it headless. Everything visible (walk frames,
## squash and stretch, hit flash, death flop, fading) lives in vordy_look.gd, which listens
## to the signals below. Several players can fight him at once: he targets by threat (who has
## hurt him most), and everyone who did a real share of the damage gets XP and a chase-drop roll.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Vorly"
## Which quests count this kill. See Quests.kind_of.
@export var quest_kind := "vordy"
@export var level := 8
@export var xp_reward := 400

@export_group("Movement")
@export var wander_speed := 18.0
@export var chase_speed := 36.0
@export var wander_radius := 90.0
## Starts chasing when you're this close (pixels).
@export var aggro_range := 165.0
## Gives up if dragged this far from home.
@export var leash_range := 429.0

@export_group("Attacks")
@export var bite_damage := 100.0
@export var bite_range := 45.0
@export var bite_cooldown := 1.2
## How long the red wedge takes to fill before the bite lands.
@export var bite_warn := 0.4
@export var burp_damage := 20.0
@export var burp_range := 150.0
@export var burp_speed := 90.0

@export_group("Spell casting")
## Vorly's own global cooldown, shared by his spells (burp, slam, blob, gust)
## and independent of other bosses and of the player. Once it is up he picks
## one at random from whatever is in range.
@export var spell_cooldown := 3.0

@export_group("Boss mechanic")
## Rising-sun ground attack: yellow -> red over 2s, then green smoke.
@export var slam_range := 225.0
@export var slam_damage := 250.0

@export_group("Acid blob")
## Lobs a slow green blob at where you're standing; a big circle marks the landing.
@export var blob_range := 285.0
@export var blob_damage := 250.0
@export var blob_radius := 90.0
## How fast the blob crawls (world units per second).
@export var blob_speed := 55.0

@export_group("Orb barrage")
## Sits down, then rapid-fires small red orbs with quick little circles, one player after
## another. Lasts about `barrage_time` seconds; the cooldown counts from when it ends.
@export var barrage_range := 285.0
@export var barrage_time := 6.0
@export var barrage_cooldown := 10.0
@export var barrage_interval := 0.25
@export var barrage_damage := 60.0
@export var barrage_radius := 28.0
@export var barrage_travel := 0.7
@export_group("Wind gust")
## Huge cone telegraph, then a gust of green wind blasts across it.
@export var gust_range := 255.0
@export var gust_damage := 200.0
@export var gust_length := 240.0
@export var gust_spread := 50.0
@export var gust_warn := 1.1
## How long the wind wisps hang around after the gust reaches full length.
@export var gust_linger := 0.15

@export_group("Death")
@export var respawn_time := 20.0
## What he drops when killed.
@export var drop_item: Item
## Chase drop (a pet, say): rolled once per kill; each account can only ever get it once.
@export var unique_drop: Item
@export_range(0.0, 1.0) var unique_drop_chance := 0.0
@export var drop_min := 40
@export var drop_max := 120
## Extra drop rolled separately (chance 0..1), e.g. food.
@export var bonus_drop: Item
@export var bonus_drop_chance := 0.6
## Rare extra drop (a staff, say): plain item, rolled once per kill.
@export var rare_drop: Item
@export_range(0.0, 1.0) var rare_drop_chance := 0.0
@export var bonus_min := 1
@export var bonus_max := 2

## One-shot events for the look script (and, later, for network clients).
signal cast_started(kind: String, duration: float)
signal bitten
signal respawned

const FIREBALL := preload("res://scenes/fireball.tscn")
const TOXIC_ZONE := preload("res://scripts/toxic_zone.gd")
const RED_ORB := preload("res://scripts/red_orb.gd")
const WIND_CONE := preload("res://scripts/wind_cone.gd")
const BITE_STRIKE := preload("res://scripts/bite_strike.gd")
## His big-attack animation starts this long before the ground telegraph appears.
## The bite wedge starts this far in front of his centre so his body doesn't cover it.
const BITE_REACH_START := 24.0
## Where red orbs start: just above his head.
const ORB_ORIGIN_OFFSET := Vector2(0, -66)
const BITE_RECOVER := 0.12   ## swipe follow-through after the hit
## How long the sit-down takes before the barrage starts firing.
const BARRAGE_SIT := 0.8
const ANIM_LEAD := 0.4
const DEATH_ANIM := 2.85     ## how long the death animation plays before the respawn countdown (seconds)
const RETARGET_EVERY := 0.5

var state := State.WANDER
var facing_right := false
var facing := Vector2.DOWN      ## last direction he moved or aimed (the look picks the 4-way art from it)
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _bite_timer := 0.0
var _spells: SpellRotation      # Vorly's own spell list + cooldowns
var _target: Node2D             # who he is fighting
var _retarget_timer := 0.0
var _cast_lock := 0.0           # seconds left in the current cast (he stands still)
var _respawn_timer := 0.0

@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	_home = position
	_wander_target = position
	_spells = SpellRotation.new(spell_cooldown)
	# Spells are mostly switched off for now: the melee bite and the red orb are active. To bring
	# one back, add it here, e.g.  _spells.add("slam", slam_range, func(): _start_slam())
	# (the _start_slam / _start_gust / _burp functions below are still there).
	_spells.add("blob", blob_range, func(): _start_blob(_target))
	_spells.add("barrage", barrage_range, func(): _start_barrage(), 1.0, barrage_time + barrage_cooldown)
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func is_casting() -> bool:
	return _cast_lock > 0.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_bite_timer -= delta
	_cast_lock = maxf(_cast_lock - delta, 0.0)
	_retarget_timer -= delta
	_spells.tick(delta)

	var from_home := position.distance_to(_home)
	match state:
		State.WANDER:
			var seen := _nearest_in(aggro_range)
			if seen != null:
				_target = seen
				_retarget_timer = RETARGET_EVERY
				state = State.CHASE
		State.CHASE:
			if _retarget_timer <= 0.0 or not _valid_target(_target):
				_retarget_timer = RETARGET_EVERY
				_target = _choose_target()
			if _target == null or from_home > leash_range:
				_give_up()
		State.RETURN:
			if from_home < 8.0:
				state = State.WANDER

	var to_target := _target.global_position - global_position if _target != null else Vector2.INF
	var dist := to_target.length()
	var move := Vector2.ZERO
	var speed := wander_speed
	match state:
		State.WANDER:
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_pick_wander_target()
			if position.distance_to(_wander_target) > 3.0:
				move = position.direction_to(_wander_target)
		State.CHASE:
			speed = chase_speed
			if dist > bite_range * 0.8:
				move = to_target / dist
			if is_casting():
				move = Vector2.ZERO
			elif dist <= bite_range and _bite_timer <= 0.0:
				_bite(_target)           # up close, the melee swing comes first
			elif _cast_spell(_target, dist):
				move = Vector2.ZERO
		State.RETURN:
			speed = chase_speed
			move = position.direction_to(_home)
			stats.heal(stats.max_health * 0.25 * delta)  # heals up on the way home

	if is_casting():
		move = Vector2.ZERO
	if move.x != 0.0:
		facing_right = move.x > 0.0
	if move != Vector2.ZERO:
		facing = move
	elif _target != null and is_casting():
		facing = _target.global_position - global_position
	velocity = move * speed
	move_and_slide()


# ---- targeting (several players can be fighting him) ----------------------------------------

func _valid_target(p: Node2D) -> bool:
	if p == null or not is_instance_valid(p) or p.is_queued_for_deletion():
		return false
	var st := p.get_node_or_null("Stats") as Stats
	return (st == null or st.health > 0.0) and p.global_position.distance_to(_home) <= leash_range


func _nearest_in(radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius
	for p in Players.alive(get_tree()):
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Whoever has hurt him most (and is still here to fight). If nobody has, the nearest player.
func _choose_target() -> Node2D:
	var best: Node2D = null
	var best_threat := 0.0
	for p in Players.alive(get_tree()):
		if p.global_position.distance_to(_home) > leash_range:
			continue
		var threat := float(stats.contributions.get(p.get_instance_id(), 0.0))
		if threat > best_threat:
			best_threat = threat
			best = p
	return best if best != null else _nearest_in(aggro_range * 1.5)


func _give_up() -> void:
	state = State.RETURN
	_target = null
	stats.clear_contributions()   # a fight he walked away from credits nobody


# ---- spells ----------------------------------------------------------------------------------

## Casts one random in-range spell if his global cooldown is up.
func _cast_spell(player: Node2D, dist: float) -> bool:
	if player == null:
		return false
	_target = player
	return _spells.try_cast(dist) != ""


## Where the scene root is (attacks are added there, under the ground art).
func _add_ground_attack(node: Node2D) -> void:
	var root := get_parent().get_parent()
	root.add_child(node)
	var ground := root.get_node_or_null("GroundArt")
	if ground == null:
		ground = root.get_node_or_null("Ground")
	if ground:
		root.move_child(node, ground.get_index() + 1)


## Runs `action` after the animation lead-in, unless he died in the meantime.
func _after_lead(action: Callable, lead := ANIM_LEAD) -> void:
	if lead > 0.0:
		await get_tree().create_timer(lead, false, true).timeout   # counted in game ticks
	if state != State.DEAD and is_inside_tree():
		action.call()


func _start_slam() -> void:
	var zone: ToxicZone = TOXIC_ZONE.new()
	zone.damage = slam_damage
	AttackGuard.bind(zone, self)
	# rears up first, then the sun appears and charges until the smoke goes off
	_begin_cast("slam", ANIM_LEAD + zone.warn_time + 0.08 + 0.15)
	_after_lead(func():
		zone.global_position = global_position + Vector2(0, -6)
		_add_ground_attack(zone))


func _start_blob(_target_at_cast: Node2D) -> void:
	# the blob keeps crawling on its own, so he is free to move again soon after
	_begin_cast("blob", ANIM_LEAD + 0.25 + 0.1 + 0.15)
	_after_lead(func():
		var target := _target
		if not _valid_target(target):
			return
		var mouth := global_position + ORB_ORIGIN_OFFSET
		var blob: RedOrb = RED_ORB.new()
		blob.damage = blob_damage
		blob.radius = blob_radius
		blob.launch_from = mouth
		blob.travel_time = clampf(mouth.distance_to(target.global_position) / blob_speed, 1.6, 3.6)
		blob.global_position = target.global_position   # circle sits right on top of them
		AttackGuard.bind(blob, self)
		_add_ground_attack(blob))


## Sit-down orb barrage: after sitting down he fires a small red orb every `barrage_interval`
## seconds, each landing in a small quick circle on a player, taking turns between players.
func _start_barrage() -> void:
	_begin_cast("barrage", barrage_time)
	_barrage_loop()


func _barrage_loop() -> void:
	await get_tree().create_timer(BARRAGE_SIT, false, true).timeout
	var shots := int((barrage_time - BARRAGE_SIT - 0.2) / barrage_interval)
	var turn := 0
	for i in shots:
		if state == State.DEAD or not is_inside_tree():
			return
		var who: Array[Node2D] = []
		for p in Players.alive(get_tree()):
			if p.global_position.distance_to(_home) <= leash_range:
				who.append(p)
		if not who.is_empty():
			var target := who[turn % who.size()]
			turn += 1
			_fire_small_orb(target)
		await get_tree().create_timer(barrage_interval, false, true).timeout


func _fire_small_orb(target: Node2D) -> void:
	facing = target.global_position - global_position
	var mouth := global_position + ORB_ORIGIN_OFFSET
	var orb: RedOrb = RED_ORB.new()
	orb.damage = barrage_damage
	orb.radius = barrage_radius
	orb.blob_size = 5.0
	orb.arc_height = 14.0
	orb.launch_from = mouth
	# a little scatter so the stream isn't perfectly on top of you, but small enough that
	# simply moving still dodges it (first boss)
	orb.travel_time = barrage_travel * Rng.randf_range(0.92, 1.08)
	orb.global_position = target.global_position + Vector2.from_angle(Rng.randf() * TAU) * Rng.randf_range(0.0, barrage_radius * 0.35)
	AttackGuard.bind(orb, self)
	_add_ground_attack(orb)


func _start_gust(target: Node2D) -> void:
	var aim := target.global_position - global_position
	var cone: WindCone = WIND_CONE.new()
	cone.damage = gust_damage
	cone.length = gust_length
	cone.spread_deg = gust_spread
	cone.warn_time = gust_warn
	cone.linger_time = gust_linger
	cone.angle = aim.angle()
	AttackGuard.bind(cone, self)
	facing_right = aim.x > 0.0
	# he settles back exactly as the last wisp of wind dies out
	_begin_cast("gust", gust_warn + cone.sweep_time + cone.linger_time)
	_after_lead(func():
		cone.global_position = global_position + Vector2(0, -4)
		_add_ground_attack(cone), 0.0)


func _begin_cast(kind: String, duration: float) -> void:
	_cast_lock = duration
	if _target != null:
		facing = _target.global_position - global_position
	cast_started.emit(kind, duration)


func _pick_wander_target() -> void:
	# Half the time he just stands there staring at nothing.
	if Rng.chance(0.5):
		_wander_target = position
	else:
		_wander_target = _home + Vector2.from_angle(Rng.randf() * TAU) * Rng.randf_range(10.0, wander_radius)
	_wander_timer = Rng.randf_range(1.5, 4.0)


func _bite(player: Node2D) -> void:
	_bite_timer = bite_cooldown + ANIM_LEAD + bite_warn
	var dir := player.global_position - global_position
	var strike: BiteStrike = BITE_STRIKE.new()
	strike.direction = dir.normalized()
	strike.damage = bite_damage
	strike.length = bite_range + 17.0
	strike.spread_deg = 95.0
	strike.warn_time = bite_warn
	strike.caster = self
	AttackGuard.bind(strike, self)
	# same lead-in animation as the big attacks, then the wedge starts filling
	_begin_cast("bite", ANIM_LEAD + bite_warn + BITE_RECOVER)
	_after_lead(func():
		strike.global_position = global_position + Vector2(0, -6) + strike.direction * BITE_REACH_START
		_add_ground_attack(strike)
		bitten.emit())


func _burp(dir: Vector2) -> void:
	var p := FIREBALL.instantiate()
	p.global_position = global_position + Vector2(30 if facing_right else -30, -33)
	p.direction = dir
	p.speed = burp_speed
	p.damage = burp_damage
	p.caster = self
	p.modulate = Color(0.55, 1.0, 0.35)  # gross green burp fire
	p.scale = Vector2(0.8, 0.8)
	get_parent().add_child(p)


# ---- being hurt, dying, coming back ---------------------------------------------------------

func _on_damaged(_amount: float) -> void:
	if state == State.WANDER:
		state = State.CHASE  # even he notices getting set on fire
		_retarget_timer = 0.0


func _on_died() -> void:
	state = State.DEAD
	_target = null
	_cast_lock = 0.0
	KillCredit.award(stats, level, xp_reward, self, unique_drop, unique_drop_chance)
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	_drop_loot()
	_respawn_timer = DEATH_ANIM + respawn_time


func _drop_loot() -> void:
	var drops := Loot.roll([
		Loot.entry(rare_drop, 1, 1, rare_drop_chance, Vector2(6, 14), 10.0),
		Loot.entry(bonus_drop, bonus_min, bonus_max, bonus_drop_chance, Vector2(-14, -6), 10.0),
		Loot.entry(drop_item, drop_min, drop_max, 1.0, Vector2(-8, 8), 6.0),
	])
	Loot.spawn(get_parent(), position, drops, stats)


func _respawn() -> void:
	position = _home
	reset_physics_interpolation()   # appear at home at once, no slide
	stats.refill()
	shape.disabled = false
	state = State.WANDER
	_target = null
	respawned.emit()

## Called by SleepRegions when this monster's region wakes up after `seconds` asleep:
## time still passed, so a respawn countdown catches up.
func slept(seconds: float) -> void:
	if state == State.DEAD:
		_respawn_timer -= seconds
