class_name QuestMenu
extends Control
## The quest log (press J). Lists your running quests; click one to track it: the
## map and the minimap then blink where it leads you.

const W := 250
const PAD := 6
const HEADER := 14
const ROW_H := 26
const ROW_GAP := 3

var _hover := -1
var _rows: Array = []


func _ready() -> void:
	CloseButton.attach(self)
	add_to_group("quest_menu")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_rows = Quests.active()
	var rows := maxi(_rows.size(), 1)
	size = Vector2(W, HEADER + rows * (ROW_H + ROW_GAP) + 18 + PAD)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = ((screen - size) / 2.0).floor()
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		var now := Quests.active()
		if now.size() != _rows.size():
			open()
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_J:
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _row_rect(i: int) -> Rect2:
	return Rect2(PAD, HEADER + i * (ROW_H + ROW_GAP), W - PAD * 2, ROW_H)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in _rows.size():
			if _row_rect(i).has_point(event.position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _rows.size():
			if _row_rect(i).has_point(event.position):
				Quests.set_tracked(_rows[i]["id"])
				queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(PAD, 4), "QUEST LOG", UiStyle.GOLD, px)
	HiFont.draw(self, Vector2(size.x - PAD - HiFont.text_width("J TO CLOSE", px), 4), "J TO CLOSE", UiStyle.TEXT_DIM, px)
	draw_rect(Rect2(PAD, HEADER - 3, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	if _rows.is_empty():
		HiFont.draw(self, Vector2(PAD + 4, HEADER + 6), "No quests yet. Try the notice board!", UiStyle.TEXT_DIM, px)
	var tracked := Quests.tracked_id()
	for i in _rows.size():
		var q: Dictionary = _rows[i]
		var r := _row_rect(i)
		UiStyle.slot(self, r, i == _hover)
		var st := Quests.state_of(q["id"])
		var n := Quests.progress_of(q["id"])
		HiFont.draw(self, r.position + Vector2(5, 4), String(q["title"]).to_upper(), UiStyle.GOLD, px)
		var line := "Return to %s" % ("Luck" if q.get("npc", false) else "the notice board") if st == 2 \
				else "Slay %d %s   %d/%d" % [q["count"], q["name"], n, q["count"]]
		HiFont.draw(self, r.position + Vector2(5, 14), line, Color("40e070") if st == 2 else UiStyle.TEXT, px)
		var label := "TRACKING" if q["id"] == tracked else "TRACK"
		var col := Color("ffe066") if q["id"] == tracked else UiStyle.TEXT_DIM
		HiFont.draw(self, Vector2(r.end.x - 5 - HiFont.text_width(label, px), r.position.y + 4), label, col, px)
	HiFont.draw(self, Vector2(PAD, size.y - 13), "Click a quest to track it on the map", UiStyle.TEXT_DIM, px)


func close_ui() -> void:
	close()
