extends CharacterBody2D
## Top-down player: 8-direction movement, 4-direction facing, 2-frame walk cycle,
## and health/mana via the Stats child. Space jumps; speed carried in from spells (and kept by
## jumping again the moment you land) is the fast way about. No sprint.

@export var display_name := "Rex"
@export var speed := 70.0              ## pixels per second
@export var walk_fps := 7.0            ## walk animation speed (4 steps per cycle)

@export_group("Momentum")
## How quickly you get up to walking speed and stop again when just walking (px/s²; high = snappy).
@export var walk_accel := 1400.0
## When you're going faster than walking (e.g. after a yank), the ground brakes you, harder the
## longer you stay on it: `friction_start` (px/s²) the moment you land, climbing to `friction_max`
## after `friction_ramp` seconds. So jumping again right as you land keeps nearly all your speed,
## and every moment you wait eats more of it.
@export var friction_start := 60.0
@export var friction_max := 1500.0
@export var friction_ramp := 0.35
## Holding the opposite way while sliding brakes this many times harder.
@export var brake_mult := 2.5
## The fastest you can ever go (px/s).
@export var max_speed := 700.0

@export_group("Jump")
## Seconds in the air, and how high the jump goes (world px).
@export var jump_time := 0.45
@export var jump_height := 12.0
## Space pressed this long (seconds) before you land still jumps the moment you touch down.
@export var jump_buffer := 0.1

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
const NAKED_TEX := preload("res://art/player_new.png")   # chest gear can swap in its own body_sheet

@onready var sprite: Sprite2D = $Sprite2D
@onready var stats: Stats = $Stats
@onready var inventory: Inventory = $Inventory

const COINS := preload("res://items/coins.tres")
const TEST_GEAR := [preload("res://items/wooden_staff.tres"), preload("res://items/vordy_staff.tres"),
		preload("res://items/amethyst_staff.tres"),
		preload("res://items/amber_staff.tres"),
		preload("res://items/sun_staff.tres"),
		preload("res://items/void_staff.tres"),
		preload("res://items/astral_staff.tres"),
		preload("res://items/clockwork_staff.tres"),
		preload("res://items/twilight_staff.tres"),
		preload("res://items/linecaster_staff.tres"),
		preload("res://items/wizard_hat.tres"), preload("res://items/wizard_robe.tres")]

## What the player is asking for right now. Only `_gather_input` reads the keyboard and mouse;
## everything else (movement, casting, jumping) uses these values, so a server can
## be fed the same data over the network.
var input_dir := Vector2.ZERO
## Set by minigames (fishing) so the keys don't walk the character.
var control_locked := false
## GameClock time until which the player is rooted by a spell they are casting (can't walk,
## jump or ward), e.g. the Sun Staff's halo beam (sun_halo.gd).
var rooted_until := 0.0
var input_ward := false            ## right mouse (pressed in the world): hold the Ward up
var aim_world := Vector2.ZERO      ## where in the world the player is aiming
## Left / right mouse held down, counting only presses that started in the world (not on a
## menu, the bag or the hotbar): holding left keeps firing the beam, right holds the Ward.
var input_fire_held := false
var _rmb_world := false

var facing := Facing.DOWN
var _anim_time := 0.0
var _idle_mat: ShaderMaterial
var _idle_time := 0.0
const IDLE_BOB_PERIOD := 0.6   ## seconds per up/down step while standing still
var _spawn_point: Vector2

# Jump (Space): a plain leap, no cost and no cooldown. In the air you keep going exactly the way
# you took off (no steering); landing starts the ground's friction ramp (see "Momentum").
const JUMP_SOUND := preload("res://audio/jump.wav")
var _jump_snd: AudioStreamPlayer2D
var _air_t := -1.0             ## seconds into the current jump (-1 = on the ground)
var _air_vel := Vector2.ZERO   ## velocity through the air on the current jump
var _jump_buffer := 0.0        ## Space pressed just before landing still counts
var _ground_t := 10.0          ## seconds on the ground since the last landing

# Being yanked along (e.g. the Yank Line spell, line_yank.gd): pulled straight at a point.
var yanking := false
var _yank_to := Vector2.ZERO
var _yank_speed := 0.0
var _yank_left := 0.0
var _yank_keep := 1.0

