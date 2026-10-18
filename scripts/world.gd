extends Node2D
## Builds a starter map on the Ground layer and clamps the camera to it.
## If you paint your own tiles on Ground in the editor, generation is skipped.

const MAP_ORIGIN := Vector2i(-105, -62)   # top-left tile (the village starts at 0, 0)
const MAP_SIZE := Vector2i(512, 168)      # in tiles (x -1680..6512, y -992..1696 in world px)
# West ocean: for each tile row (from the top), the first land tile counted from the left edge.
# Everything between the wall and that tile is sea (impassable). Matches art/water_info_ocean.png.
var OCEAN_SHORE := PackedInt32Array([35, 35, 36, 36, 36, 37, 36, 36, 36, 36, 35, 35, 35, 35, 35, 35, 35, 34, 33, 33, 32, 32, 32, 31, 31, 31, 30, 30, 30, 30, 30, 30, 31, 31, 31, 31, 32, 33, 34, 34, 34, 34, 34, 35, 36, 36, 37, 38, 38, 38, 38, 37, 37, 37, 36, 35, 35, 34, 34, 33, 33, 33, 33, 33, 32, 32, 31, 31, 32, 32, 33, 33, 33, 34, 34, 35, 35, 36, 36, 36, 36, 36, 37, 37, 37, 37, 37, 37, 36, 36, 36, 36, 35, 35, 35, 34, 34, 34, 34, 33, 33, 33, 33, 33, 34, 34, 35, 36, 37, 37, 37, 37, 37, 37, 38, 38, 38, 38, 38, 39, 39, 39, 39, 39, 39, 39, 39, 39, 39, 39, 38, 38, 37, 37, 36, 36, 36, 36, 36, 36, 36, 36, 35, 35, 35, 35, 35, 35, 36, 36, 37, 38, 38, 38, 37, 38, 38, 39, 39, 40, 40, 40, 40, 40, 39, 38, 37, 37])

# Atlas coordinates in art/tiles.png
const GRASS := Vector2i(0, 0)
const GRASS_FLOWERS := Vector2i(1, 0)
const PATH := Vector2i(2, 0)
const WATER := Vector2i(3, 0)   # has collision
const WALL := Vector2i(4, 0)    # has collision
const DOCK_WEST := -76          # westmost tile column of the dock (art/dock.png)
## East mountains and ravine: wall tiles made by tools/gen_ravine.py ('#' = wall).
const MOUNTAINS := "res://data/mountains.json"
var _mountains := {}

@onready var ground: TileMapLayer = $Ground
@onready var camera: Camera2D = $Entities/Player/Camera2D
@onready var player: CharacterBody2D = $Entities/Player

const ARRIVAL_LOCK := 0.1   # seconds the player can't move after going through a door

## Mouse-wheel zoom, up to 25% closer or further (ZOOMS: 1.0 = normal). At normal zoom nothing
## changes: the world draws on its 640x360 screen, blown up to the window. Zoomed, that screen is
## drawn at the window's full resolution instead (same 640x360 layout, so the interface and the
## mouse work exactly the same) and the camera zooms, so no art pixel is ever dropped; at
## in-between sizes some art pixels just come out one window pixel wider than others.
const ZOOMS := [0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25]
const ZOOM_NORMAL := 4
const BASE_ZOOM := 2.0
var _zoom_i := ZOOM_NORMAL

var _outside_limits := Rect2i()
var _inside: Node2D = null       # the interior the player is in, if any
var _return_pos := Vector2.ZERO  # where to put the player back outside
var _busy := false               # true during a fade
var _fade := ColorRect.new()


