class_name WindowDrag
extends Control
## Makes a window movable: an invisible handle over its title bar (left of the close button).
## Drag the title bar to move the window; it stays fully on screen. Where you leave each window is
## remembered (saved as "window_pos", by window name) and used every time it opens again. Opening
## or clicking a window also brings it in front of the others.
## Added automatically by CloseButton.attach, so every window with a close button can be moved.

const SAVE_KEY := "window_pos"

var _menu: Control
var _dragging := false
var _offset := Vector2.ZERO


static func attach(menu: Control) -> void:
	var d := WindowDrag.new()
	d.name = "WindowDrag"
	d._menu = menu
	menu.add_child(d)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	_menu.resized.connect(_fit)
	_menu.visibility_changed.connect(_on_shown)
	_fit()
	if _menu.visible:                # a window that starts open (the bag) goes back where it was
		_restore.call_deferred()


## Covers the title bar, except the close button at its right end.
func _fit() -> void:
	position = Vector2(UiStyle.FRAME, UiStyle.FRAME)
	size = Vector2(maxf(_menu.size.x - UiStyle.FRAME * 2.0 - CloseButton.SZ - 2.0, 0.0), UiStyle.TITLE_H)


func _px() -> float:
	return 1.0 / maxf(_menu.get_canvas_transform().get_scale().x, 0.001)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_offset = _menu.position - _canvas_pos(event)
			bring_to_front(_menu)
		elif _dragging:
			_dragging = false
			_remember()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_menu.position = _clamped((_canvas_pos(event) + _offset).snapped(Vector2.ONE * _px()))
		accept_event()


## Where the mouse is, in the HUD's own units (the event comes in this handle's coordinates).
func _canvas_pos(event: InputEventMouse) -> Vector2:
	return get_global_transform() * event.position


## Keeps the whole window on screen.
func _clamped(p: Vector2) -> Vector2:
	var screen := _menu.get_viewport_rect().size / _menu.get_canvas_transform().get_scale()
	return p.clamp(Vector2.ZERO, (screen - _menu.size).max(Vector2.ZERO))


func _remember() -> void:
	var all = SaveGame.get_value(SAVE_KEY, {})
	if not all is Dictionary:
		all = {}
	all[String(_menu.name)] = [_menu.position.x, _menu.position.y]
	SaveGame.put(SAVE_KEY, all)


## When the window opens: in front, and back where it was left (after the window's own
## open() has placed it, hence deferred).
func _on_shown() -> void:
	if _menu.visible:
		bring_to_front(_menu)
		_restore.call_deferred()


func _restore() -> void:
	var all = SaveGame.get_value(SAVE_KEY, {})
	if all is Dictionary and all.has(String(_menu.name)):
		var v: Array = all[String(_menu.name)]
		if v.size() == 2:
			_menu.position = _clamped(Vector2(float(v[0]), float(v[1])))


## Draws `menu` over the other windows (later in the HUD = drawn on top, and closed first by Esc).
static func bring_to_front(menu: Control) -> void:
	var parent := menu.get_parent()
	if parent and menu.get_index() != parent.get_child_count() - 1:
		parent.move_child(menu, -1)