# Movement history for server corrections (client-side prediction). Every physics tick that
# moves the body is numbered and remembered: the velocity used and where it ended up.
# A server will answer "after tick N you were at P"; `reconcile` then puts the body at P and
# replays the ticks after N, so the player never sees a jump unless they really were off.
const MOVE_HISTORY := 120          ## ticks kept (2 seconds at 60 ticks/s)
var move_seq := 0                  ## number of the last movement tick
var _moves: Array[Dictionary] = [] ## [{seq, vel, pos}]


@onready var _cam: Camera2D = get_node_or_null("Camera2D")
var _tick := TickTracker.new()


func _ready() -> void:
	_tick.body = self
	add_child(_tick)
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
	input_ward = _rmb_world
	if ChatLog.typing:          # typing a message: the keys are for the chat
		input_dir = Vector2.ZERO
		input_ward = false
	if control_locked or is_rooted():
		input_dir = Vector2.ZERO
		input_ward = false
	aim_world = get_global_mouse_position()


func _process(_delta: float) -> void:
	_gather_input()
	_place_camera()


## The camera sits on the player's smoothed (interpolated) position, rounded to whole WINDOW
## pixels (the world is drawn at the window's resolution, see world.gd), so the ground is always
## pixel-exact (no shimmer). Sprites
## are kept on screen pixels by snap_2d_vertices_to_pixel (scenes/game.tscn). See
## docs/desert_texture.md, "Keep everything on the pixel grid".
func _place_camera() -> void:
	if _cam == null:
		return
	if _tick.now != global_position:          # teleported since the last tick: jump straight there
		_tick.prev = global_position
		_tick.now = global_position
	var at: Vector2 = _tick.prev.lerp(_tick.now, Engine.get_physics_interpolation_fraction())
	var px := _cam.zoom.x * get_tree().root.get_final_transform().get_scale().x   # window px per world px
	_cam.global_position = (at * px).round() / px
	_cam.force_update_scroll()          # use it this frame, not next


## Where the player is DRAWN this frame minus where its body really is (the drawing is smoothed
## between game ticks). Effects tied to the player add this so they stay glued on at speed.
func drawn_offset() -> Vector2:
	return _tick.prev.lerp(_tick.now, Engine.get_physics_interpolation_fraction()) - global_position


## Remembers where the player was at the end of the last two physics ticks (it runs after the
## player's own tick), which is exactly what the drawn player is smoothed between.
class TickTracker extends Node:
	var body: Node2D
	var prev := Vector2.ZERO
	var now := Vector2.ZERO

	func _ready() -> void:
		process_physics_priority = 1000
		prev = body.global_position
		now = prev

	func _physics_process(_delta: float) -> void:
		prev = now
		now = body.global_position


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		aim_world = get_global_mouse_position()
	# Holding the button only counts if the press started in the world, not on a menu,
	# the bag or the hotbar (those mark their clicks handled before this runs, or sit under the mouse).
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var in_world: bool = event.pressed and get_viewport().gui_get_hovered_control() == null
		if event.button_index == MOUSE_BUTTON_LEFT:
			input_fire_held = in_world
		else:
			_rmb_world = in_world


func _physics_process(delta: float) -> void:
	_gather_input()
	if yanking:
		_yank_step(delta)
		return
	if _air_t >= 0.0:
		_air_step(delta)
		return
	_ground_t += delta
	var dir: Vector2 = input_dir
	var move_speed := speed
	if is_warding():
		move_speed *= Ward.SPEED_MULT   # ward up: slow going
	var v := velocity
	if v.length() > move_speed + 1.0:
		# Sliding on speed you carried in: it keeps going the same way and the ground bleeds the
		# extra off, gently just after landing and harder the longer you stay down. The keys
		# can't steer it, only brake it by holding the other way.
		var fric := lerpf(friction_start, friction_max, clampf(_ground_t / maxf(friction_ramp, 0.001), 0.0, 1.0))
		fric *= brake_mult if dir.dot(v.normalized()) < -0.5 else 1.0
		velocity = v.normalized() * maxf(v.length() - fric * delta, move_speed)
	else:
		velocity = v.move_toward(dir * move_speed, walk_accel * delta)
		_corner_nudge(dir, move_speed, delta)
	_move_tick()
	_update_animation(dir, delta)


