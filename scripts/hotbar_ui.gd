extends Control
## Draws the 6-slot hotbar along the bottom of the screen, plus a cast bar.

const SLOT := 14
const ICON := 12   # the 16px art is drawn smaller to fit
const GAP := 2
const ICONS := preload("res://art/icons.png")
const ITEM_ICONS := preload("res://art/items.png")   # 32px frames, drawn at 16px
const DRAG_START := 3.0

const BG := Color(0.03, 0.03, 0.03, 0.7)
const BORDER := Color("4a4a55")
const SELECTED := Color(0.9, 0.55, 0.08, 0.95)
const FAIL := Color("e03c3c")

var hotbar: Hotbar:
	set(value):
		if hotbar:
			hotbar.changed.disconnect(queue_redraw)
		hotbar = value
		if hotbar:
			hotbar.changed.connect(queue_redraw)
		queue_redraw()

var _press_slot := -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _mouse := Vector2.ZERO


func _ready() -> void:
	add_to_group("hotbar_ui")


func _origin() -> Vector2:
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	var total_w := Hotbar.PER_BAR * SLOT + (Hotbar.PER_BAR - 1) * GAP
	return Vector2(floori((screen.x - total_w) / 2.0), screen.y - SLOT - 3)


## Which hotbar slot is under a HUD-space point (-1 = none).
func slot_at(p: Vector2) -> int:
	var o := _origin()
	for s in Hotbar.PER_BAR:
		if Rect2(o + Vector2(s * (SLOT + GAP), 0), Vector2(SLOT, SLOT)).has_point(p):
			return (hotbar.active_bar if hotbar else 0) * Hotbar.PER_BAR + s
	return -1


## The little up / down arrows to the left of the bar: [up rect, down rect, number position].
func _arrows() -> Array:
	var o := _origin()
	var x := o.x - 12
	return [Rect2(x, o.y, 10, 5), Rect2(x, o.y + SLOT - 5, 10, 5), Vector2(x + 3.5, o.y + 5.25)]


func drop_item_at(p: Vector2, item: Item) -> void:
	var i := slot_at(p)
	if i != -1 and hotbar:
		hotbar.assign_item(i, item)


func drop_ability_at(p: Vector2, ab: Ability) -> void:
	var i := slot_at(p)
	if i != -1 and hotbar:
		hotbar.assign_ability(i, ab)


func _hud_pos(event: InputEventMouse) -> Vector2:
	return get_canvas_transform().affine_inverse() * event.position


