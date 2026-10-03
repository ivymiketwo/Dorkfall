class_name Fishing
extends Node2D
## Fishing. Equip a fishing rod (weapon slot), then left-click to cast.
##  - Aim at land: the line flies out, lands, and resets straight away.
##  - Aim at water: the bobber splashes down. After a random 1-4 seconds it sinks with a flash
##    and a bar minigame starts (see FishingBar): keep your marker (A / D) inside the
##    wiggling catch zone until the meter fills and the fish goes into your bag. Let the
##    meter run dry and it gets away.
## Left-click while the bobber is floating to reel it in. Lives as a child of the player.

enum S { IDLE, FLYING, WAIT, BITE, MINI }

const MAX_CAST := 120.0          ## world px
const MIN_CAST := 22.0
const BITE_MIN := 1.0
const BITE_MAX := 4.0
const SNAP_AWAY := 190.0         ## walk this far from the bobber and the line comes in
const WATER_TILE := Vector2i(3, 0)
const LINE_COL := Color(0.93, 0.95, 1.0, 0.85)
const ROD_COLS := [Color("c49650"), Color("96aabe"), Color("ffc83c")]
const ROD_DARK := Color("3a2410")
const OUTLINE := Color(0.13, 0.09, 0.05, 1.0)
const FISH_PATHS := ["res://items/minnow.tres", "res://items/perch.tres", "res://items/bass.tres", "res://items/golden_carp.tres"]
## Chance weights (minnow, perch, bass, golden carp) per rod power.
const POOLS := {1: [60, 30, 9, 1], 2: [25, 40, 30, 5], 3: [5, 25, 50, 20]}
const PX := 0.5                  ## one art pixel in world units

var state := S.IDLE
var _t := 0.0
var _fly_time := 0.3
var _dir := Vector2.DOWN
var _tip_start := Vector2.ZERO
var _land := Vector2.ZERO
var _water := false
var _bite_at := 4.0
var _splash := -1.0              ## seconds since the bobber hit the water
var _flash := -1.0               ## seconds since the bite flash started
var _dust := -1.0
var _rod: Item
var _fish: Item
var _bar: FishingBar

@onready var caster: CharacterBody2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")
@onready var equipment: Equipment = get_parent().get_node("Equipment")
@onready var inventory: Inventory = get_parent().get_node("Inventory")


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 4
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_bar = FishingBar.new()
	_bar.finished.connect(_on_minigame_done)
	layer.add_child(_bar)
	_bar.hide()
	stats.damaged.connect(func(_a: float) -> void: cancel())
	stats.died.connect(cancel)


func _rod_item() -> Item:
	var w := equipment.get_item("weapon")
	return w if w != null and w.fishing_rod else null


## Where the line leaves the rod: the tip of the rod held in the character's hand.
func _rod_tip() -> Vector2:
	for n in get_tree().get_nodes_in_group("held_weapon"):
		var w := n as HeldWeapon
		if w != null and w.player == caster and w.visible:
			return w.orb_global()
	return _hand() + _dir * 12.0 + Vector2(0, -6)


