class_name ContextMenu
extends Control
## RuneScape-style right-click menu. Anyone can call
## `open_at_screen(mouse_pos, [{"label": "DROP", "callback": some_callable}])`.
## Click an option to run it; click anywhere else (or Esc) to close.

const ROW_H := 6.0
const PAD := 2.0

var _options: Array = []
var _hover := -1
var _pos := Vector2.ZERO
var _size := Vector2.ZERO
var _open := false


func _ready() -> void:
	add_to_group("context_menu")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func open_at_screen(screen_pos: Vector2, options: Array) -> void:
	_options = options.duplicate()
	_options.append({"label": "Cancel", "callback": Callable()})
	var px := _px()
	var widest := 0.0
	for o: Dictionary in _options:
		widest = maxf(widest, HiFont.text_width(o.label, px))
	_size = Vector2(widest + PAD * 2 + 2, _options.size() * ROW_H + PAD)
	var at: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var view: Vector2 = get_viewport_rect().size / get_canvas_transform().get_scale()
	_pos = Vector2(minf(at.x, view.x - _size.x - 1), minf(at.y, view.y - _size.y - 1)).snapped(Vector2(px, px))
	_hover = -1
	_open = true
	queue_redraw()


func is_open() -> bool:
	return _open


func close() -> void:
	_open = false
	queue_redraw()


func _row_at(local: Vector2) -> int:
	var r := Rect2(_pos, _size)
	if not r.has_point(local):
		return -1
	return clampi(floori((local.y - _pos.y - PAD / 2.0) / ROW_H), 0, _options.size() - 1)


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		_hover = _row_at(get_canvas_transform().affine_inverse() * event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var row := _row_at(get_canvas_transform().affine_inverse() * event.position)
		var chosen: Callable = Callable()
		if row != -1 and event.button_index == MOUSE_BUTTON_LEFT:
			chosen = _options[row].callback
		close()
		if chosen.is_valid():
			chosen.call()
		get_viewport().set_input_as_handled()   # the click that closes the menu does nothing else
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not _open:
		return
	var px := _px()
	UiStyle.panel(self, Rect2(_pos - Vector2(px, px), _size + Vector2(px, px) * 2))
	for i in _options.size():
		var y := _pos.y + PAD / 2.0 + i * ROW_H
		if i == _hover:
			draw_rect(Rect2(_pos.x + px, y, _size.x - px * 2, ROW_H), Color("4a3d5a"))
		var col := UiStyle.GOLD if i == _hover else UiStyle.TEXT
		HiFont.draw(self, Vector2(_pos.x + PAD, y + (ROW_H - HiFont.H * px) / 2.0), _options[i].label, col, px)
