extends Control
## Bottom-right navigation bar: Inventory (B), Spellbook (K), Equipment (P), Stats (C).
## Click a button (or press its key) to open or close that window.

const SLOT := 14
const ICON := 12
const GAP := 2
const ICONS := preload("res://art/nav_icons.png")
const BUTTONS := [
	{"key": "B", "action": "inventory", "panel": "InventoryUI", "name": "Inventory"},
	{"key": "K", "action": "spellbook", "panel": "SpellbookUI", "name": "Spellbook"},
	{"key": "P", "action": "paperdoll", "panel": "PaperdollUI", "name": "Equipment"},
	{"key": "C", "action": "stats", "panel": "StatsUI", "name": "Stats"},
]

var _hover := -1


func _ready() -> void:
	size = Vector2(BUTTONS.size() * SLOT + (BUTTONS.size() - 1) * GAP, SLOT)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2(screen.x - size.x - 4, screen.y - SLOT - 3)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	queue_redraw()   # cheap; keeps the "open" highlight in sync with the keys


func _index_at(p: Vector2) -> int:
	for i in BUTTONS.size():
		if Rect2(i * (SLOT + GAP), 0, SLOT, SLOT).has_point(p):
			return i
	return -1


func _is_open(i: int) -> bool:
	var panel := get_parent().get_node_or_null(BUTTONS[i]["panel"]) as Control
	return panel != null and panel.visible


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _index_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(event.position)
		if i != -1:
			var ev := InputEventAction.new()
			ev.action = BUTTONS[i]["action"]
			ev.pressed = true
			Input.parse_input_event(ev)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _draw() -> void:
	for i in BUTTONS.size():
		var r := Rect2(Vector2(i * (SLOT + GAP), 0), Vector2(SLOT, SLOT))
		var open := _is_open(i)
		UiStyle.slot(self, r, open or i == _hover)
		draw_texture_rect_region(ICONS, Rect2(r.position + Vector2.ONE, Vector2(ICON, ICON)),
				Rect2(i * 16, 0, 16, 16), Color(1, 1, 1, 1.0 if (open or i == _hover) else 0.85))
		if open:
			draw_rect(r, Color(0.9, 0.55, 0.08, 0.95), false, 1.0)
		HiFont.draw(self, r.position + Vector2(SLOT - 4.5, SLOT - 5.5), BUTTONS[i]["key"], UiStyle.TEXT, 0.5)
	if _hover != -1:
		var label: String = BUTTONS[_hover]["name"].to_upper()
		var px := 0.5
		var w := HiFont.text_width(label, px) + 6 * px
		var h := HiFont.H * px + 6 * px
		var tp := Vector2(size.x - w, -h - 2).snapped(Vector2(px, px))
		UiStyle.panel(self, Rect2(tp, Vector2(w, h)))
		HiFont.draw(self, tp + Vector2(3, 3) * px, label, UiStyle.GOLD, px)