func _ready() -> void:
	if ground.get_used_cells().is_empty():
		_generate_map()
	ground.self_modulate = Color(1, 1, 1, 0)   # the tiles are only for collision; GroundArt is what you see
	_fit_camera_to_map()
	_zoom_i = clampi(int(SaveGame.get_value("view_zoom", ZOOM_NORMAL)), 0, ZOOMS.size() - 1)
	if _zoom_i != ZOOM_NORMAL:
		_apply_zoom.call_deferred()
	get_tree().root.size_changed.connect(func() -> void:
		if _zoom_i != ZOOM_NORMAL:
			_apply_zoom())
	$HUD/Bars.stats = $Entities/Player.stats
	$HUD/Bars.xp = $Entities/Player/Experience
	Gravestone.restore($Entities)
	Pet.restore($Entities/Player)
	$HUD/HotbarUI.hotbar = $Entities/Player/Hotbar
	$HUD/InventoryUI.inventory = $Entities/Player/Inventory
	$HUD/SpellbookUI.hotbar = $Entities/Player/Hotbar
	$HUD/PaperdollUI.equipment = $Entities/Player/Equipment
	RenderingServer.set_default_clear_color(Color("0d0b12"))
	_make_fade_layer()
	add_to_group("world")
	for door in get_tree().get_nodes_in_group("doors"):
		door.entered.connect(_on_door_entered)
	for interior in $Interiors.get_children():
		interior.exit_requested.connect(_on_exit_requested)
	player.stats.died.connect(_on_player_died)


func _generate_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234  # same map every run
	var f := FileAccess.open(MOUNTAINS, FileAccess.READ)
	if f:
		_mountains = JSON.parse_string(f.get_as_text())
	for y in range(MAP_ORIGIN.y, MAP_ORIGIN.y + MAP_SIZE.y):
		for x in range(MAP_ORIGIN.x, MAP_ORIGIN.x + MAP_SIZE.x):
			ground.set_cell(Vector2i(x, y), 0, _pick_tile(x, y, rng))


func _pick_tile(x: int, y: int, rng: RandomNumberGenerator) -> Vector2i:
	# Border wall
	if x == MAP_ORIGIN.x or y == MAP_ORIGIN.y or x == MAP_ORIGIN.x + MAP_SIZE.x - 1 or y == MAP_ORIGIN.y + MAP_SIZE.y - 1:
		return WALL
	if _is_mountain(x, y):
		return WALL
	# Dock at the west end of the road: walkable planks over the sea
	if (y == 15 or y == 16) and x >= DOCK_WEST and x - MAP_ORIGIN.x < OCEAN_SHORE[y - MAP_ORIGIN.y]:
		return PATH
	# West ocean
	if x - MAP_ORIGIN.x < OCEAN_SHORE[y - MAP_ORIGIN.y]:
		return WATER
	# Pond (ellipse); moved 2 + 9 tiles east in Oct 2026 for the new shops (tools/move_pond.py)
	var d := Vector2((x - 44) / 5.0, (y - 8) / 3.0)
	if d.length() <= 1.0:
		return WATER
	# Second pond, out in the south
	if Vector2((x - 62) / 7.0, (y - 46) / 4.0).length() <= 1.0:
		return WATER
	# Village street in front of the shops (north of the crossroads)
	if (y == 9 or y == 10) and x >= 1 and x <= 33:
		return PATH
	# Crossroads
	if y == 15 or y == 16 or x == 12 or x == 13 or ((x == 90 or x == 91) and y >= 15):
		return PATH
	return GRASS_FLOWERS if rng.randf() < 0.08 else GRASS


func _is_mountain(x: int, y: int) -> bool:
	if _mountains.is_empty():
		return false
	var row := y - int(_mountains.y0)
	var col := x - int(_mountains.x0)
	var rows: Array = _mountains.rows
	if row < 0 or row >= rows.size() or col < 0 or col >= (rows[row] as String).length():
		return false
	return (rows[row] as String)[col] == "#"


func _fit_camera_to_map() -> void:
	var cells := ground.get_used_rect()
	var ts := Vector2i(Vector2(ground.tile_set.tile_size) * ground.scale)  # tiles are 32px art drawn at half scale
	_outside_limits = Rect2i(cells.position * ts, cells.size * ts)
	_set_camera_limits(_outside_limits)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	# not while the mouse is over a window or panel of the interface
	if _in_shop():
		return                  # shops are always at normal zoom
	var hovered := get_tree().root.gui_get_hovered_control()
	if hovered != null and not hovered is SubViewportContainer:
		return
	var i := clampi(_zoom_i + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, ZOOMS.size() - 1)
	get_viewport().set_input_as_handled()
	if i == _zoom_i:
		return
	_zoom_i = i
	SaveGame.put("view_zoom", _zoom_i)
	_apply_zoom()


