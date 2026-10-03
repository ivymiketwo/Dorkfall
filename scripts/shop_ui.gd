class_name ShopUI
extends Control
## Shop window: a 6 wide x 3 tall grid (18 slots). Click an item to buy it.
## Shops that buy things get BUY / SELL tabs: on SELL, click sells one, Shift+click sells all.
## Opened by pressing F next to a shopkeeper; closes with F, Esc, or by walking away.

const COLS := 6
const ROWS := 3
const SLOT := 20
const GAP := 2
const PAD := 6
const HEADER := 14
const FOOTER := 22
const ICONS := preload("res://art/items.png")   # 32px icons, drawn 1:1 on screen
const COINS := preload("res://items/coins.tres")

var shop: Shop
var _npc: Node2D
var _player: Node2D
var _inv: Inventory
var _hover := -1
var _message := ""
var _message_color := Color.WHITE
var _selling := false     # which tab is showing


func _ready() -> void:
	CloseButton.attach(self)
	add_to_group("shop_ui")
	size = Vector2(COLS * SLOT + (COLS - 1) * GAP + PAD * 2, HEADER + ROWS * SLOT + (ROWS - 1) * GAP + FOOTER + PAD)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = ((screen - size) / 2.0).floor()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func open(new_shop: Shop, npc: Node2D, player: Node2D) -> void:
	shop = new_shop
	_npc = npc
	_player = player
	if _inv:
		_inv.changed.disconnect(queue_redraw)
	_inv = player.get_node("Inventory")
	_inv.changed.connect(queue_redraw)
	_selling = false
	_hint()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(_npc) or not is_instance_valid(_player)
			or _npc.global_position.distance_to(_player.global_position) > 70.0):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _slot_pos(i: int) -> Vector2:
	return Vector2(PAD + (i % COLS) * (SLOT + GAP), HEADER + (i / COLS) * (SLOT + GAP))


func _slot_at(p: Vector2) -> int:
	for i in COLS * ROWS:
		if Rect2(_slot_pos(i), Vector2(SLOT, SLOT)).has_point(p):
			return i
	return -1


func _hint() -> void:
	_message = "Click sells one, Shift+click sells all" if _selling else "Click an item to buy it"
	_message_color = Color("b0a890")


## What the grid shows: the shop's stock, or (on SELL) the things you carry that it buys.
func _listing() -> Array[Item]:
	var out: Array[Item] = []
	if shop == null:
		return out
	if not _selling:
		return shop.items
	for it in shop.buys:
		if it != null and _inv != null and _inv.count_of(it) > 0 and Trade.sell_price(shop, it) > 0:
			out.append(it)
	return out


func _item_at(i: int) -> Item:
	var list := _listing()
	if i < 0 or i >= list.size():
		return null
	return list[i]


func _has_tabs() -> bool:
	return shop != null and not shop.buys.is_empty()


func _tab_rect(sell: bool) -> Rect2:
	var w := 24.0
	return Rect2(size.x - PAD - 14 - (w if not sell else 0.0) - w - (2.0 if not sell else 0.0), 2, w, 9)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _has_tabs():
			for sell in [false, true]:
				if _tab_rect(sell).has_point(event.position):
					_selling = sell
					_hint()
					queue_redraw()
					return
		var i := _slot_at(event.position)
		if _item_at(i) != null:
			if _selling:
				_sell(_item_at(i), event.shift_pressed)
			else:
				_buy(_item_at(i))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()


func _buy(item: Item) -> void:
	var r := Trade.buy(_inv, item)
	_say(r["message"], Color("40e070") if r["ok"] else Color("e03c3c"))


func _sell(item: Item, all: bool) -> void:
	var r := Trade.sell(_inv, shop, item, Trade.MAX_SELL if all else 1)
	_say(r["message"], Color("40e070") if r["ok"] else Color("e03c3c"))


func _say(text: String, color: Color) -> void:
	_message = text
	_message_color = color
	queue_redraw()


func _draw() -> void:
	if shop == null:
		return
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(PAD, 4), shop.title, UiStyle.GOLD, px)
	if _has_tabs():
		for sell in [false, true]:
			var tr := _tab_rect(sell)
			var on: bool = sell == _selling
			draw_rect(tr, UiStyle.BRONZE_MID if on else Color(0, 0, 0, 0.35))
			var label := "SELL" if sell else "BUY"
			HiFont.draw(self, tr.position + Vector2((tr.size.x - HiFont.text_width(label, px)) / 2.0, 2), label,
					UiStyle.GOLD if on else Color("b0a890"), px)
	draw_rect(Rect2(PAD, HEADER - 3, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	for i in COLS * ROWS:
		var p := _slot_pos(i)
		UiStyle.slot(self, Rect2(p, Vector2(SLOT, SLOT)), i == _hover)
		var item := _item_at(i)
		if item:
			draw_texture_rect_region(ICONS, Rect2(p + Vector2(2, 1), Vector2(16, 16)),
					Rect2(item.frame_for(1) * 32, 0, 32, 32))
			var price := str(Trade.sell_price(shop, item) if _selling else item.value)
			if _selling:
				HiFont.draw(self, p + Vector2(2, 1), str(_inv.count_of(item)), Color.WHITE, px)
			HiFont.draw(self, p + Vector2(SLOT - 2 - HiFont.text_width(price, px), SLOT - 5), price, Color("f0d040"), px)
	var fy := HEADER + ROWS * SLOT + (ROWS - 1) * GAP + 4
	var hovered := _item_at(_hover)
	var line := _message
	var col := _message_color
	if hovered:
		line = "%s  %d coins" % [hovered.display_name, Trade.sell_price(shop, hovered) if _selling else hovered.value]
		col = Color.WHITE
	HiFont.draw(self, Vector2(PAD, fy), line, col, px)
	if hovered and not hovered.stat_lines().is_empty():
		HiFont.draw(self, Vector2(PAD, fy + 9), "  ".join(hovered.stat_lines()), Color("8fd0ff"), px)
	elif _inv:
		HiFont.draw(self, Vector2(PAD, fy + 9), "Your coins  %d" % _inv.count_of(COINS), Color("f0d040"), px)


func close_ui() -> void:
	close()