func _hand() -> Vector2:
	return caster.global_position + Vector2(5.0 if _dir.x >= 0.0 else -5.0, -9.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if _rod_item() == null:
		return
	var melee := caster.get_node_or_null("Melee")
	if melee != null and melee.has_method("_ui_blocking") and melee._ui_blocking():
		return
	if stats.health <= 0.0:
		return
	get_viewport().set_input_as_handled()
	match state:
		S.IDLE:
			_cast()
		S.WAIT:
			cancel()          # reel the bobber back in


func cancel() -> void:
	if state == S.IDLE:
		return
	state = S.IDLE
	caster.control_locked = false
	_bar.stop()
	_splash = -1.0
	_flash = -1.0
	queue_redraw()


func _cast() -> void:
	_rod = _rod_item()
	var from := caster.global_position + Vector2(0, -9)
	var aim: Vector2 = caster.aim_world - from
	_dir = aim.normalized() if aim.length() > 1.0 else Vector2.DOWN
	_tip_start = _rod_tip()
	_land = from + _dir * clampf(aim.length(), MIN_CAST, MAX_CAST)
	_water = _is_water(_land)
	_fly_time = 0.3 + _land.distance_to(from) / 420.0
	_t = 0.0
	_splash = -1.0
	_flash = -1.0
	_dust = -1.0
	if "facing" in caster:     # turn to face the cast (0 down, 1 up, 2 left, 3 right)
		caster.facing = (3 if _dir.x > 0 else 2) if absf(_dir.x) > absf(_dir.y) else (0 if _dir.y > 0 else 1)
	state = S.FLYING


func _is_water(p: Vector2) -> bool:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	var ground := world.get("ground") as TileMapLayer
	if ground == null:
		return false
	var cell := ground.local_to_map(ground.to_local(p))
	return ground.get_cell_atlas_coords(cell) == WATER_TILE


func _process(delta: float) -> void:
	if state == S.IDLE and _splash < 0.0 and _dust < 0.0:
		return
	if _splash >= 0.0:
		_splash += delta
		if _splash > 1.0 and state == S.IDLE:
			_splash = -1.0
	if _flash >= 0.0:
		_flash += delta
		if _flash > 0.6:
			_flash = -1.0
	if _dust >= 0.0:
		_dust += delta
		if _dust > 0.4:
			_dust = -1.0
	if state != S.IDLE:
		_t += delta
		if _rod_item() == null or not caster.is_physics_processing() \
				or (state == S.WAIT and caster.global_position.distance_to(_land) > SNAP_AWAY):
			cancel()
			return
		match state:
			S.FLYING:
				if _t >= _fly_time:
					_landed()
			S.WAIT:
				if _t >= _bite_at:
					_bite()
			S.BITE:
				if _t >= 0.55:
					_start_minigame()
	queue_redraw()


func _landed() -> void:
	_t = 0.0
	if _water:
		_splash = 0.0
		_bite_at = randf_range(BITE_MIN, BITE_MAX)
		state = S.WAIT
	else:
		_dust = 0.0            # dry land: a puff of dust and the line resets at once
		state = S.IDLE


func _bite() -> void:
	_t = 0.0
	_flash = 0.0
	state = S.BITE
	_fish = _roll_fish(_rod.fishing_power if _rod else 1)
	FloatingText.spawn(caster.get_parent(), _land + Vector2(0, -8), "!", Color("fff08a"), 1.0)


func _roll_fish(power: int) -> Item:
	var w: Array = POOLS.get(clampi(power, 1, 3), POOLS[1])
	var total := 0
	for x: int in w:
		total += x
	var r := randi() % total
	var idx := 0
	for i in w.size():
		r -= int(w[i])
		if r < 0:
			idx = i
			break
	return load(FISH_PATHS[idx]) as Item


func _start_minigame() -> void:
	state = S.MINI
	caster.control_locked = true
	_bar.start(_rod.fishing_power if _rod else 1, _fish.icon_frame if _fish else 25)


func _on_minigame_done(success: bool) -> void:
	caster.control_locked = false
	state = S.IDLE
	_splash = 0.4
	var above: Vector2 = caster.global_position + Vector2(0, -28)
	if success and _fish != null:
		if inventory.add(_fish, 1) > 0:
			FloatingText.spawn(caster.get_parent(), above, "BAG FULL", Color("ff6b5a"))
		else:
			FloatingText.spawn(caster.get_parent(), above, "CAUGHT %s!" % _fish.display_name.to_upper(), Color("9be87a"))
	else:
		FloatingText.spawn(caster.get_parent(), above, "IT GOT AWAY...", Color("ff9a8a"))
	queue_redraw()


# ---- drawing (everything is chunky art pixels: PX world units) ----------------

func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.snapped(Vector2(PX, PX)), Vector2(PX, PX)), c)


func _px_line(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)) / PX) + 1
	for i in n + 1:
		_px(a.lerp(b, float(i) / float(maxi(n, 1))), c)


func _bobber_pos() -> Vector2:
	match state:
		S.FLYING:
			var f := clampf(_t / _fly_time, 0.0, 1.0)
			return _rod_tip().lerp(_land, f) - Vector2(0, sin(f * PI) * 18.0)
		S.WAIT:
			return _land + Vector2(0, snappedf(sin(_t * 3.0) * 0.5, PX))
		S.BITE, S.MINI:
			return _land + Vector2(randf_range(-0.5, 0.5) if state == S.BITE else 0.0, 1.5)
	return _land


