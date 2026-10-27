extends Control
## The inventory window (B, or P): Rex's MMO-style bag. A 5 x 6 grid of item slots, a column of
## worn gear on the right (weapon on top, then head, body, legs) and the purse under it all.
##
## Bag: drag an item onto another slot to swap them, onto a gear slot to wear it, onto the hotbar
## to put it there. Click food / a potion to use it, double-click gear to wear it, right-click for
## more. Gear column: drag a worn item into the bag (or double-click it) to take it off,
## right-click for more. Hover anything for its tooltip.

const COLS := 5
const ROWS := 6
const SLOT := 9.0
const ICON := 8.0        # 32 real pixels at 1280x720: the item sprites at their own size
const GAP := 0.5
const PAD := 1.0         # inside the sunken wells
const MARGIN := 2.0      # between the frame and the wells
const GRID_X := UiStyle.FRAME + MARGIN
const GRID_Y := UiStyle.FRAME + UiStyle.TITLE_H + 2.0
const GEAR_W := SLOT + PAD * 2
const GOLD_H := 8.0
const GEAR_ORDER := ["weapon", "helmet", "chest", "legs"]
const GEAR_HINT := {"weapon": "Weapon", "helmet": "Head", "chest": "Body", "legs": "Legs"}
const ITEM_ICONS := preload("res://art/items_small.png")   # classic 8x8 icons
const ITEM_SPRITES := preload("res://art/items.png")        # full 32x32 sprites
## true: full 32px item sprites. false: the old tiny 8px icons (flip back if the new ones look off).
const DETAILED_ICONS := true
const STAT_TEXT := Color("8fd0ff")

var inventory: Inventory:
	set(value):
		if inventory:
			inventory.changed.disconnect(queue_redraw)
		inventory = value
		if inventory:
			inventory.changed.connect(queue_redraw)
			var eq := inventory.get_parent().get_node_or_null("Equipment") as Equipment
			if eq:
				equipment = eq
		queue_redraw()

var equipment: Equipment:
	set(value):
		if equipment:
			equipment.changed.disconnect(queue_redraw)
		equipment = value
		if equipment:
			equipment.changed.connect(queue_redraw)
		queue_redraw()

var _hover := -1               ## bag slot under the mouse
var _hover_gear := ""          ## gear slot under the mouse
var _drag_from := -1           ## bag slot being dragged
var _drag_gear := ""           ## gear slot being dragged
var _dragging := false         ## only true once the mouse has actually moved after pressing
var _press_pos := Vector2.ZERO
const DRAG_START := 3.0        ## pixels of movement before an item starts to follow the mouse
var _mouse := Vector2.ZERO


func _ready() -> void:
	add_to_group("inventory_ui")
	CloseButton.attach(self)
	size = Vector2(_gear_well().end.x + MARGIN + UiStyle.FRAME, _gold_rect().end.y + MARGIN + UiStyle.FRAME)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2(screen.x - size.x - 4, screen.y - size.y - 4 - 17)   # sits above the nav bar
	mouse_filter = Control.MOUSE_FILTER_STOP


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") or event.is_action_pressed("paperdoll"):
		visible = not visible
		_drag_from = -1
		_drag_gear = ""
		get_viewport().set_input_as_handled()


## Size of one real screen pixel in this control's coordinates (UI layer is 2x).
func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


# ---- layout

func _grid_well() -> Rect2:
	return Rect2(GRID_X, GRID_Y, COLS * SLOT + (COLS - 1) * GAP + PAD * 2, ROWS * SLOT + (ROWS - 1) * GAP + PAD * 2)


func _gear_well() -> Rect2:
	var g := _grid_well()
	return Rect2(g.end.x + 1.5, g.position.y, GEAR_W, g.size.y)


func _gold_rect() -> Rect2:
	var g := _grid_well()
	return Rect2(g.position.x, g.end.y + 1.5, _gear_well().end.x - g.position.x, GOLD_H)


func _slot_pos(i: int) -> Vector2:
	return _grid_well().position + Vector2(PAD, PAD) + Vector2((i % COLS) * (SLOT + GAP), (i / COLS) * (SLOT + GAP))


## Gear slots spread evenly down the column: the weapon on top (with a line under it), then
## head, body, legs.
func _gear_pos(slot: String) -> Vector2:
	var w := _gear_well()
	var k := GEAR_ORDER.find(slot)
	var step := (w.size.y - PAD * 2 - SLOT) / float(GEAR_ORDER.size() - 1)
	return Vector2(w.position.x + PAD, w.position.y + PAD + roundf(k * step * 2.0) / 2.0)


