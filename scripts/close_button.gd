class_name CloseButton
extends Control
## The little X in the top-right corner of every menu and dialogue box.
## `CloseButton.attach(menu)` adds one to a menu; the menu needs `close_ui()`.
## `CloseButton.close_top(tree)` closes the front-most open menu (used by Esc).

const SZ := 8.0
## Menus join this group and offer `close_ui()`; optional `ui_is_open()` (default: `visible`).
const GROUP := "closable_ui"

var _menu: Object
var _auto := true
var _hover := false

# 7x7 pixel X, drawn with half-unit pixels so it matches the rest of the HUD art
const X_PIXELS := ["X.....X", ".X...X.", "..X.X..", "...X...", "..X.X..", ".X...X.", "X.....X"]


static func attach(menu: Control) -> void:
	menu.add_to_group(GROUP)
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
	position = Vector2((_menu as Control).size.x - SZ + 3.0, -3.0)    # straddles the corner so it never covers content


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_menu.call("close_ui")
		accept_event()


func _draw() -> void:
	var p := 0.5
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("7a2020") if not _hover else Color("c03030"))
	var o := (size - Vector2(7, 7) * p) / 2.0
	for y in X_PIXELS.size():
		for x in 7:
			if X_PIXELS[y][x] == "X":
				draw_rect(Rect2(o + Vector2(x, y) * p, Vector2(p, p)), Color("fff0d0"))
