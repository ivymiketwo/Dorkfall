extends CharacterBody2D
## Top-down player: 8-direction movement, 4-direction facing, 2-frame walk cycle,
## sprinting that costs stamina, and health/stamina/mana via the Stats child.

@export var display_name := "Rex"
@export var speed := 70.0              ## pixels per second
@export var walk_fps := 7.0            ## walk animation speed (4 steps per cycle)
@export var sprint_multiplier := 1.6
@export var sprint_stamina_per_sec := 12.0
@export var hop_ability: Ability        ## the Space-key gust hop (not on the hotbar)

@export_group("Debug keys")
@export var debug_damage := 50.0       ## F1
@export var debug_mana_cost := 50.0    ## F2
## F3 gives 100 coins, F4 gives a set of test gear

# player_new.png: 9 columns; rows = animation * 4 + facing (down, up, left, right).
# Animations: 0 idle (4 frames), 1 run (4 frames), 2 jump (9 frames, 8 for the robed north/south).
enum Facing { DOWN, UP, LEFT, RIGHT }
const ANIM_IDLE := 0
const ANIM_RUN := 1
const ANIM_JUMP := 2
const IDLE_FPS := 4.0
const ROBE_JUMP_TEX := preload("res://art/player_new_robe_jump.png")
const NAKED_TEX := preload("res://art/player_new.png")
const ROBE_JUMP_FRAMES := [8, 8, 9, 9]   # per facing, in the robed jump

@onready var sprite: Sprite2D = $Sprite2D
@onready var stats: Stats = $Stats
@onready var inventory: Inventory = $Inventory

const COINS := preload("res://items/coins.tres")
const TEST_GEAR := [preload("res://items/iron_sword.tres"), preload("res://items/wooden_shield.tres"),
		preload("res://items/iron_helm.tres"), preload("res://items/wizard_hat.tres"),
		preload("res://items/leather_armor.tres")]

## What the player is asking for right now. Only `_gather_input` reads the keyboard and mouse;
## everything else (movement, casting, melee, guarding) uses these values, so a server can
## be fed the same data over the network.
var input_dir := Vector2.ZERO
var input_sprint := false
var input_guard := false
var aim_world := Vector2.ZERO      ## where in the world the player is aiming

var facing := Facing.DOWN
var _anim_time := 0.0
var _idle_mat: ShaderMaterial
var _idle_time := 0.0
const IDLE_BOB_PERIOD := 0.6   ## seconds per up/down step while standing still
var _spawn_point: Vector2

# Gust hop (bunnyhop): leap along a ballistic arc; landing opens a quick window to press Space again.
const HOP_GUST := preload("res://scripts/hop_gust.gd")
var _hop_ab: Ability
var _hop_dir := Vector2.DOWN
var _hop_t := -1.0          ## seconds into the current leap (-1 = not airborne)
var _hop_window := 0.0      ## seconds left to press Space after landing
var _jump_buffer := 0.0     ## Space pressed just before landing still counts
var _hop_ring: Node2D
var _hop_cooldown := 0.0


func _ready() -> void:
	add_to_group("player")
	_ensure_input_actions()
	_spawn_point = position
	stats.died.connect(_on_died)
	_idle_mat = ShaderMaterial.new()
	_idle_mat.shader = load("res://shaders/idle_bob.gdshader")
	_idle_mat.set_shader_parameter("vframes", float(sprite.vframes))
	sprite.material = _idle_mat    # gear layers copy this (see Equipment)


func _gather_input() -> void:
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input_sprint = Input.is_action_pressed("sprint")
	input_guard = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_physical_key_pressed(KEY_Q)
	if ChatLog.typing:          # typing a message: the keys are for the chat
		input_dir = Vector2.ZERO
		input_sprint = false
		input_guard = false
	aim_world = get_global_mouse_position()


func _process(_delta: float) -> void:
	_gather_input()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		aim_world = get_global_mouse_position()


