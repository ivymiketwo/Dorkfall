extends CanvasLayer
## Minimap + world map (press M) with fog of war, after Hearthlight's map:
## the world is hidden under a dark veil in 8x8-tile cells that lift wherever
## you walk. The explored cells are saved.

const TILE := 16.0
const ORIGIN := Vector2(-105, -62)        # tile coordinates of the map's top-left
const FOG := 8
const REVEAL_RADIUS := 14.0               # tiles
const MINI_SIZE := Vector2(96, 64)

var _base: Texture2D
var _veil_img: Image
var _veil_tex: ImageTexture
var _w := 300
var _h := 168
var _fw := 0
var _fh := 0
var _fog := PackedByteArray()
var _mini: Control
var _full: Control
var _t := 0.0
var _scan := 0.0
var _dirty := false


func _ready() -> void:
	layer = 3
	_base = load("res://art/world_map.png")
	_w = _base.get_width()
	_h = _base.get_height()
	_fw = ceili(float(_w) / FOG)
	_fh = ceili(float(_h) / FOG)
	_fog.resize(_fw * _fh)
	var saved = SaveGame.get_value("map_fog", "")
	if saved is String and saved != "":
		var raw := Marshalls.base64_to_raw(saved)
		if raw.size() == _fog.size():
			_fog = raw
	_veil_img = Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	_paint_veil()
	_veil_tex = ImageTexture.create_from_image(_veil_img)
	_mini = Control.new()
	_mini.position = Vector2(640 - 4 - MINI_SIZE.x, 4)
	_mini.size = MINI_SIZE
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.draw.connect(_draw_mini)
	add_child(_mini)
	_full = Control.new()
	_full.position = Vector2.ZERO
	_full.size = Vector2(640, 360)
	_full.mouse_filter = Control.MOUSE_FILTER_STOP
	_full.visible = false
	_full.draw.connect(_draw_full)
	add_child(_full)


func _hash(x: int, z: int) -> float:
	var n := (x * 374761393 + z * 668265263 + 9 * 2246822519) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


func _seen(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < _fw and cz < _fh and _fog[cz * _fw + cx] != 0


func _paint_cell(cx: int, cz: int) -> void:
	for j in FOG:
		for i in FOG:
			var x := cx * FOG + i
			var z := cz * FOG + j
			if x >= _w or z >= _h:
				continue
			if _seen(cx, cz):
				_veil_img.set_pixel(x, z, Color(0, 0, 0, 0))
				continue
			# dithered edge beside what is already known
			var edge := (i == 0 and _seen(cx - 1, cz)) or (i == FOG - 1 and _seen(cx + 1, cz)) \
					or (j == 0 and _seen(cx, cz - 1)) or (j == FOG - 1 and _seen(cx, cz + 1))
			if edge and (x + z) % 2 == 1:
				_veil_img.set_pixel(x, z, Color(0, 0, 0, 0))
				continue
			var a := _hash(x >> 1, z >> 1) < 0.5
			_veil_img.set_pixel(x, z, Color8(58, 47, 70, 189) if a else Color8(52, 42, 64, 199))


func _paint_veil() -> void:
	for cz in _fh:
		for cx in _fw:
			_paint_cell(cx, cz)


## Lifts the fog around a tile position; returns true if something new showed.
func reveal(tile: Vector2) -> bool:
	var changed := false
	var c0 := floori((tile.x - REVEAL_RADIUS) / FOG)
	var c1 := floori((tile.x + REVEAL_RADIUS) / FOG)
	var d0 := floori((tile.y - REVEAL_RADIUS) / FOG)
	var d1 := floori((tile.y + REVEAL_RADIUS) / FOG)
	for cz in range(d0, d1 + 1):
		for cx in range(c0, c1 + 1):
			if cx < 0 or cz < 0 or cx >= _fw or cz >= _fh or _fog[cz * _fw + cx] != 0:
				continue
			var mid := Vector2(cx * FOG + FOG / 2.0, cz * FOG + FOG / 2.0)
			if mid.distance_to(tile) > REVEAL_RADIUS + 4.0:
				continue
			_fog[cz * _fw + cx] = 1
			changed = true
			for dc in range(-1, 2):
				for dz in range(-1, 2):
					if cx + dc >= 0 and cz + dz >= 0 and cx + dc < _fw and cz + dz < _fh:
						_paint_cell(cx + dc, cz + dz)
	return changed


func _player() -> Node2D:
	return Players.local(get_tree())


func _tile_of(p: Node2D) -> Vector2:
	return p.global_position / TILE - ORIGIN


func _outside(p: Node2D) -> bool:
	return p != null and p.global_position.y < 2300.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			_full.visible = not _full.visible
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE and _full.visible:
			_full.visible = false
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	_scan -= delta
	var p := _player()
	if _scan <= 0.0:
		_scan = 0.25
		if _outside(p) and reveal(_tile_of(p)):
			_veil_tex.update(_veil_img)
			_dirty = true
	if _dirty and _t - floorf(_t) < 0.05:
		_dirty = false
		SaveGame.put("map_fog", Marshalls.raw_to_base64(_fog))
	_mini.visible = _outside(p) and not _full.visible
	if _mini.visible:
		_mini.queue_redraw()
	if _full.visible:
		_full.queue_redraw()


func _frame(c: Control, r: Rect2) -> void:
	c.draw_rect(r.grow(2), Color("14121c"))
	c.draw_rect(r.grow(1), Color("90734f"))
	c.draw_rect(r, Color("14121c"))


func _marker(c: Control, pos: Vector2) -> void:
	var on := int(_t * 2.0) % 2 == 0
	c.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(5, 5)), Color("14121c"))
	c.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(3, 3)), Color("fff3c4") if on else Color("f6c65b"))