func _draw() -> void:
	if _dust >= 0.0 and state == S.IDLE:
		var a := 1.0 - _dust / 0.4
		for i in 5:
			var ang := TAU * float(i) / 5.0 + 0.4
			_px(_land + Vector2.from_angle(ang) * (1.0 + _dust * 12.0) + Vector2(0, -_dust * 3.0), Color(0.85, 0.78, 0.6, a))
	if _splash >= 0.0:
		_draw_splash()
	if state == S.IDLE:
		return
	var tip := _rod_tip()      # the rod itself is the held item (HeldWeapon)
	# the line and bobber
	var b := _bobber_pos()
	var sag := 7.0 if state == S.WAIT else (3.0 if state == S.FLYING else 1.5)
	var ctrl := (tip + b) * 0.5 + Vector2(0, sag)
	var n := 18
	for i in n + 1:
		var f := float(i) / float(n)
		var p := tip.lerp(ctrl, f).lerp(ctrl.lerp(b, f), f)
		_px(p, LINE_COL)
	_draw_bobber(b)
	if _flash >= 0.0:
		var f := _flash / 0.6
		draw_circle(b, 3.0 + f * 8.0, Color(1, 1, 0.8, (1.0 - f) * 0.7))
		draw_arc(b, 2.0 + f * 12.0, 0.0, TAU, 24, Color(1, 1, 1, 1.0 - f), 0.5)


func _draw_bobber(p: Vector2) -> void:
	for dx in range(-2, 3):
		for dy in range(-3, 3):
			var edge := dx == -2 or dx == 2 or dy == -3 or dy == 2
			var corner := (dx == -2 or dx == 2) and (dy == -3 or dy == 2)
			if corner:
				continue
			var c := OUTLINE if edge else (Color("e8453c") if dy < 0 else Color("f4f4f4"))
			_px(p + Vector2(dx, dy) * PX, c)
	_px(p + Vector2(0, -4) * PX, OUTLINE)


func _draw_splash() -> void:
	var c := _land + Vector2(0, 1.0)
	for k in 2:
		var t := _splash - float(k) * 0.18
		if t < 0.0 or t > 0.7:
			continue
		var f := t / 0.7
		var r := 1.5 + f * 8.0
		var a := (1.0 - f) * 0.9
		for i in 20:
			var ang := TAU * float(i) / 20.0
			_px(c + Vector2(cos(ang) * r, sin(ang) * r * 0.45), Color(0.85, 0.95, 1.0, a))
	if _splash < 0.5:                                   # droplets thrown up and out
		for i in 7:
			var ang := TAU * float(i) / 7.0 + 0.3
			var v := Vector2(cos(ang) * 9.0, -16.0 - 6.0 * sin(float(i) * 2.1))
			var p := c + v * _splash + Vector2(0, 40.0 * _splash * _splash)
			_px(p, Color(0.9, 0.97, 1.0, 1.0 - _splash * 1.6))
	if state == S.WAIT:                                 # lazy ripple while waiting
		var f := fmod(_t, 1.4) / 1.4
		for i in 16:
			var ang := TAU * float(i) / 16.0
			_px(c + Vector2(cos(ang) * (2.0 + f * 5.0), sin(ang) * (2.0 + f * 5.0) * 0.45), Color(0.85, 0.95, 1.0, 0.45 * (1.0 - f)))