func _apply_zoom() -> void:
	var view := get_viewport() as SubViewport
	var box := view.get_parent() as SubViewportContainer if view else null
	if box == null:
		return                  # running main.tscn on its own: no window wrapper to resize
	var zi := ZOOM_NORMAL if _in_shop() else _zoom_i
	if zi == ZOOM_NORMAL:
		view.size_2d_override = Vector2i.ZERO
		box.scale = Vector2.ONE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.stretch = true
	else:
		# the window's real pixels per screen pixel (2 in a 1280x720 window)
		var k := get_tree().root.get_final_transform().get_scale().x
		var win := Vector2i(roundi(640 * k), roundi(360 * k))
		box.stretch = false
		box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		box.position = Vector2.ZERO
		view.size = win
		view.size_2d_override = Vector2i(640, 360)
		view.size_2d_override_stretch = true
		box.size = Vector2(win)
		box.scale = Vector2(640.0 / win.x, 360.0 / win.y)
	camera.zoom = Vector2.ONE * BASE_ZOOM * float(ZOOMS[zi])
	if _inside:
		_set_camera_limits(_inside.camera_rect(_view_world()))


## Inside a shop (a small room the camera is pinned on) the zoom is locked to normal; the cave
## and the outside use the player's zoom.
func _in_shop() -> bool:
	return _inside != null and float(_inside.get("scroll_margin")) < 0.0


## How much of the world the screen shows (world px).
func _view_world() -> Vector2:
	return Vector2(640, 360) / camera.zoom


func _set_camera_limits(r: Rect2i) -> void:
	camera.limit_left = r.position.x
	camera.limit_top = r.position.y
	camera.limit_right = r.end.x
	camera.limit_bottom = r.end.y


# ---- building entrances (Pokemon style: fade, teleport, fade) ----------------

func _make_fade_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_to_group("ui_layer")   # drawn at full window resolution (see game.gd)
	add_child(layer)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


func _on_door_entered(door: Area2D) -> void:
	if _busy or _inside != null:
		return
	var interior: Node2D = $Interiors.get_node_or_null(door.interior_id)
	if interior == null:
		return
	_return_pos = door.global_position + Vector2(0, 14)
	# small shops are smaller than the screen, so the camera is pinned on the room
	_travel(interior.entry_position() as Vector2, interior.camera_rect(_view_world()), interior)


func _on_exit_requested(_interior: Node2D) -> void:
	if _busy or _inside == null:
		return
	_travel(_return_pos, _outside_limits, null)


## Home teleport: back to the respawn point, wherever you are.
func go_home() -> void:
	if _busy:
		return
	_travel(player._spawn_point, _outside_limits, null)


func _on_player_died() -> void:
	# The player script respawns outside; just put the camera back.
	_inside = null
	_apply_zoom()
	_set_camera_limits(_outside_limits)


func _travel(to_pos: Vector2, limits: Rect2i, new_inside: Node2D) -> void:
	_busy = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.show_idle()
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.15)
	await tw.finished
	player.global_position = to_pos
	player.reset_physics_interpolation()   # jump straight there, no slide across the map
	for pet: Node2D in get_tree().get_nodes_in_group("pets"):   # pets come along through doors
		pet.global_position = to_pos + Vector2(14, 6)
		pet.reset_physics_interpolation()
	_inside = new_inside
	_apply_zoom()                       # back to normal zoom in shops, the player's zoom outside
	_set_camera_limits(limits if _inside == null else _inside.camera_rect(_view_world()))
	camera.reset_smoothing()
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.15)
	await tw.finished
	await get_tree().create_timer(ARRIVAL_LOCK).timeout   # brief movement lock after arriving
	player.velocity = Vector2.ZERO
	player.show_idle()
	player._gather_input()    # keys still held from before the lock count straight away
	player.set_physics_process(true)
	_busy = false
