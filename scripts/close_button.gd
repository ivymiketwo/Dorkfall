class_name CloseButton
extends Control
## The little X in the top-right corner of every menu and dialogue box.
## Every window must have one (it also makes the window movable, see WindowDrag): call `CloseButton.attach(self)` in the menu's _ready() and give it a
## `close_ui()` method (then Esc closes it too). It sits flush inside the top-right corner.
## `CloseButton.close_top(tree)` closes the front-most open menu (used by Esc).

const SZ := 7.0
## Menus join this group and offer `close_ui()`; optional `ui_is_open()` (default: `visible`).
const GROUP := "closable_ui"

var _menu: Object
var _auto := true
var _hover := false

# 7x7 pixel X, drawn with half-unit pixels so it matches the rest of the HUD art
const X_PIXELS := ["X.....X", ".X...X.", "..X.X..", "...X...", "..X.X..", ".X...X.", "X.....X"]


static func attach(menu: Control) -> void:
	menu.add_to_group(GROUP)
	WindowDrag.attach(menu)          # every window with a close button can be dragged by its title bar
	var b := CloseButton.new()
	b.name = "CloseButton"
	b._menu = menu
	menu.add_child(b)


## For menus that are not a plain HUD Control (the world map): put the button in `host` at `at`.
static func attach_custom(host: Control, closer: Object, at: Vector2, scale_by := 1.0) -> void:
	if closer is Node:
		(closer as Node).add_to_group(GROUP)
	var b := CloseButton.new()
	b.name = "CloseButton"
	b._menu = closer
	b._auto = false
	b.position = at
	b.scale = Vector2(scale_by, scale_by)
	host.add_child(b)


static func close_top(tree: SceneTree) -> bool:
	var nodes := tree.get_nodes_in_group(GROUP)
	nodes.reverse()          # later in the HUD = drawn on top = closed first
	for n in nodes:
		var open: bool = n.call("ui_is_open") if n.has_method("ui_is_open") else (n as Control).visible
		if open:
			n.call("close_ui")
			return true
	return false


func _ready() -> void:
	size = Vector2(SZ, SZ)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 5
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	if _auto:
		(_menu as Control).resized.connect(_place)
		_place()


func _place() -> void:
	# in the right end of the title bar (UiStyle.window), inside the frame
	position = Vector2((_menu as Control).size.x - SZ - UiStyle.FRAME - 1.0, UiStyle.FRAME + (UiStyle.TITLE_H - SZ) / 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_menu.call("close_ui")
		accept_event()


func _draw() -> void:
	var p := 0.5
	UiStyle.button(self, Rect2(Vector2.ZERO, size), "", 1 if _hover else 0, p)
	var o := ((size - Vector2(7, 7) * p) / 2.0).snapped(Vector2(p, p))
	for y in X_PIXELS.size():
		for x in 7:
			if X_PIXELS[y][x] == "X":
				draw_rect(Rect2(o + Vector2(x, y) * p, Vector2(p, p)), Color("ff6a5a") if _hover else UiStyle.TEXT)
