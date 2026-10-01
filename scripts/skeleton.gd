extends CharacterBody2D
## Skeleton: a graveyard warrior. Shambles near its spot, chases when you get
## close, then telegraphs a red lane on the ground and lunges forward down it
## with its rusty sword.

enum State { WANDER, CHASE, RETURN, DEAD }

@export var display_name := "Skeleton"
@export var level := 3
## XP at level 3; higher-level skeletons are worth proportionally more.
@export var xp_reward := 30
@export_group("Boss")
## 1 = normal. Bigger values make a larger, tougher version of the same skeleton.
@export var boss_scale := 1.0
@export var health_mult := 1.0
@export_group("")

@export_group("Movement")
@export var wander_speed := 12.0
@export var chase_speed := 34.0
@export var wander_radius := 40.0
@export var aggro_range := 95.0
@export var leash_range := 170.0

@export_group("Lunge")
## Starts the wind-up when you're this close.
@export var lunge_range := 40.0
@export var lunge_cooldown := 2.6
@export var lunge_damage := 60.0
@export var lunge_length := 44.0
@export var lunge_width := 18.0
@export var lunge_warn := 0.7
## How far it actually dashes, and how long the dash takes.
@export var lunge_distance := 30.0
@export var lunge_time := 0.14

@export_group("Boulder rain")
## Boss only: covers the whole chamber in falling boulders.
@export var rain_enabled := false
@export var rain_cooldown := 14.0
@export var rain_radius := 15.8
## How many boulders per barrage.
@export var rain_count := 60
@export var rain_warn := 1.1
@export var rain_spread := 0.8
@export var rain_damage := 90.0
## The chamber, in the cave's own coordinates (x, y, width, height).
@export var rain_rect := Rect2(650, 12, 520, 206)

@export_group("Stone walls")
## Boss only: stripes of spiky stone that erupt right to left across the chamber.
@export var walls_enabled := false
@export var walls_cooldown := 13.0
@export var walls_thickness := 16.0    ## stripe thickness = safe gap between stripes
@export var walls_warn := 1.3
@export var walls_speed := 650.0
@export var walls_damage := 100.0

@export_group("Death")
@export var respawn_time := 6.0
@export var drop_item: Item
## Chase drop (a pet, say): rolled once per kill; each account can only ever get it once.
@export var unique_drop: Item
@export_range(0.0, 1.0) var unique_drop_chance := 0.0
@export var drop_min := 3
@export var drop_max := 14

const STRIKE := preload("res://scripts/lunge_strike.gd")
const RAIN := preload("res://scripts/boulder_rain.gd")
const WALLS := preload("res://scripts/stone_walls.gd")
const PICKUP := preload("res://scenes/pickup.tscn")

var state := State.WANDER
var _home: Vector2
var _wander_target: Vector2
var _wander_timer := 0.0
var _lunge_timer := 0.0
var _winding := 0.0        # seconds left in the wind-up (0 = not winding up)
var _lunging := 0.0        # seconds left in the dash
var _recover := 0.0        # brief pause after the dash
var _lunge_dir := Vector2.LEFT
var _t := 0.0
var _rain_timer := 6.0
var _walls_timer := 10.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var stats: Stats = $Stats


