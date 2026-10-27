class_name DialogueUI
extends Control
## A talking box at the bottom of the screen. The NPC supplies get_dialogue() and choose().
## Click a button to answer. F / Esc / walking away closes it.

const W := 176
const PAD := 6
const LINE_H := 8
const BTN_H := 12

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
	size = Vector2(W, 16 + lines.size() * LINE_H + 8 + BTN_H + (_btn_rows(d) - 1) * (BTN_H + 3) + PAD)
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


## The buttons, right-aligned along the bottom; too many for one row wrap onto more rows.
func _btn_rects() -> Array:
	var px := _px()
	var buttons: Array = _dlg.get("buttons", [])
	var rows: Array = [[]]          # each row: the button indices in it
	var used := 0.0
	for i in buttons.size():
		var w := _btn_w(String(buttons[i]["label"]), px)
		if not rows[-1].is_empty() and used + 4 + w > W - PAD * 2:
			rows.append([])
			used = 0.0
		used += (4 if not rows[-1].is_empty() else 0) + w
		rows[-1].append(i)
	var out: Array = []
	out.resize(buttons.size())
	for r in rows.size():
		var y := size.y - PAD - BTN_H - (rows.size() - 1 - r) * (BTN_H + 3)
		var x := size.x - PAD
		for k in range(rows[r].size() - 1, -1, -1):
			var i: int = rows[r][k]
			var w := _btn_w(String(buttons[i]["label"]), px)
			x -= w
			out[i] = Rect2(x, y, w, BTN_H)
			x -= 4
	return out


func _btn_w(label: String, px: float) -> float:
	return HiFont.text_width(label, px) + 12


## How many rows of buttons there will be.
func _btn_rows(d: Dictionary) -> int:
	var px := _px()
	var rows := 1
	var used := 0.0
	for b in d.get("buttons", []):
		var w := _btn_w(String(b["label"]), px)
		if used > 0.0 and used + 4 + w > W - PAD * 2:
			rows += 1
			used = 0.0
		used += (4 if used > 0.0 else 0) + w
	return rows


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
	var title := String(_npc.display_name) if _npc != null else ""
	UiStyle.window(self, Rect2(Vector2.ZERO, size), title, px)
	var y := 16.0
	for l in _wrap(String(_dlg["text"])):
		HiFont.draw(self, Vector2(PAD, y), l, UiStyle.TEXT, px)
		y += LINE_H
	var rects := _btn_rects()
	for i in rects.size():
		var label := String(_dlg["buttons"][i]["label"])
		UiStyle.button(self, rects[i], label, 1 if i == _hover else 0, px, Color("ffe066") if i == 0 else Color(0, 0, 0, 0))


func close_ui() -> void:
	close()
