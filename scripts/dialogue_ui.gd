class_name DialogueUI
extends Control
## A talking box at the bottom of the screen. The NPC supplies get_dialogue() and choose().
## Click a button to answer. F / Esc / walking away closes it.

const W := 196
const PAD := 7
const LINE_H := 8
const BTN_H := 13

var _npc: Node2D
var _player: Node2D
var _dlg := {}
var _hover := -1


func _ready() -> void:
	CloseButton.attach(self)
	add_to_group("dialogue_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func open(npc: Node2D, player: Node2D) -> void:
	_npc = npc
	_player = player
	_show(npc.get_dialogue(player))
	visible = true


func close() -> void:
	visible = false


func _show(d: Dictionary) -> void:
	if d.is_empty():
		close()
		return
	_dlg = d
	var lines := _wrap(String(d["text"]))
	size = Vector2(W, 14 + lines.size() * LINE_H + 8 + BTN_H + PAD)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2(floorf((screen.x - W) / 2.0), floorf(screen.y - size.y - 34))
	queue_redraw()


func _wrap(text: String) -> Array:
	var px := _px()
	var out: Array = []
	var line := ""
	for word in text.split(" "):
		var t := word if line == "" else line + " " + word
		if HiFont.text_width(t, px) > W - PAD * 2 and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out


func _process(_delta: float) -> void:
	if visible and (not is_instance_valid(_npc) or not is_instance_valid(_player)
			or _npc.global_position.distance_to(_player.global_position) > 70.0):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _btn_rects() -> Array:
	var out: Array = []
	var px := _px()
	var x := size.x - PAD
	var y := size.y - PAD - BTN_H
	var buttons: Array = _dlg.get("buttons", [])
	for i in range(buttons.size() - 1, -1, -1):
		var w := HiFont.text_width(String(buttons[i]["label"]), px) + 12
		x -= w
		out.push_front(Rect2(x, y, w, BTN_H))
		x -= 4
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		var rects := _btn_rects()
		for i in rects.size():
			if rects[i].has_point(event.position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rects := _btn_rects()
		for i in rects.size():
			if rects[i].has_point(event.position):
				var id := String(_dlg["buttons"][i]["id"])
				if id == "close":
					close()
				else:
					_show(_npc.choose(id, _player))
				return


func _draw() -> void:
	if _dlg.is_empty():
		return
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	var title := String(_npc.display_name).to_upper() if _npc != null else ""
	HiFont.draw(self, Vector2(PAD, 4), title, UiStyle.GOLD, px)
	draw_rect(Rect2(PAD, 11, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	var y := 15.0
	for l in _wrap(String(_dlg["text"])):
		HiFont.draw(self, Vector2(PAD, y), l, UiStyle.TEXT, px)
		y += LINE_H
	var rects := _btn_rects()
	for i in rects.size():
		UiStyle.slot(self, rects[i], i == _hover)
		var label := String(_dlg["buttons"][i]["label"])
		HiFont.draw(self, rects[i].position + Vector2(6, 4), label, Color("ffe066") if i == 0 else UiStyle.TEXT, px)


func close_ui() -> void:
	close()
