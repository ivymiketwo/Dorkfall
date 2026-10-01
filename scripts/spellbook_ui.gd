extends Control
## Spellbook: lists the abilities the player knows. Press K to show/hide.
## Drag a spell onto a hotbar slot to assign it.

const ICONS := preload("res://art/icons.png")
const ROW_H := 20
const ROW_W := 78
const PAD := 3
const DRAG_START := 3.0

var hotbar: Hotbar:
	set(value):
		hotbar = value
		if is_node_ready():
			_resize()
		queue_redraw()

var _hover := -1
var _press := -1
var _dragging := false
var _press_pos := Vector2.ZERO
var _mouse := Vector2.ZERO


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resize()


func _resize() -> void:
	size = Vector2(ROW_W + PAD * 2, maxi(_spells().size(), 1) * ROW_H + PAD * 2 + 9)
	var inv := get_parent().get_node_or_null("InventoryUI") as Control
	if inv:
		position = Vector2(inv.position.x - size.x - 3, inv.position.y + inv.size.y - size.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("spellbook"):
		visible = not visible
		_press = -1
		_dragging = false
		get_viewport().set_input_as_handled()


func _spells() -> Array[Ability]:
	return hotbar.known if hotbar else ([] as Array[Ability])


func _row_at(p: Vector2) -> int:
	var q := p - Vector2(PAD, PAD + 9)
	if q.x < 0 or q.y < 0 or q.x >= ROW_W:
		return -1
	var r := floori(q.y / ROW_H)
	return r if r < _spells().size() else -1


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _row_at(_mouse)
		if _press != -1 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_START:
			_dragging = true
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = _row_at(event.position)
			_press_pos = event.position
			_dragging = false
		else:
			if _dragging and _press != -1:
				var hb := get_tree().get_first_node_in_group("hotbar_ui")
				if hb:
					hb.drop_ability_at(position + event.position, _spells()[_press])
			_press = -1
			_dragging = false
			queue_redraw()


func _draw() -> void:
	if hotbar == null:
		return
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(PAD, PAD), "SPELLBOOK", UiStyle.GOLD, px)
	var spells := _spells()
	for i in spells.size():
		var ab := spells[i]
		var r := Rect2(Vector2(PAD, PAD + 9 + i * ROW_H), Vector2(ROW_W, ROW_H - 1))
		UiStyle.slot(self, Rect2(r.position, Vector2(18, 18)), i == _hover)
		if not (_dragging and i == _press):
			draw_texture_rect_region(ICONS, Rect2(r.position + Vector2.ONE, Vector2(16, 16)),
					Rect2(ab.icon_index * 16, 0, 16, 16))
		HiFont.draw(self, r.position + Vector2(21, 2), ab.display_name, UiStyle.TEXT, px)
		HiFont.draw(self, r.position + Vector2(21, 11), ("CAST 5 S" if ab.kind == Ability.Kind.HOME_TELEPORT else "%d MP  %d S" % [int(ab.mana_cost), int(ab.cooldown)]),
				UiStyle.TEXT_DIM, px)
	if _dragging and _press != -1:
		draw_texture_rect_region(ICONS, Rect2(_mouse - Vector2(8, 8), Vector2(16, 16)),
				Rect2(spells[_press].icon_index * 16, 0, 16, 16), Color(1, 1, 1, 0.85))