func _ready() -> void:
	add_to_group("monsters")
	_home = position
	_wander_target = position
	_t = randf() * 10.0
	_lunge_timer = randf_range(1.0, 3.0)
	# stronger and worth more at higher levels
	var lv := maxi(level - 3, 0)
	stats.max_health *= (1.0 + 0.25 * float(lv)) * health_mult
	lunge_damage *= 1.0 + 0.15 * float(maxi(level - 4, 0))
	if boss_scale != 1.0:
		sprite.scale *= boss_scale
		shape.scale = Vector2(boss_scale, boss_scale)
		var np_ := get_node_or_null("Nameplate") as Node2D
		if np_:
			np_.position.y *= boss_scale
		lunge_distance *= boss_scale
	stats.refill()
	xp_reward = int(round(float(xp_reward) * (1.0 + 0.33 * float(lv))))
	stats.died.connect(_on_died)
	stats.damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_t += delta
	_lunge_timer -= delta
	_rain_timer -= delta
	_walls_timer -= delta
	if _winding > 0.0:
		_winding -= delta
	if _recover > 0.0:
		_recover -= delta

	var player := Players.nearest(get_tree(), global_position)
	var to_player := player.global_position - global_position if player else Vector2.INF
	var dist := to_player.length()
	var from_home := position.distance_to(_home)

	if _lunging > 0.0:
		_lunging -= delta
		velocity = _lunge_dir * (lunge_distance / lunge_time)
		move_and_slide()
		_animate(Vector2.ZERO)
		if _lunging <= 0.0:
			_recover = 0.3
		return

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
			if _winding <= 0.0 and _recover <= 0.0:
				if rain_enabled and _rain_timer <= 0.0 and dist < aggro_range * 2.0:
					_start_rain()
				elif walls_enabled and _walls_timer <= 0.0 and dist < aggro_range * 2.0:
					_start_walls()
				elif dist <= lunge_range and _lunge_timer <= 0.0 and not _special_ready():
					_start_lunge(to_player / dist)
				elif dist > lunge_range * 0.6:
					move = to_player / dist
		State.RETURN:
			speed = chase_speed
			move = position.direction_to(_home)
			stats.heal(stats.max_health * 0.3 * delta)

	if _winding > 0.0 or _recover > 0.0:
		move = Vector2.ZERO
	velocity = move * speed
	move_and_slide()
	_animate(move)


## True when one of the boss's telegraphed attacks is off cooldown. Those always
## come before the basic lunge.
func _special_ready() -> bool:
	return (rain_enabled and _rain_timer <= 0.0) or (walls_enabled and _walls_timer <= 0.0)


func _start_rain() -> void:
	var cave := get_tree().get_first_node_in_group("cave") as Node2D
	if cave == null:
		_rain_timer = rain_cooldown
		return
	# random boulders all over the chamber, each 5-25% bigger or smaller than the base size
	var ring: PackedVector2Array = cave.get("ring")
	var global_ring := PackedVector2Array()
	for p in ring:
		global_ring.append(cave.to_global(p))
	var spots: Array[Vector2] = []
	var radii: Array[float] = []
	var tries := 0
	while spots.size() < rain_count and tries < 4000:
		tries += 1
		var rad := rain_radius * (1.0 + randf_range(0.05, 0.25) * (1.0 if randf() < 0.5 else -1.0))
		var g := cave.to_global(rain_rect.position + Vector2(randf() * rain_rect.size.x, randf() * rain_rect.size.y))
		var ok := true
		for off in [Vector2.ZERO, Vector2(rad + 3, 0), Vector2(-rad - 3, 0), Vector2(0, rad + 3), Vector2(0, -rad - 3)]:
			if not Geometry2D.is_point_in_polygon(g + off, global_ring):
				ok = false
				break
		if ok:
			for j in spots.size():
				if g.distance_to(spots[j]) < (rad + radii[j]) * 0.9:   # may touch a little, never stack
					ok = false
					break
		if ok:
			spots.append(g)
			radii.append(rad)
	var r: BoulderRain = RAIN.new()
	r.spots = spots
	r.radii = radii
	r.radius = rain_radius
	r.warn_time = rain_warn
	r.spread = rain_spread
	r.damage = rain_damage
	r.caster = self
	AttackGuard.bind(r, self)
	var root := get_parent().get_parent()
	root.add_child(r)
	var ground := root.get_node_or_null("GroundArt")
	if ground:
		root.move_child(r, ground.get_index() + 1)
	_rain_timer = rain_cooldown
	_walls_timer = maxf(_walls_timer, 6.0)
	_winding = rain_warn + rain_spread + 0.3     # arms raised while the rocks fall
	_lunge_timer = maxf(_lunge_timer, _winding + 1.0)


