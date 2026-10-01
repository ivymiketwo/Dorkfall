extends Control
## RuneScape-style 4x7 inventory panel. Press B to show/hide.
## Drag an item onto another slot to swap them. Hover for a name tooltip.

const COLS := 4
const ROWS := 7
const SLOT := 10
const ICON := 8     # icons come from items_small.png (8x8 frames)
const GAP := 0
const PAD := 3
const ITEM_ICONS := preload("res://art/items_small.png")

const PANEL_BG := Color("3b3226")
const PANEL_BORDER := Color("1a140e")
const PANEL_LIGHT := Color("5c4d3a")
const SLOT_BG := Color("1a150f")
const SLOT_EDGE := Color("4d4130")
const SLOT_HOVER := Color("3d3324")

var inventory: Inventory:
	set(value):
		if inventory:
			inventory.changed.disconnect(queue_redraw)
		inventory = value
		if inventory:
			inventory.changed.connect(queue_redraw)
		queue_redraw()

var _hover := -1
var _drag_from := -1
var _dragging := false          ## only true once the mouse has actually moved after pressing
var _press_pos := Vector2.ZERO
const DRAG_START := 3.0        ## pixels of movement before an item starts to follow the mouse
var _mouse := Vector2.ZERO


func _ready() -> void:
	size = Vector2(COLS * SLOT + (COLS - 1) * GAP + PAD * 2, ROWS * SLOT + (ROWS - 1) * GAP + PAD * 2)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2(screen.x - size.x - 4, screen.y - size.y - 4 - 17)   # sits above the nav bar
	mouse_filter = Control.MOUSE_FILTER_STOP


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		visible = not visible
		_drag_from = -1
		get_viewport().set_input_as_handled()


## Size of one real screen pixel in this control's coordinates (UI layer is 2x).
func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func _slot_at(p: Vector2) -> int:
	var q := p - Vector2(PAD, PAD)
	if q.x < 0 or q.y < 0:
		return -1
	var col := floori(q.x / (SLOT + GAP))
	var row := floori(q.y / (SLOT + GAP))
	if col >= COLS or row >= ROWS:
		return -1
	if fmod(q.x, SLOT + GAP) >= SLOT or fmod(q.y, SLOT + GAP) >= SLOT:
		return -1
	return row * COLS + col


func _slot_pos(i: int) -> Vector2:
	return Vector2(PAD + (i % COLS) * (SLOT + GAP), PAD + (i / COLS) * (SLOT + GAP))


func _gui_input(event: InputEvent) -> void:
	if inventory == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _slot_at(_mouse)
		if _drag_from != -1 and not _dragging and _mouse.distance_to(_press_pos) > DRAG_START:
			_dragging = true
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var slot := _slot_at(event.position)
		var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
		if slot != -1 and inventory.items[slot] != null and menu:
			_drag_from = -1
			_hover = -1
			queue_redraw()
			var opts: Array = []
			if inventory.items[slot].is_consumable():
				opts.append({"label": ("Drink " if inventory.items[slot].heal_amount <= 0.0 else "Eat ") + inventory.items[slot].display_name,
						"callback": inventory.use_slot.bind(slot)})
			if inventory.items[slot].is_equippable():
				var eq := inventory.get_parent().get_node_or_null("Equipment") as Equipment
				if eq:
					opts.append({"label": "Equip " + inventory.items[slot].display_name,
							"callback": eq.equip_from.bind(inventory, slot)})
			opts.append({"label": "Drop " + inventory.items[slot].display_name,
					"callback": inventory.drop_slot.bind(slot)})
			menu.open_at_screen(get_viewport().get_mouse_position(), opts)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.position
		var i := _slot_at(_mouse)
		if event.pressed:
			if event.double_click and i != -1 and inventory.items[i] != null and inventory.items[i].is_equippable():
				var eq := inventory.get_parent().get_node_or_null("Equipment") as Equipment
				if eq:
					_drag_from = -1
					eq.equip_from(inventory, i)     # double-click wears it
					queue_redraw()
					return
			if i != -1 and inventory.items[i] != null:
				_drag_from = i
				_dragging = false
				_press_pos = _mouse
		else:
			if _drag_from != -1 and i == _drag_from:
				var it := inventory.items[i]
				if it != null and it.is_consumable():
					inventory.use_slot(i)   # plain click on food / a potion uses it
			elif _dragging and _drag_from != -1 and i != -1:
				inventory.swap(_drag_from, i)
			elif _dragging and _drag_from != -1 and i == -1:
				# let go outside the bag: maybe onto a hotbar slot
				var it2 := inventory.items[_drag_from]
				var hb := get_tree().get_first_node_in_group("hotbar_ui")
				if it2 != null and it2.is_consumable() and hb != null:
					hb.drop_item_at(position + event.position, it2)
			_drag_from = -1
			_dragging = false
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	if inventory == null:
		return
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	for i in Inventory.SLOT_COUNT:
		var p := _slot_pos(i)
		UiStyle.slot(self, Rect2(p, Vector2(SLOT, SLOT)), i == _hover)
		var item := inventory.items[i]
		if item == null or (_dragging and i == _drag_from):
			continue
		draw_texture_rect_region(ITEM_ICONS, Rect2(p + Vector2.ONE, Vector2(ICON, ICON)),
				Rect2(item.frame_for(inventory.counts[i]) * ICON, 0, ICON, ICON))
	# quantities drawn last so they can spill over neighbouring slots
	for i in Inventory.SLOT_COUNT:
		if inventory.items[i] != null and not (_dragging and i == _drag_from):
			_draw_count(_slot_pos(i), inventory.items[i], inventory.counts[i])
	# item being dragged follows the mouse
	if _drag_from != -1 and _dragging:
		var item := inventory.items[_drag_from]
		if item:
			draw_texture_rect_region(ITEM_ICONS, Rect2(_mouse - Vector2(4, 4), Vector2(ICON, ICON)),
					Rect2(item.frame_for(inventory.counts[_drag_from]) * ICON, 0, ICON, ICON))
	# tooltip
	elif _hover != -1 and inventory.items[_hover] != null:
		var item := inventory.items[_hover]
		var label := item.display_name
		if item.stackable:
			label += " " + str(inventory.counts[_hover])
		var px := _px()
		var stats_txt := item.stat_lines()
		var w := HiFont.text_width(label, px)
		for l in stats_txt:
			w = maxf(w, HiFont.text_width(l, px))
		w += 6 * px
		var lh := (HiFont.H + 3) * px
		var h := HiFont.H * px + 6 * px + stats_txt.size() * lh
		var tp := Vector2(_mouse.x - w - 4, _mouse.y - h / 2.0).snapped(Vector2(px, px))
		UiStyle.panel(self, Rect2(tp, Vector2(w, h)))
		HiFont.draw(self, tp + Vector2(3, 3) * px, label, UiStyle.GOLD, px)
		for k in stats_txt.size():
			HiFont.draw(self, tp + Vector2(3 * px, 3 * px + (k + 1) * lh), stats_txt[k], Color("8fd0ff"), px)


func _draw_count(p: Vector2, item: Item, count: int) -> void:
	if item.stackable and count > 1:
		var text := HiFont.short_count(count)
		var color := Color("f0d040")            # yellow: exact number
		if count >= 1000000:
			color = Color("40e070")            # green: millions
		elif count >= 1000:
			color = Color.WHITE                # white: thousands
		HiFont.draw(self, p + Vector2(0.5, 0.5), text, color, _px(), true)