func _physics_process(delta: float) -> void:
	_gather_input()
	_hop_cooldown = maxf(_hop_cooldown - delta, 0.0)
	if _hop_ab:
		if _hop_t >= 0.0:
			_hop_step(delta)
			return
		_hop_window -= delta              # landed: move freely while the Space window ticks down
		if _hop_window <= 0.0:
			_hop_end()
	var dir: Vector2 = input_dir
	var move_speed := speed
	var sprinting := false
	var guard := get_node_or_null("Guard") as Guard
	var guarding := guard != null and guard.guarding
	if guarding:
		move_speed *= 0.5   # shield up: slow going
	if dir != Vector2.ZERO and not guarding and input_sprint:
		sprinting = stats.spend_stamina(sprint_stamina_per_sec * delta)
		if sprinting:
			move_speed *= sprint_multiplier
	velocity = dir * move_speed
	_corner_nudge(dir, move_speed, delta)
	move_and_slide()
	_update_animation(dir, delta * (sprint_multiplier if sprinting else 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and _hop_ab:
		if _hop_t >= 0.0:
			_jump_buffer = 0.05
		elif _hop_window > 0.0:
			stats.take_damage(_hop_ab.hop_chain_health_cost, null, true)       # chaining a hop costs blood
			if _hop_ab:                                       # (dying ends the chain)
				_hop_leap()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump") and hop_ability:
		start_hop(hop_ability)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_damage"):
		stats.take_damage(debug_damage)
	elif event.is_action_pressed("debug_spend_mana"):
		stats.spend_mana(debug_mana_cost)
	elif event.is_action_pressed("debug_coins"):
		inventory.add(COINS, 100)
	elif event.is_action_pressed("debug_sword"):
		for g: Item in TEST_GEAR:
			inventory.add(g, 1)
	elif event.is_action_pressed("interact"):
		_interact()


## Called by the hotbar. Returns false if a hop chain is already running.
func start_hop(ab: Ability) -> bool:
	if _hop_ab or _hop_cooldown > 0.0:
		return false
	if not stats.spend_mana(ab.mana_cost):
		stats.warn_out_of_mana()
		return false
	if ab.hop_health_cost > 0.0:
		var dies := stats.health <= ab.hop_health_cost
		stats.take_damage(ab.hop_health_cost)
		if dies:
			return false
	_hop_ab = ab
	_hop_dir = _hop_input_dir()
	_hop_leap()
	return true


func _hop_input_dir() -> Vector2:
	var d := input_dir
	if d != Vector2.ZERO:
		return d.normalized()
	if _hop_ab and _hop_t == -1.0 and _hop_window > 0.0 and _hop_dir != Vector2.ZERO:
		return _hop_dir
	return [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT][facing]


func _hop_leap() -> void:
	_hop_dir = _hop_input_dir()
	_hop_t = 0.0
	_hop_window = 0.0
	_jump_buffer = 0.0
	if _hop_ring:
		_hop_ring.queue_free()
		_hop_ring = null
	facing = (Facing.RIGHT if _hop_dir.x > 0 else Facing.LEFT) if absf(_hop_dir.x) > absf(_hop_dir.y) \
			else (Facing.DOWN if _hop_dir.y > 0 else Facing.UP)
	var gust := Node2D.new()
	gust.set_script(HOP_GUST)
	gust.direction = _hop_dir
	gust.global_position = global_position
	get_parent().add_child(gust)


func _hop_step(delta: float) -> void:
	_idle_time = 0.0
	_idle_mat.set_shader_parameter("bob", 0.0)
	if _hop_t >= 0.0:
		_hop_t += delta
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
		var k := clampf(_hop_t / _hop_ab.hop_time, 0.0, 1.0)
		_set_jump_frame(k)
		sprite.position.y = -4.0 * _hop_ab.hop_height * k * (1.0 - k)      # parabola, apex at k = 0.5
		velocity = _hop_dir * _hop_ab.hop_speed
		move_and_slide()
		if k >= 1.0:
			_hop_land()


func _wearing_robe() -> bool:
	var eq := get_node_or_null("Equipment") as Equipment
	var it: Item = eq.get_item("chest") if eq else null
	return it != null and it.id == &"wizard_robe"


func _set_jump_frame(k: float) -> void:
	var robe := _wearing_robe()
	var tex: Texture2D = ROBE_JUMP_TEX if robe else NAKED_TEX
	if sprite.texture != tex:
		sprite.texture = tex
	var n: int = ROBE_JUMP_FRAMES[facing] if robe else 9
	sprite.frame = (ANIM_JUMP * 4 + facing) * sprite.hframes + mini(int(k * n), n - 1)


func _hop_land() -> void:
	sprite.position.y = 0.0
	_hop_t = -1.0
	if _jump_buffer > 0.0:
		stats.take_damage(_hop_ab.hop_chain_health_cost, null, true)
		if _hop_ab:
			_hop_leap()
		return
	_hop_window = _hop_ab.hop_window
	_hop_ring = HopRing.new()
	_hop_ring.life = _hop_window
	add_child(_hop_ring)
	move_child(_hop_ring, 0)          # drawn under the sprite, above the ground


func _hop_end() -> void:
	if _hop_ab:
		_hop_cooldown = _hop_ab.cooldown   # the cooldown starts when the chain ends
	_hop_ab = null
	_hop_t = -1.0
	_hop_window = 0.0
	sprite.position.y = 0.0
	if _hop_ring:
		_hop_ring.queue_free()
		_hop_ring = null


## F: close an open shop, or talk to the nearest shopkeeper in range.
func _interact() -> void:
	var ui := get_tree().get_first_node_in_group("shop_ui")
	if ui and ui.visible:
		ui.close()
		return
	var qui := get_tree().get_first_node_in_group("quest_ui")
	if qui and qui.visible:
		qui.close()
		return
	var dui := get_tree().get_first_node_in_group("dialogue_ui")
	if dui and dui.visible:
		dui.close()
		return
	var best: Node = null
	var best_d := INF
	for n: Node2D in get_tree().get_nodes_in_group("interactables"):
		var d := global_position.distance_to(n.global_position)
		if d <= n.interact_range and d < best_d:
			best = n
			best_d = d
	if best:
		best.interact(self)


func _on_died() -> void:
	_hop_end()
	_leave_gravestone()
	# Respawn at the start with full stats.
	position = _spawn_point
	stats.refill()
	# pets come along to the respawn point
	var n := 0
	for pet in get_tree().get_nodes_in_group("pets"):
		if pet is Pet:
			pet.call_deferred("join_player", self, n)
			n += 1


## Everything carried and worn goes onto a gravestone where you fell.
func _leave_gravestone() -> void:
	var stone := Gravestone.new()
	stone.name = "Gravestone"
	stone.owner_name = display_name
	for e: Dictionary in inventory.take_unbound():
		stone.add_loot(e["item"], e["count"])
	var eq := get_node_or_null("Equipment") as Equipment
	if eq:
		for slot: String in eq.items.keys():
			if eq.items[slot] != null and not eq.items[slot].soulbound:
				stone.add_loot(eq.items[slot], 1)
				eq.items.erase(slot)
		eq._refresh()
	if stone.loot.is_empty():
		stone.free()
		return
	stone.position = position
	get_parent().add_child(stone)


func _update_animation(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		_anim_time = 0.0
		_idle_time += delta
	else:
		_idle_time = 0.0
		_anim_time += delta
		if absf(dir.x) > absf(dir.y):
			facing = Facing.RIGHT if dir.x > 0 else Facing.LEFT
		else:
			facing = Facing.DOWN if dir.y > 0 else Facing.UP
	if sprite.texture != NAKED_TEX:
		sprite.texture = NAKED_TEX
	var anim := ANIM_IDLE if dir == Vector2.ZERO else ANIM_RUN
	var t := _idle_time if dir == Vector2.ZERO else _anim_time
	var col := int(t * (IDLE_FPS if dir == Vector2.ZERO else walk_fps * 1.15)) % 4
	sprite.frame = (anim * 4 + facing) * sprite.hframes + col
	_idle_mat.set_shader_parameter("bob", 0.0)   # the new body has real idle frames


## Adds key bindings if they aren't already defined in
## Project Settings > Input Map. Define them there to override.
static func _ensure_input_actions() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"debug_damage": [KEY_F1],
		"debug_spend_mana": [KEY_F2],
		"debug_coins": [KEY_F3],
		"debug_sword": [KEY_F4],
		"paperdoll": [KEY_P],
		"stats": [KEY_C],
		"inventory": [KEY_B],
		"spellbook": [KEY_K],
		"interact": [KEY_F],
		"home_teleport": [KEY_H],
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	Keybinds.apply()   # hotbar / window keys, with the player's saved rebinds
	if not InputMap.has_action("cast"):
		InputMap.add_action("cast")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("cast", click)


## Bumping into a corner or the edge of an obstacle slides you around it instead of
## stopping dead (Hearthlight's "corner nudge"): if the way ahead is blocked but a few
## pixels to the side is free, drift sideways toward the free side while still moving.
const NUDGE_REACH := 7.0       ## how far to the side we look for a gap (px)
const NUDGE_SPEED := 0.75      ## sideways drift, as a share of move speed

func _corner_nudge(dir: Vector2, move_speed: float, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	var step := dir * move_speed * delta
	for axis in 2:
		var comp := step[axis]
		if absf(comp) < 0.01 or (axis == 0 and absf(dir.x) < 0.3) or (axis == 1 and absf(dir.y) < 0.3):
			continue
		var motion := Vector2.ZERO
		motion[axis] = comp * 2.0
		if not test_move(global_transform, motion):
			continue
		var perp := Vector2(0, 1) if axis == 0 else Vector2(1, 0)
		var other := dir[1 - axis]
		if absf(other) > 0.3:
			continue                         # already sliding along the wall: leave it to the physics
		for off in range(1, int(NUDGE_REACH) + 1):
			for sgn in [1.0, -1.0]:
				var t: Transform2D = global_transform.translated(perp * sgn * float(off))
				if not test_move(t, motion):
					var drift: Vector2 = perp * sgn * move_speed * NUDGE_SPEED * delta
					var cap := float(off)
					global_position += drift.limit_length(cap)
					return
