class_name ShopUI
extends Control
## Shop window: a 6 wide x 3 tall grid (18 slots). Click an item to buy it.
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


func _ready() -> void:
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
	_message = "Click an item to buy it"
	_message_color = Color("b0a890")
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


func _item_at(i: int) -> Item:
	if shop == null or i < 0 or i >= shop.items.size():
		return null
	return shop.items[i]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _slot_at(event.position)
		if _item_at(i) != null:
			_buy(_item_at(i))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()


func _buy(item: Item) -> void:
	var r := Trade.buy(_inv, item)
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
	draw_rect(Rect2(PAD, HEADER - 3, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	for i in COLS * ROWS:
		var p := _slot_pos(i)
		UiStyle.slot(self, Rect2(p, Vector2(SLOT, SLOT)), i == _hover)
		var item := _item_at(i)
		if item:
			draw_texture_rect_region(ICONS, Rect2(p + Vector2(2, 1), Vector2(16, 16)),
					Rect2(item.frame_for(1) * 32, 0, 32, 32))
			var price := str(item.value)
			HiFont.draw(self, p + Vector2(SLOT - 2 - HiFont.text_width(price, px), SLOT - 5), price, Color("f0d040"), px)
	var fy := HEADER + ROWS * SLOT + (ROWS - 1) * GAP + 4
	var hovered := _item_at(_hover)
	var line := _message
	var col := _message_color
	if hovered:
		line = "%s  %d coins" % [hovered.display_name, hovered.value]
		col = Color.WHITE
	HiFont.draw(self, Vector2(PAD, fy), line, col, px)
	if hovered and not hovered.stat_lines().is_empty():
		HiFont.draw(self, Vector2(PAD, fy + 9), "  ".join(hovered.stat_lines()), Color("8fd0ff"), px)
	elif _inv:
		HiFont.draw(self, Vector2(PAD, fy + 9), "Your coins  %d" % _inv.count_of(COINS), Color("f0d040"), px)