## Moves the body one tick with the current velocity and remembers it (see MOVE_HISTORY).
func _move_tick() -> void:
	var v := velocity
	move_and_slide()
	velocity = get_real_velocity()         # walls soak up the part of the speed that hits them
	move_seq += 1
	_moves.append({"seq": move_seq, "vel": v, "pos": global_position})
	if _moves.size() > MOVE_HISTORY:
		_moves.pop_front()


## Server correction: "after movement tick `seq` you were at `server_pos`". If we agree
## (within half a pixel) nothing happens; otherwise the body goes to `server_pos` and the
## ticks after `seq` are replayed with the same velocities. Returns how far off we were.
func reconcile(seq: int, server_pos: Vector2) -> float:
	var i := -1
	for k in _moves.size():
		if _moves[k]["seq"] == seq:
			i = k
			break
	if i == -1:
		return 0.0                     # too old (or not ours): nothing to correct against
	var off: float = _moves[i]["pos"].distance_to(server_pos)
	_moves = _moves.slice(i)           # the server has confirmed everything up to here
	if off < 0.5:
		return off
	var keep := velocity
	global_position = server_pos
	_moves[0]["pos"] = server_pos
	for k in range(1, _moves.size()):
		velocity = _moves[k]["vel"]
		move_and_slide()
		_moves[k]["pos"] = global_position
	velocity = keep
	return off


func _unhandled_input(event: InputEvent) -> void:
	if (control_locked or is_rooted()) and event.is_action_pressed("jump"):
		return
	if event.is_action_pressed("jump"):
		if yanking:
			_end_yank(1.0)                 # jump straight out of a yank, keeping all its speed
			_jump()
		elif _air_t >= 0.0:
			_jump_buffer = jump_buffer     # a touch early: jumps again the moment you land
		elif not is_warding():
			_jump()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_damage"):
		stats.take_damage(debug_damage)
	elif event.is_action_pressed("debug_spend_mana"):
		stats.spend_mana(debug_mana_cost)
	elif event.is_action_pressed("debug_coins"):
		inventory.add(COINS, 100)
	elif event.is_action_pressed("debug_gear"):
		for g: Item in TEST_GEAR:
			inventory.add(g, 1)
	elif event.is_action_pressed("interact"):
		_interact()


## True while the Ward (right click) is up.
func is_rooted() -> bool:
	return not GameClock.passed(rooted_until)


func is_warding() -> bool:
	var w := get_node_or_null("Ward") as Ward
	return w != null and w.warding


## Leaves the ground. You keep the part of your speed that points where you're going (the keys
## you hold, or straight on if none), and at least walking speed if you're moving: momentum only
## goes one way, so turning loses it. No keys and standing still: a jump on the spot.
func _jump() -> void:
	var dir := input_dir.normalized() if input_dir != Vector2.ZERO \
			else (velocity.normalized() if velocity.length() > 1.0 else Vector2.ZERO)
	var spd := maxf(velocity.dot(dir), speed if input_dir != Vector2.ZERO else 0.0)
	_air_vel = dir * minf(spd, max_speed)
	_air_t = 0.0
	_jump_buffer = 0.0
	if dir != Vector2.ZERO:
		facing = (Facing.RIGHT if dir.x > 0 else Facing.LEFT) if absf(dir.x) > absf(dir.y) \
				else (Facing.DOWN if dir.y > 0 else Facing.UP)
	if _jump_snd == null:
		_jump_snd = AudioStreamPlayer2D.new()
		_jump_snd.stream = JUMP_SOUND
		_jump_snd.volume_db = -6.0   # half amplitude
		add_child(_jump_snd)
	_jump_snd.play()


func _air_step(delta: float) -> void:
	_idle_time = 0.0
	_idle_mat.set_shader_parameter("bob", 0.0)
	_air_t += delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	var k := clampf(_air_t / maxf(jump_time, 0.01), 0.0, 1.0)
	_set_jump_frame(k)
	sprite.position.y = -4.0 * jump_height * k * (1.0 - k)      # parabola, apex at k = 0.5
	velocity = _air_vel
	_move_tick()
	_air_vel = velocity                # (minus whatever a wall soaked up)
	if k >= 1.0:
		_land()