func _start_walls() -> void:
	var cave := get_tree().get_first_node_in_group("cave") as Node2D
	if cave == null:
		_walls_timer = walls_cooldown
		return
	var ring: PackedVector2Array = cave.get("ring")
	var global_ring := PackedVector2Array()
	for p in ring:
		global_ring.append(cave.to_global(p))
	# horizontal stripes, each as thick as the gap between them
	var t := walls_thickness
	var cell_w := 24.0       # three 8-unit stretches per chunk: one third the objects
	var cells: Array[Rect2] = []
	var y := cave.to_global(rain_rect.position).y + randf() * t
	var y_end := cave.to_global(rain_rect.end).y
	var x0 := cave.to_global(rain_rect.position).x
	var x1 := cave.to_global(rain_rect.end).x
	while y + t <= y_end:
		var x := x0
		while x < x1:
			var r := Rect2(x, y, cell_w, t)
			var ok := true
			for pt in [r.get_center(), r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end, Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]:
				if not Geometry2D.is_point_in_polygon(pt, global_ring):
					ok = false
					break
			if ok:
				cells.append(r)
			x += cell_w
		y += t * 2.0
	var w: StoneWalls = WALLS.new()
	w.cells = cells
	w.warn_time = walls_warn
	w.wave_speed = walls_speed
	w.damage = walls_damage
	w.caster = self
	AttackGuard.bind(w, self)
	var root := get_parent().get_parent()
	root.add_child(w)
	var ground := root.get_node_or_null("GroundArt")
	if ground:
		root.move_child(w, ground.get_index() + 1)
	_walls_timer = walls_cooldown
	_rain_timer = maxf(_rain_timer, 6.0)
	_winding = walls_warn + (x1 - x0) / walls_speed + 0.3
	_lunge_timer = maxf(_lunge_timer, _winding + 1.0)


func _start_lunge(dir: Vector2) -> void:
	_lunge_timer = lunge_cooldown
	_winding = lunge_warn
	_lunge_dir = dir
	var s: LungeStrike = STRIKE.new()
	s.direction = dir
	s.damage = lunge_damage
	s.length = lunge_length
	s.width = lunge_width
	s.warn_time = lunge_warn
	s.caster = self
	s.global_position = global_position + Vector2(0, -8)
	AttackGuard.bind(s, self)
	var root := get_parent().get_parent()
	root.add_child(s)
	var ground := root.get_node_or_null("GroundArt")
	if ground == null:
		ground = root.get_node_or_null("Ground")
	if ground:
		root.move_child(s, ground.get_index() + 1)   # painted on the ground, under everyone
	sprite.flip_h = dir.x > 0.0   # art faces left


## Called by the telegraph when it's full: the dash forward.
func begin_lunge(dir: Vector2) -> void:
	if state == State.DEAD:
		return
	_winding = 0.0
	_lunging = lunge_time
	_lunge_dir = dir
	sprite.flip_h = dir.x > 0.0


func _animate(move: Vector2) -> void:
	if _lunging > 0.0:
		sprite.frame = 3                 # sword thrust
		sprite.rotation = 0.0
		return
	if _winding > 0.0:
		sprite.frame = 2                 # sword cocked back
		sprite.rotation = 0.0
		return
	if _recover > 0.0:
		sprite.frame = 3
		sprite.rotation = 0.0
		return
	if move.x != 0.0:
		sprite.flip_h = move.x > 0.0
	if move != Vector2.ZERO:
		sprite.frame = int(_t * 6.0) % 2
		sprite.rotation = sin(_t * 12.0) * 0.06
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
	_winding = 0.0
	_lunging = 0.0
	velocity = Vector2.ZERO
	shape.set_deferred("disabled", true)
	Loot.spawn(get_parent(), position, Loot.roll([Loot.entry(drop_item, drop_min, drop_max)]))
	# collapses into a heap of bones
	sprite.rotation = 0.0
	sprite.frame = 0
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(0.5, 0.2), 0.18)
	tw.tween_interval(0.8)
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_interval(respawn_time)
	tw.tween_callback(_respawn)


func _respawn() -> void:
	position = _home
	sprite.rotation = 0.0
	sprite.scale = Vector2(0.5, 0.5)
	stats.refill()
	shape.disabled = false
	state = State.WANDER
	_lunge_timer = randf_range(1.0, 3.0)
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
