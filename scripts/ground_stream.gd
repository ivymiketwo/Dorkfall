@tool
class_name GroundStream
extends Node2D
## Draws the painted ground, loading only the squares around the camera.
##
## The painting is cut into squares of `tile_world` world px (art/ground/g_<col>_<row>.png,
## made by tools/ground_tiles.py). The squares around the camera's square are kept loaded
## (`load_radius` 1 = a 3x3 block); squares farther than `keep_radius` are let go, so memory
## stays the same however big the map gets. Squares that are on screen and still missing are
## loaded at once (never a hole); the ring around them loads in the background.
## In the editor every square is shown, so placing things on the map works as before.
## Squares with no file are land the camera can never see; they are simply skipped.

const DIR := "res://art/ground/"

## World position of the painting's top-left corner.
@export var origin := Vector2(-1680, -992)
@export var tile_world := 512.0
@export var cols := 13
@export var rows := 6
## Art pixels per world pixel (the ground is painted at double resolution).
@export var art_scale := 2.0
## Squares kept loaded around the camera's square (1 = 3x3).
@export var load_radius := 1
## Squares farther than this from the camera's square are unloaded (a gap so they don't flicker).
@export var keep_radius := 2

var _tiles := {}      ## Vector2i -> Sprite2D
var _pending := {}    ## Vector2i -> path being loaded in the background


func _ready() -> void:
	process_priority = 100     # after the camera has moved this frame
	if Engine.is_editor_hint():
		for r in rows:
			for c in cols:
				if ResourceLoader.exists(_path(Vector2i(c, r))):
					_show(Vector2i(c, r), load(_path(Vector2i(c, r))))
		return
	_update.call_deferred(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update(false)


## How many squares are loaded right now (for tests and the debug overlay).
func loaded_count() -> int:
	return _tiles.size()


func _path(cell: Vector2i) -> String:
	return DIR + "g_%d_%d.png" % [cell.x, cell.y]


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(cell) * tile_world, Vector2(tile_world, tile_world))


func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport().get_visible_rect().size
	if cam == null:
		return Rect2(Vector2.ZERO, size)
	var half := size / cam.zoom * 0.5
	var now := Rect2(cam.get_screen_center_position() - half, half * 2.0)
	# also where the camera is heading (it lags a frame behind a teleport or respawn)
	return now.merge(Rect2(cam.global_position - half, half * 2.0))


func _update(all_sync: bool) -> void:
	var view := _view_rect()
	var cam := get_viewport().get_camera_2d()
	var focus := cam.global_position if cam else view.get_center()
	var center := Vector2i(((focus - origin) / tile_world).floor())
	var on_screen := view.grow(16.0)
	# squares we want: the block around the camera's square
	for dy in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			var cell := center + Vector2i(dx, dy)
			if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows or _tiles.has(cell):
				continue
			if not ResourceLoader.exists(_path(cell)):
				continue          # land nobody can see (around the east ravine) isn't stored
			if all_sync or on_screen.intersects(_cell_rect(cell)):
				_show(cell, load(_path(cell)))          # on screen: load now, no hole
			elif not _pending.has(cell):
				_pending[cell] = _path(cell)
				ResourceLoader.load_threaded_request(_pending[cell])
	# finished background loads (always collected, even if no longer wanted)
	for cell: Vector2i in _pending.keys():
		var path: String = _pending[cell]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_pending.erase(cell)
		var tex: Texture2D = ResourceLoader.load_threaded_get(path) if status == ResourceLoader.THREAD_LOAD_LOADED else null
		if tex != null and not _tiles.has(cell) and _near(cell, center, keep_radius):
			_show(cell, tex)
	# let go of far squares
	for cell: Vector2i in _tiles.keys():
		if not _near(cell, center, keep_radius):
			_tiles[cell].queue_free()
			_tiles.erase(cell)


func _near(cell: Vector2i, center: Vector2i, radius: int) -> bool:
	return absi(cell.x - center.x) <= radius and absi(cell.y - center.y) <= radius


func _show(cell: Vector2i, tex: Texture2D) -> void:
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2.ONE / art_scale
	s.position = _cell_rect(cell).position
	add_child(s)
	_tiles[cell] = s
