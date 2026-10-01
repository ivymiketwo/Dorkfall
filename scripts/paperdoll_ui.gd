class_name PaperdollUI
extends Control
## Equipment panel (press P). Shows Rex wearing his gear with slots for helmet,
## weapon, chest and shield. The shield slot greys out while a two-handed weapon
## is equipped. Right-click a slot to take the item off.

const SLOT := 20
const ICONS := preload("res://art/items.png")     # 32px icons, drawn 16x16 units
const BASE := preload("res://art/player.png")
const PANEL_BG := Color("3b3226")
const PANEL_BORDER := Color("1a140e")
const PANEL_LIGHT := Color("5c4d3a")
const SLOT_BG := Color("1a150f")
const SLOT_EDGE := Color("4d4130")
const SLOT_HOVER := Color("3d3324")
const HINT := {"helmet": "head", "weapon": "weapon", "chest": "body", "shield": "shield"}

# slot rectangles inside the panel
const SLOT_POS := {
	"helmet": Vector2(34, 14), "weapon": Vector2(6, 40),
	"shield": Vector2(62, 40), "chest": Vector2(34, 74),
}

var equipment: Equipment:
	set(value):
		if equipment:
			equipment.changed.disconnect(queue_redraw)
		equipment = value
		if equipment:
			equipment.changed.connect(queue_redraw)
		queue_redraw()

var _hover := ""
var _mouse := Vector2.ZERO


func _ready() -> void:
	size = Vector2(88, 136)
	position = Vector2(4, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("paperdoll_ui")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("paperdoll"):
		visible = not visible
		get_viewport().set_input_as_handled()


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func _slot_at(p: Vector2) -> String:
	for s: String in SLOT_POS:
		if Rect2(SLOT_POS[s], Vector2(SLOT, SLOT)).has_point(p):
			return s
	return ""


func _gui_input(event: InputEvent) -> void:
	if equipment == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _slot_at(_mouse)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var slot := _slot_at(event.position)
		var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
		var it := equipment.get_item(slot) if slot != "" else null
		if it and menu:
			_hover = ""
			queue_redraw()
			menu.open_at_screen(get_viewport().get_mouse_position(), [
				{"label": "Unequip " + it.display_name, "callback": equipment.unequip.bind(slot)}])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""
		queue_redraw()


func _draw() -> void:
	if equipment == null:
		return
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(6, 5), "Equipment", UiStyle.GOLD, px)

	# the paperdoll itself: base body + worn layers, facing the camera
	var fig := Rect2(Vector2(32, 38), Vector2(24, 40))
	draw_texture_rect_region(BASE, fig, Rect2(96, 0, 24, 40))
	for slot: String in Equipment.LAYER_ORDER:
		var it := equipment.get_item(slot)
		if it and it.worn_texture:
			draw_texture_rect_region(it.worn_texture, fig, Rect2(96, 0, 24, 40))

	for slot: String in SLOT_POS:
		var p: Vector2 = SLOT_POS[slot]
		var blocked := slot == "shield" and equipment.shield_blocked()
		UiStyle.slot(self, Rect2(p, Vector2(SLOT, SLOT)), slot == _hover and not blocked)
		var it := equipment.get_item(slot)
		if it:
			draw_texture_rect_region(ICONS, Rect2(p + Vector2(2, 2), Vector2(16, 16)),
					Rect2(it.icon_frame * 32, 0, 32, 32))
		else:
			var hint: String = HINT[slot]
			var w := HiFont.text_width(hint, px * 0.8)
			HiFont.draw(self, p + Vector2((SLOT - w) / 2.0, 7), hint, Color(0.45, 0.4, 0.32), px * 0.8)
		if blocked:
			draw_rect(Rect2(p + Vector2.ONE, Vector2(SLOT - 2, SLOT - 2)), Color(0.02, 0.02, 0.02, 0.8))
			draw_line(p + Vector2(3, 3), p + Vector2(SLOT - 3, SLOT - 3), Color(0.55, 0.15, 0.15), 1.0)
			draw_line(p + Vector2(SLOT - 3, 3), p + Vector2(3, SLOT - 3), Color(0.55, 0.15, 0.15), 1.0)
			var w2 := HiFont.text_width("2H", px)
			HiFont.draw(self, p + Vector2((SLOT - w2) / 2.0, SLOT + 2), "2H", Color("e03c3c"), px)

	# totals from everything worn
	var ty := 100.0
	draw_line(Vector2(6, ty - 3), Vector2(size.x - 6, ty - 3), Color(0.55, 0.42, 0.22, 0.6), 1.0)
	HiFont.draw(self, Vector2(6, ty), "Gear bonuses", UiStyle.GOLD, px)
	var rows := [
		["Defense", "%s%%" % _fmt(equipment.total("defense"))],
		["Mana regen", "+%s/s" % _fmt(equipment.total("mana_regen_bonus"))],
		["Magic dmg", "+%s%%" % _fmt(equipment.total("magic_damage_bonus"))],
	]
	for k in rows.size():
		var y := ty + 11 + k * 9
		HiFont.draw(self, Vector2(6, y), rows[k][0], UiStyle.TEXT_DIM, px)
		HiFont.draw(self, Vector2(size.x - 6 - HiFont.text_width(rows[k][1], px), y), rows[k][1], Color("8fd0ff"), px)

	# tooltip
	if _hover != "":
		var hit := equipment.get_item(_hover)
		var label: String = hit.display_name if hit else Equipment.SLOT_NAMES[_hover]
		if _hover == "shield" and equipment.shield_blocked():
			label = "Blocked by two-handed weapon"
		var lines: PackedStringArray = hit.stat_lines() if hit and label == hit.display_name else PackedStringArray()
		var w := HiFont.text_width(label, px)
		for l in lines:
			w = maxf(w, HiFont.text_width(l, px))
		w += 6 * px
		var lh := (HiFont.H + 3) * px
		var h := HiFont.H * px + 6 * px + lines.size() * lh
		var tp := Vector2(minf(_mouse.x + 6, size.x - w - 2), _mouse.y + 8).snapped(Vector2(px, px))
		UiStyle.panel(self, Rect2(tp, Vector2(w, h)))
		HiFont.draw(self, tp + Vector2(3, 3) * px, label, UiStyle.GOLD, px)
		for k in lines.size():
			HiFont.draw(self, tp + Vector2(3 * px, 3 * px + (k + 1) * lh), lines[k], Color("8fd0ff"), px)


func _fmt(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")