## The catch bar: a track with your marker (A / D) and a larger, see-through zone that wiggles
## about. Stay inside it and the meter fills; stay outside and it drains.
class FishingBar extends Control:
	signal finished(success: bool)

	const ICONS := preload("res://art/items.png")
	const BAR_W := 240.0
	const BAR_H := 22.0

	var active := false
	var _p := 0.5               ## your marker, 0..1 along the track
	var _pv := 0.0
	var _c := 0.5               ## centre of the catch zone
	var _cv := 0.0
	var _cv_target := 0.0
	var _retarget := 0.0
	var _zone := 0.3            ## zone width as a fraction of the track
	var _speed := 0.4
	var _progress := 0.3
	var _gain := 0.3
	var _drain := 0.24
	var _icon := 25
	var _time := 0.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	func start(power: int, icon_frame: int) -> void:
		power = clampi(power, 1, 3)
		_zone = [0.26, 0.32, 0.38][power - 1]
		_speed = [0.5, 0.42, 0.34][power - 1]
		_gain = [0.30, 0.32, 0.34][power - 1]
		_drain = [0.26, 0.23, 0.20][power - 1]
		_icon = icon_frame
		_p = 0.5
		_pv = 0.0
		_c = randf_range(0.3, 0.7)
		_cv = 0.0
		_cv_target = 0.0
		_retarget = 0.0
		_progress = 0.3
		_time = 0.0
		active = true
		show()

	func stop() -> void:
		active = false
		hide()

	func _process(delta: float) -> void:
		if not active:
			return
		_time += delta
		var axis := 0.0
		if not ChatLog.typing:
			axis = Input.get_axis("move_left", "move_right")
		_pv = move_toward(_pv, axis * 0.85, 4.5 * delta)       # a little momentum
		_p += _pv * delta
		if _p < 0.0 or _p > 1.0:
			_p = clampf(_p, 0.0, 1.0)
			_pv = 0.0
		_retarget -= delta
		if _retarget <= 0.0:
			_cv_target = randf_range(-1.0, 1.0) * _speed
			_retarget = randf_range(0.35, 1.0)
		_cv = lerpf(_cv, _cv_target, minf(delta * 5.0, 1.0))
		_c += _cv * delta
		var half := _zone * 0.5
		if _c < half:
			_c = half
			_cv = absf(_cv)
			_cv_target = absf(_cv_target)
		elif _c > 1.0 - half:
			_c = 1.0 - half
			_cv = -absf(_cv)
			_cv_target = -absf(_cv_target)
		if absf(_p - _c) <= half:
			_progress += _gain * delta
		else:
			_progress -= _drain * delta
		if _progress >= 1.0 or _progress <= 0.0:
			active = false
			hide()
			finished.emit(_progress >= 1.0)
			return
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var cx := size.x * 0.5
		var x0 := cx - BAR_W * 0.5
		var y0 := size.y - 78.0
		# panel
		draw_rect(Rect2(x0 - 8, y0 - 22, BAR_W + 16, BAR_H + 48), Color(0.05, 0.04, 0.08, 0.92))
		draw_rect(Rect2(x0 - 8, y0 - 22, BAR_W + 16, BAR_H + 48), Color(0.72, 0.58, 0.32), false, 1.0)
		var title := "A / D  KEEP THE BAR ON THE FISH"
		HiFont.draw(self, Vector2(cx - floorf(HiFont.text_width(title, 1.0) / 2.0), y0 - 16.0), title, Color("ffe9a8"), 1.0)
		# track
		draw_rect(Rect2(x0, y0, BAR_W, BAR_H), Color(0.12, 0.2, 0.3))
		draw_rect(Rect2(x0, y0, BAR_W, BAR_H), Color(0.3, 0.45, 0.6), false, 1.0)
		# the wiggling catch zone (see-through, so your marker shows through it)
		var zx := x0 + (_c - _zone * 0.5) * BAR_W
		var zw := _zone * BAR_W
		var inside := absf(_p - _c) <= _zone * 0.5
		var zc := Color(0.35, 0.95, 0.55, 0.42) if inside else Color(0.95, 0.85, 0.35, 0.34)
		draw_rect(Rect2(zx, y0, zw, BAR_H), zc)
		draw_rect(Rect2(zx, y0, zw, BAR_H), Color(zc.r, zc.g, zc.b, 0.9), false, 1.0)
		draw_texture_rect_region(ICONS, Rect2(zx + zw * 0.5 - 13.0, y0 + BAR_H * 0.5 - 13.0 + sin(_time * 9.0) * 1.0, 26, 26), Rect2(_icon * 32, 0, 32, 32))
		# your marker
		var mx := x0 + _p * BAR_W
		draw_rect(Rect2(mx - 3, y0 - 4, 6, BAR_H + 8), Color(0.1, 0.07, 0.04))
		draw_rect(Rect2(mx - 2, y0 - 3, 4, BAR_H + 6), Color(1.0, 0.97, 0.75) if not inside else Color(0.8, 1.0, 0.8))
		# catch meter
		var my := y0 + BAR_H + 8.0
		draw_rect(Rect2(x0, my, BAR_W, 6), Color(0.1, 0.08, 0.12))
		draw_rect(Rect2(x0 + 1, my + 1, (BAR_W - 2.0) * clampf(_progress, 0.0, 1.0), 4), Color(0.95, 0.4, 0.3).lerp(Color(0.5, 0.95, 0.4), _progress))
		draw_rect(Rect2(x0, my, BAR_W, 6), Color(0.6, 0.5, 0.3), false, 1.0)