func _land() -> void:
	sprite.position.y = 0.0
	_air_t = -1.0
	velocity = _air_vel                # land still moving: the ground starts slowing you
	_ground_t = 0.0
	if _jump_buffer > 0.0:
		_jump()


## The chest item, if it comes with its own body sheet (robe, chestplate...).
func _body_item() -> Item:
	var eq := get_node_or_null("Equipment") as Equipment
	var it: Item = eq.get_item("chest") if eq else null
	return it if it != null and it.body_sheet != null else null


func _use_body_texture() -> void:
	var it := _body_item()
	var tex: Texture2D = it.body_sheet if it else NAKED_TEX
	if sprite.texture != tex:
		sprite.texture = tex


func _set_jump_frame(k: float) -> void:
	var it := _body_item()
	_use_body_texture()
	var n: int = it.body_jump_frames[facing] if it and it.body_jump_frames.size() == 4 else 9
	sprite.frame = (ANIM_JUMP * 4 + facing) * sprite.hframes + mini(int(k * n), n - 1)


## Pulls the player straight at `point` at `spd` px/s (a spell's rope, see line_yank.gd). It
## stops on arrival, against a wall, or after `max_time`; you then keep `keep` of the speed
## and slide (or jump on). Space during the pull jumps out of it at full speed.
func yank_to(point: Vector2, spd: float, max_time: float, keep: float) -> void:
	if _air_t >= 0.0:
		_air_t = -1.0                      # a yank takes you out of the air
		sprite.position.y = 0.0
	yanking = true
	_yank_to = point
	_yank_speed = minf(spd, max_speed)
	_yank_left = max_time
	_yank_keep = keep


func _yank_step(delta: float) -> void:
	_yank_left -= delta
	var to := _yank_to - global_position
	var dir := to.normalized() if to.length() > 0.01 else Vector2.ZERO
	var step := _yank_speed * delta
	facing = (Facing.RIGHT if dir.x > 0 else Facing.LEFT) if absf(dir.x) > absf(dir.y) \
			else (Facing.DOWN if dir.y > 0 else Facing.UP)
	_use_body_texture()                    # the running pose, staff held out (the line stays tied to its orb)
	sprite.frame = (ANIM_RUN * 4 + facing) * sprite.hframes + 1
	sprite.position.y = -2.0
	var before := global_position
	velocity = dir * minf(_yank_speed, to.length() / delta)
	_move_tick()
	var moved := global_position.distance_to(before)
	if to.length() <= step + 0.5 or moved < step * 0.3 or _yank_left <= 0.0:
		velocity = dir * _yank_speed
		_end_yank(_yank_keep)


func _end_yank(keep: float) -> void:
	if not yanking:
		return
	yanking = false
	sprite.position.y = 0.0
	velocity *= keep
	_ground_t = 0.0                        # like landing: a quick jump keeps the speed


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
	_end_yank(0.0)
	_air_t = -1.0
	_jump_buffer = 0.0
	sprite.position.y = 0.0
	velocity = Vector2.ZERO
	_leave_gravestone()
	# Respawn at the start with full stats.
	position = _spawn_point
	reset_physics_interpolation()   # appear there at once, no slide
	stats.refill()
	# pets come along to the respawn point
	var n := 0
	for pet in get_tree().get_nodes_in_group("pets"):
		if pet is Pet:
			pet.call_deferred("join_player", self, n)
			n += 1


## Everything carried and worn goes onto a gravestone where you fell.
func _leave_gravestone() -> void:
	SaveGame.batch(_fill_gravestone)   # bag, gear and stone are saved together


func _fill_gravestone() -> void:
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


## Snap to the standing pose (first idle frame, current facing). Used when something
## freezes the player (door / teleport fade) so they don't stop on a mid-stride frame.
func show_idle() -> void:
	_anim_time = 0.0
	_idle_time = 0.0
	_use_body_texture()
	sprite.frame = (ANIM_IDLE * 4 + facing) * sprite.hframes
	_idle_mat.set_shader_parameter("bob", 0.0)


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
	_use_body_texture()
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
		"jump": [KEY_SPACE],
		"debug_damage": [KEY_F1],
		"debug_spend_mana": [KEY_F2],
		"debug_coins": [KEY_F3],
		"debug_gear": [KEY_F4],
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
