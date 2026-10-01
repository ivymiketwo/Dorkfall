class_name QuestUI
extends Control
## Notice board window: one row per kill quest. Click a row to accept it, hand it in
## when it's done, or abandon it while it's running. F / Esc / walking away closes it.

const PAD := 6
const HEADER := 14
const ROW_H := 30
const ROW_GAP := 3
const W := 232

var _board: Node2D
var _player: Node2D
var _hover := -1
var _message := ""
var _message_color := Color("b0a890")


func _ready() -> void:
	CloseButton.attach(self)
	add_to_group("quest_ui")
	size = Vector2(W, HEADER + Quests.board_list().size() * (ROW_H + ROW_GAP) + 20 + PAD)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = ((screen - size) / 2.0).floor()
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func open(board: Node2D, player: Node2D) -> void:
	_board = board
	_player = player
	_message = "Click a quest.  Pays 10 coins + 10 XP per Mangyang, 12 per Skeleton"
	_message_color = Color("b0a890")
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		if not is_instance_valid(_board) or not is_instance_valid(_player) \
				or _board.global_position.distance_to(_player.global_position) > 70.0:
			close()
		else:
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _row_rect(i: int) -> Rect2:
	return Rect2(PAD, HEADER + i * (ROW_H + ROW_GAP), W - PAD * 2, ROW_H)


func _row_at(p: Vector2) -> int:
	for i in Quests.board_list().size():
		if _row_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _row_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _row_at(event.position)
		if i >= 0:
			_click(Quests.board_list()[i])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()


func _click(q: Dictionary) -> void:
	match Quests.state_of(q["id"]):
		0:
			Quests.accept(q["id"])
			_say("Accepted: %s" % q["title"], Color("40e070"))
		1:
			Quests.abandon(q["id"])
			_say("Abandoned: %s" % q["title"], Color("e0a040"))
		2:
			var r := Quests.turn_in(q["id"], _player)
			_say(r["message"], Color("40e070") if r["ok"] else Color("e03c3c"))


func _say(text: String, color: Color) -> void:
	_message = text
	_message_color = color
	queue_redraw()


func _draw() -> void:
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(PAD, 4), "NOTICE BOARD", UiStyle.GOLD, px)
	draw_rect(Rect2(PAD, HEADER - 3, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	for i in Quests.board_list().size():
		var q: Dictionary = Quests.board_list()[i]
		var r := _row_rect(i)
		UiStyle.slot(self, r, i == _hover)
		var st := Quests.state_of(q["id"])
		HiFont.draw(self, r.position + Vector2(5, 4), String(q["title"]).to_upper(), UiStyle.GOLD, px)
		HiFont.draw(self, r.position + Vector2(5, 13), "Slay %d %s" % [q["count"], q["name"]], UiStyle.TEXT, px)
		var n := Quests.progress_of(q["id"])
		var frac := float(n) / float(q["count"])
		UiStyle.bar(self, Rect2(r.position + Vector2(5, 22), Vector2(100, 4)), frac if st != 0 else 0.0, Color("9a6cf0"))
		var label := "ACCEPT"
		var col := Color("40e070")
		if st == 1:
			label = "%d/%d  ABANDON" % [n, q["count"]]
			col = Color("e0a040")
		elif st == 2:
			label = "TURN IN"
			col = Color("ffe066")
		HiFont.draw(self, Vector2(r.end.x - 6 - HiFont.text_width(label, px), r.position.y + 5), label, col, px)
		var reward := "%d COINS  %d XP" % [Quests.reward_of(q), Quests.reward_of(q)]
		HiFont.draw(self, Vector2(r.end.x - 6 - HiFont.text_width(reward, px), r.position.y + 20), reward, Color("f0d040"), px)
	HiFont.draw(self, Vector2(PAD, size.y - 14), _message, _message_color, px)


func close_ui() -> void:
	close()