func _input(event: InputEvent) -> void:
	if hotbar == null:
		return
	if event is InputEventMouseMotion:
		_mouse = _hud_pos(event)
		if _press_slot != -1 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_START:
			_dragging = true
		if _dragging:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var wp := _hud_pos(event)
		var wo := _origin()
		var bar_rect := Rect2(wo + Vector2(-12, 0), Vector2(12 + Hotbar.PER_BAR * (SLOT + GAP), SLOT))
		if bar_rect.has_point(wp):
			hotbar.set_bar(hotbar.active_bar + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _hud_pos(event)
		if event.pressed:
			var arr := _arrows()
			if (arr[0] as Rect2).has_point(p) or (arr[1] as Rect2).has_point(p):
				hotbar.set_bar(hotbar.active_bar + (-1 if (arr[0] as Rect2).has_point(p) else 1))
				get_viewport().set_input_as_handled()
				return
			var i := slot_at(p)
			if i != -1:
				get_viewport().set_input_as_handled()   # don't swing the weapon
				if hotbar.has_content(i):
					_press_slot = i
					_press_pos = p
					_mouse = p
					_dragging = false
		elif _press_slot != -1:
			var from := _press_slot
			_press_slot = -1
			if _dragging:
				var to := slot_at(p)
				if to != -1:
					hotbar.swap_slots(from, to)
				else:
					hotbar.clear_slot(from)   # dragged off the bar: unassign
			elif hotbar.item_slots[from] != null:
				hotbar.try_cast(from)   # plain click uses a consumable
			_dragging = false
			get_viewport().set_input_as_handled()
			queue_redraw()


func _draw() -> void:
	if hotbar == null:
		return
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	var total_w := Hotbar.PER_BAR * SLOT + (Hotbar.PER_BAR - 1) * GAP
	var origin := Vector2(floori((screen.x - total_w) / 2.0), screen.y - SLOT - 3)

	for s in Hotbar.PER_BAR:
		var i := hotbar.active_bar * Hotbar.PER_BAR + s
		var r := Rect2(origin + Vector2(s * (SLOT + GAP), 0), Vector2(SLOT, SLOT))
		UiStyle.slot(self, r, i == hotbar.selected)
		var ab := hotbar.slots[i]
		var it := hotbar.item_slots[i]
		var lifted := _dragging and i == _press_slot
		if it and not lifted:
			var stock := hotbar.item_stock(i)
			draw_texture_rect_region(ITEM_ICONS, Rect2(r.position + Vector2.ONE, Vector2(ICON, ICON)),
					Rect2(it.icon_frame * 32, 0, 32, 32),
					Color(1, 1, 1, 1.0 if stock > 0 else 0.3))
			var icd := hotbar.inventory.cooldown_of(it) if hotbar.inventory else 0.0
			if icd > 0.0 and it.use_cooldown > 0.0:
				var h2 := ceili(ICON * icd / it.use_cooldown)
				draw_rect(Rect2(r.position + Vector2(1, ICON + 1 - h2), Vector2(ICON, h2)), Color(0, 0, 0, 0.65))
			HiFont.draw(self, r.position + Vector2(1.5, 1.5), HiFont.short_count(stock),
					UiStyle.TEXT if stock > 0 else Color("e03c3c"), 0.5)
		elif ab and not lifted:
			draw_texture_rect_region(ICONS, Rect2(r.position + Vector2.ONE, Vector2(ICON, ICON)),
					Rect2(ab.icon_index * 16, 0, 16, 16))
			# Cooldown: dark shade that shrinks as it recovers
			if hotbar.cooldown_left(i) > 0.0 and ab.cooldown > 0.0:
				var frac := hotbar.cooldown_left(i) / ab.cooldown
				var h := ceili(ICON * frac)
				draw_rect(Rect2(r.position + Vector2(1, ICON + 1 - h), Vector2(ICON, h)), Color(0, 0, 0, 0.65))
		var border := BORDER
		if hotbar.fail_flash[i] > 0.0:
			border = FAIL
		elif i == hotbar.selected:
			border = SELECTED
		if border != BORDER:
			draw_rect(r, border, false, 1.0)
		var key := Keybinds.label("hotbar_%d" % (s + 1), true)
		if key == "":
			key = Keybinds.label("bar%d_slot%d" % [hotbar.active_bar + 1, s + 1], true)
		if key != "":
			HiFont.draw(self, r.position + Vector2(SLOT - 0.5 - HiFont.text_width(key, 0.5), SLOT - 5.5), key, UiStyle.TEXT, 0.5)

	# bar switcher
	var ar := _arrows()
	for k in 2:
		var rr: Rect2 = ar[k]
		UiStyle.slot(self, rr, false)
		var cx := rr.position.x + rr.size.x / 2.0
		var cy := rr.position.y + rr.size.y / 2.0
		var d := -1.0 if k == 0 else 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 2.5, cy - d * 1.0), Vector2(cx + 2.5, cy - d * 1.0), Vector2(cx, cy + d * 1.5)]) if k == 1 else PackedVector2Array([Vector2(cx - 2.5, cy + 1.0), Vector2(cx + 2.5, cy + 1.0), Vector2(cx, cy - 1.5)]), UiStyle.GOLD)
	HiFont.draw(self, ar[2], str(hotbar.active_bar + 1), UiStyle.TEXT, 0.5)

	# Cast bar above the hotbar
	if hotbar.casting_slot != -1:
		var bar := Rect2(origin + Vector2(0, -6), Vector2(total_w, 4))
		draw_rect(bar, Color("1a1a22"))
		draw_rect(Rect2(bar.position + Vector2.ONE, Vector2((total_w - 2) * hotbar.cast_progress(), 2)), SELECTED)

	# The icon being dragged follows the mouse
	if _dragging and _press_slot != -1:
		var tex: Texture2D = null
		var region := Rect2()
		if hotbar.item_slots[_press_slot]:
			tex = ITEM_ICONS
			region = Rect2(hotbar.item_slots[_press_slot].icon_frame * 32, 0, 32, 32)
		elif hotbar.slots[_press_slot]:
			tex = ICONS
			region = Rect2(hotbar.slots[_press_slot].icon_index * 16, 0, 16, 16)
		if tex:
			draw_texture_rect_region(tex, Rect2(_mouse - Vector2(ICON, ICON) / 2.0, Vector2(ICON, ICON)), region, Color(1, 1, 1, 0.85))