func _draw_mini() -> void:
	var p := _player()
	if p == null:
		return
	var t := _tile_of(p)
	var r := Rect2(Vector2.ZERO, MINI_SIZE)
	_frame(_mini, r)
	# the window onto the map, centred on the player (kept inside the map)
	var src_size := MINI_SIZE
	var src_pos := (t - src_size / 2.0).clamp(Vector2.ZERO, Vector2(_w, _h) - src_size)
	var src := Rect2(src_pos.floor(), src_size)
	_mini.draw_texture_rect_region(_base, r, src)
	_mini.draw_texture_rect_region(_veil_tex, r, src)
	_quest_markers(_mini, p, func(tile: Vector2) -> Vector2: return tile - src.position, r)
	_marker(_mini, t - src.position)


func _draw_full() -> void:
	_full.draw_rect(Rect2(Vector2.ZERO, Vector2(640, 360)), Color(0.05, 0.04, 0.08, 0.82))
	var s := 2.0
	var size := Vector2(_w, _h) * s
	var pos := Vector2((640.0 - size.x) / 2.0, 22.0)
	var r := Rect2(pos, size)
	_frame(_full, r)
	_full.draw_texture_rect(_base, r, false)
	_full.draw_texture_rect(_veil_tex, r, false)
	HiFont.draw(_full, Vector2(pos.x, 9), "WORLD MAP", UiStyle.TEXT, 1.0)
	var known := 0
	for v in _fog:
		if v != 0:
			known += 1
	var pct := "%d%% EXPLORED" % roundi(100.0 * known / _fog.size())
	HiFont.draw(_full, Vector2(pos.x + 70, 9), pct, UiStyle.TEXT, 1.0)
	HiFont.draw(_full, Vector2(pos.x + 450, 9), "M OR ESC TO CLOSE", UiStyle.TEXT, 1.0)
	var p := _player()
	if p != null and _outside(p):
		_quest_markers(_full, p, func(tile: Vector2) -> Vector2: return pos + tile * s, r)
		_marker(_full, pos + _tile_of(p) * s)


## Blinking gold markers where the tracked quest leads. Off the edge of the minimap they
## stick to the border as an arrow pointing the way.
func _quest_markers(c: Control, p: Node2D, to_screen: Callable, clip: Rect2) -> void:
	var on := int(_t * 3.0) % 2 == 0
	var col := Color("ffe066") if on else Color("f08a28")
	for wp in Quests.targets(get_tree(), p):
		var pos: Vector2 = to_screen.call(wp / TILE - ORIGIN)
		var inside := clip.grow(-3).has_point(pos)
		if inside:
			c.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(7, 7)), Color("14121c"))
			c.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(5, 5)), col)
			c.draw_rect(Rect2(pos - Vector2(0, 1), Vector2(1, 2)), Color("14121c"))
		else:
			var centre := clip.get_center()
			var dir := (pos - centre).normalized()
			# where the line from the centre toward the marker leaves the (inset) map box
			var half := clip.size / 2.0 - Vector2(4, 4)
			var tx := half.x / maxf(absf(dir.x), 0.0001)
			var ty := half.y / maxf(absf(dir.y), 0.0001)
			var edge := centre + dir * minf(tx, ty)
			var side := Vector2(-dir.y, dir.x)
			c.draw_colored_polygon(PackedVector2Array([edge + dir * 3.5, edge - dir * 2.5 + side * 3.0, edge - dir * 2.5 - side * 3.0]), col)