func _slot_at(p: Vector2) -> int:
	for i in Inventory.SLOT_COUNT:
		if Rect2(_slot_pos(i), Vector2(SLOT, SLOT)).has_point(p):
			return i
	return -1


func _gear_at(p: Vector2) -> String:
	for s: String in GEAR_ORDER:
		if Rect2(_gear_pos(s), Vector2(SLOT, SLOT)).has_point(p):
			return s
	return ""


# ---- input

func _gui_input(event: InputEvent) -> void:
	if inventory == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _slot_at(_mouse)
		_hover_gear = _gear_at(_mouse)
		if (_drag_from != -1 or _drag_gear != "") and not _dragging and _mouse.distance_to(_press_pos) > DRAG_START:
			_dragging = true
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var gs := _gear_at(event.position)
		if gs != "":
			_gear_menu(gs)
		else:
			_bag_menu(_slot_at(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.position
		if event.pressed:
			_left_press(event)
		else:
			_left_release(event)
		queue_redraw()


func _bag_menu(slot: int) -> void:
	var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
	if slot == -1 or inventory.items[slot] == null or menu == null:
		return
	_drag_from = -1
	_hover = -1
	queue_redraw()
	var it := inventory.items[slot]
	var opts: Array = []
	if it.is_consumable():
		opts.append({"label": ("Drink " if it.heal_amount <= 0.0 else "Eat ") + it.display_name,
				"callback": inventory.use_slot.bind(slot)})
	if it.is_equippable() and equipment:
		opts.append({"label": "Equip " + it.title(), "callback": equipment.equip_from.bind(inventory, slot)})
	var anvil_ui := get_tree().get_first_node_in_group("enhance_ui") as EnhanceUI
	if anvil_ui and anvil_ui.is_open():
		opts.append({"label": "Place on anvil", "callback": anvil_ui.place.bind(it)})
	var shop_ui := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if shop_ui and shop_ui.is_open():
		var each := Trade.sell_price(shop_ui.shop, it)
		if each > 0:
			opts.append({"label": "Sell %s (%d)" % [it.title(), each], "callback": shop_ui.sell_item.bind(it, false)})
			if inventory.counts[slot] > 1:
				opts.append({"label": "Sell all (%d)" % [each * mini(inventory.count_of(it), Trade.MAX_SELL)],
						"callback": shop_ui.sell_item.bind(it, true)})
	opts.append({"label": "Drop " + it.title(), "callback": inventory.drop_slot.bind(slot)})
	menu.open_at_screen(get_viewport().get_mouse_position(), opts)


func _gear_menu(slot: String) -> void:
	var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
	var it := equipment.get_item(slot) if equipment else null
	if it == null or menu == null:
		return
	_hover_gear = ""
	queue_redraw()
	var opts := [{"label": "Unequip " + it.title(), "callback": equipment.unequip.bind(slot)}]
	var hb := equipment.get_parent().get_node_or_null("Hotbar") as Hotbar
	if it.is_hand_gear() and hb:
		opts.append({"label": "Put on hotbar", "callback": hb.add_item_to_free_slot.bind(it)})
	menu.open_at_screen(get_viewport().get_mouse_position(), opts)


func _left_press(event: InputEventMouseButton) -> void:
	var gs := _gear_at(_mouse)
	if gs != "":
		if equipment and equipment.get_item(gs) != null:
			if event.double_click:
				equipment.unequip(gs)          # double-click takes it off
				_drag_gear = ""
				return
			_drag_gear = gs
			_dragging = false
			_press_pos = _mouse
		return
	var i := _slot_at(_mouse)
	if i == -1 or inventory.items[i] == null:
		return
	var anvil := get_tree().get_first_node_in_group("enhance_ui") as EnhanceUI
	if anvil and anvil.is_open() and not event.double_click:
		_drag_from = -1
		anvil.place(inventory.items[i])   # at the anvil: a click puts it on the anvil
		return
	var shop_ui := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if shop_ui and shop_ui.is_open():
		_drag_from = -1
		shop_ui.show_value(inventory.items[i])   # shopping: a click just shows its value
		return
	if event.double_click and inventory.items[i].is_equippable() and equipment:
		_drag_from = -1
		equipment.equip_from(inventory, i)     # double-click wears it
		return
	_drag_from = i
	_dragging = false
	_press_pos = _mouse


func _left_release(event: InputEventMouseButton) -> void:
	var i := _slot_at(_mouse)
	var gs := _gear_at(_mouse)
	if _drag_gear != "":
		# a worn item let go over the bag: take it off
		if _dragging and gs == "" and _grid_well().has_point(_mouse):
			equipment.unequip(_drag_gear)
		_drag_gear = ""
		_dragging = false
		return
	if _drag_from != -1 and i == _drag_from and not _dragging:
		var it := inventory.items[i]
		if it != null and it.is_consumable():
			inventory.use_slot(i)   # plain click on food / a potion uses it
	elif _dragging and _drag_from != -1 and i != -1:
		inventory.swap(_drag_from, i)
	elif _dragging and _drag_from != -1 and gs != "":
		var it_g := inventory.items[_drag_from]
		if it_g != null and it_g.is_equippable() and equipment:
			equipment.equip_from(inventory, _drag_from)   # dropped on the gear column: wear it
	elif _dragging and _drag_from != -1 and i == -1:
		# let go outside the window: maybe onto the anvil or a hotbar slot
		var it2 := inventory.items[_drag_from]
		var anv := get_tree().get_first_node_in_group("enhance_ui") as EnhanceUI
		if it2 != null and anv and anv.is_open() and anv.get_rect().has_point(position + event.position):
			anv.place(it2)                  # dropped onto the anvil window
		else:
			var hb := get_tree().get_first_node_in_group("hotbar_ui")
			if it2 != null and (it2.is_consumable() or it2.is_hand_gear()) and hb != null:
				hb.drop_item_at(position + event.position, it2)
	_drag_from = -1
	_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		_hover_gear = ""
		queue_redraw()


# ---- drawing

func _draw() -> void:
	if inventory == null:
		return
	var px := _px()
	UiStyle.window(self, Rect2(Vector2.ZERO, size), "Inventory", px)
	# the bag
	UiStyle.well(self, _grid_well(), px)
	for i in Inventory.SLOT_COUNT:
		var p := _slot_pos(i)
		UiStyle.slot(self, Rect2(p, Vector2(SLOT, SLOT)), i == _hover, px)
		var item := inventory.items[i]
		if item == null or (_dragging and i == _drag_from):
			continue
		_draw_icon(item, inventory.counts[i], _icon_rect(p))
	# worn gear
	UiStyle.well(self, _gear_well(), px)
	for s: String in GEAR_ORDER:
		var p := _gear_pos(s)
		var r := Rect2(p, Vector2(SLOT, SLOT))
		UiStyle.slot(self, r, s == _hover_gear, px)
		if s == "weapon":           # the weapon slot gets a steel rim, like the reference
			draw_rect(r.grow(px), UiStyle.STEEL_MID, false, px)
		var it := equipment.get_item(s) if equipment else null
		if it and not (_dragging and _drag_gear == s):
			_draw_icon(it, 1, _icon_rect(p))
			if it.enhance > 0:
				HiFont.draw(self, p + Vector2(0.5, 0.5), "+%d" % it.enhance, UiStyle.GOLD, px, true)
		elif it == null:
			_draw_hint(s, r, px)
	var mid := floorf((_gear_pos("weapon").y + SLOT + _gear_pos("helmet").y) / 2.0)
	UiStyle.divider(self, Vector2(_gear_well().position.x + 1, mid), GEAR_W - 2, px)
	# the purse
	_draw_gold(px)
	# quantities drawn last so they can spill over neighbouring slots
	for i in Inventory.SLOT_COUNT:
		if inventory.items[i] != null and not (_dragging and i == _drag_from):
			_draw_count(_slot_pos(i), inventory.items[i], inventory.counts[i])
	# item being dragged follows the mouse, otherwise the tooltip
	if _dragging and _drag_from != -1 and inventory.items[_drag_from]:
		_draw_icon(inventory.items[_drag_from], inventory.counts[_drag_from], Rect2(_mouse - Vector2(ICON, ICON) / 2.0, Vector2(ICON, ICON)))
	elif _dragging and _drag_gear != "" and equipment and equipment.get_item(_drag_gear):
		_draw_icon(equipment.get_item(_drag_gear), 1, Rect2(_mouse - Vector2(ICON, ICON) / 2.0, Vector2(ICON, ICON)))
	elif _hover != -1 and inventory.items[_hover] != null:
		var item := inventory.items[_hover]
		var label := item.title()
		if item.stackable:
			label += " " + str(inventory.counts[_hover])
		_tooltip(label, item.stat_lines(), px)
	elif _hover_gear != "":
		var it := equipment.get_item(_hover_gear) if equipment else null
		if it:
			_tooltip(it.title(), it.stat_lines(), px)
		else:
			_tooltip(Equipment.SLOT_NAMES[_hover_gear], PackedStringArray(), px)


func _icon_rect(slot_pos: Vector2) -> Rect2:
	return Rect2(slot_pos + Vector2(SLOT - ICON, SLOT - ICON) / 2.0, Vector2(ICON, ICON))


## Empty gear slot: a faint label of what goes there.
func _draw_hint(slot: String, r: Rect2, px: float) -> void:
	var t: String = GEAR_HINT[slot]
	var s := px * 0.5
	var w := HiFont.text_width(t, s)
	HiFont.draw(self, (r.get_center() - Vector2(w, HiFont.H * s) / 2.0).snapped(Vector2(s, s)), t, Color("3c414b"), s)


func _draw_gold(px: float) -> void:
	var r := _gold_rect()
	UiStyle.well(self, r, px)
	# a little coin pile on the left, then "25,558,069 Gold" on the right
	var coins := Inventory.COINS
	var ic := Rect2(r.position + Vector2(1.0, (r.size.y - 6.0) / 2.0), Vector2(6, 6))
	if DETAILED_ICONS:
		draw_texture_rect_region(ITEM_SPRITES, ic, Rect2(coins.frame_for(maxi(inventory.gold, 1)) * 32, 0, 32, 32))
	var word := " Gold"
	var num := UiStyle.thousands(inventory.gold)
	var y := r.position.y + (r.size.y - HiFont.H * px) / 2.0
	var x := r.end.x - 2.0 - HiFont.text_width(word, px)
	HiFont.draw(self, Vector2(x, y).snapped(Vector2(px, px)), word, UiStyle.TEXT, px)
	x -= HiFont.text_width(num, px) + px
	HiFont.draw(self, Vector2(x, y).snapped(Vector2(px, px)), num, UiStyle.MONEY, px)


func _tooltip(label: String, lines: PackedStringArray, px: float) -> void:
	var w := HiFont.text_width(label, px)
	for l in lines:
		w = maxf(w, HiFont.text_width(l, px))
	w += 14 * px
	var lh := (HiFont.H + 3) * px
	var h := HiFont.H * px + 14 * px + lines.size() * lh
	var tp := Vector2(_mouse.x - w - 4, _mouse.y - h / 2.0).snapped(Vector2(px, px))
	UiStyle.panel(self, Rect2(tp, Vector2(w, h)), px)
	HiFont.draw(self, tp + Vector2(7, 7) * px, label, UiStyle.GOLD, px)
	for k in lines.size():
		HiFont.draw(self, tp + Vector2(7 * px, 7 * px + (k + 1) * lh), lines[k], STAT_TEXT, px)


## Stack size (or +level) in the slot's top-left corner, small white text like the reference.
func _draw_count(p: Vector2, item: Item, count: int) -> void:
	if item.enhance > 0:                      # enhanced gear: its +level in the corner
		HiFont.draw(self, p + Vector2(0.5, 0.5), "+%d" % item.enhance, UiStyle.GOLD, _px(), true)
		return
	if item.stackable and count > 1:
		var text := HiFont.short_count(count)
		var color := Color.WHITE
		if count >= 1000000:
			color = Color("40e070")            # green: millions
		elif count >= 1000:
			color = Color("f0d040")            # yellow: thousands
		HiFont.draw(self, p + Vector2(0.5, 0.5), text, color, _px(), true)


func close_ui() -> void:
	visible = false


## One item icon: the full sprite, or the old tiny icon (see DETAILED_ICONS).
func _draw_icon(item: Item, count: int, r: Rect2) -> void:
	var f := item.frame_for(count)
	if DETAILED_ICONS:
		draw_texture_rect_region(ITEM_SPRITES, r, Rect2(f * 32, 0, 32, 32))
	else:
		draw_texture_rect_region(ITEM_ICONS, r, Rect2(f * 8, 0, 8, 8))
