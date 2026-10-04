extends Control
## Esc menu: Resume, Sound, Hotkeys, Quit Game. The game is paused while it is open.
## Hotkeys lists every rebindable action: click one, then press the new key
## (Esc cancels, Backspace / Delete clears it).

const BTN_W := 90.0
const BTN_H := 14.0
const ROW_H := 11.0

var _mode := "menu"            ## "menu", "keys" or "sound"
var _drag := ""                ## slider being dragged: "music" / "sfx"
var _hover := ""               ## hovered button id / "row:N"
var _listening := ""           ## action waiting for a key press
var _scroll := 0.0
var _entries: Array = []       ## flat rows: {header} or {action,label}
var _mouse := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2.ZERO
	size = screen
	_build_entries()


func _build_entries() -> void:
	_entries.clear()
	var last := ""
	for e in Keybinds.entries():
		if e[2] != last:
			last = e[2]
			_entries.append({"header": last})
		_entries.append({"action": e[0], "label": e[1]})


func is_open() -> bool:
	return visible


func open() -> void:
	_mode = "menu"
	_listening = ""
	visible = true
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	visible = false
	_listening = ""
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if visible or not event.is_action_pressed("ui_cancel"):
		return
	var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
	if menu != null and menu.is_open():
		return
	# Esc closes open windows one at a time (front-most first) before the escape menu opens
	if CloseButton.close_top(get_tree()):
		get_viewport().set_input_as_handled()
		return
	open()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var code: int = event.physical_keycode
	if _listening != "":
		if code == KEY_ESCAPE:
			_listening = ""
		elif code == KEY_BACKSPACE or code == KEY_DELETE:
			Keybinds.bind(_listening, [])
			_listening = ""
		elif code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			return     # wait for the real key
		else:
			Keybinds.bind(_listening, [code, event.shift_pressed, event.ctrl_pressed, event.alt_pressed])
			_listening = ""
	elif code == KEY_ESCAPE:
		if _mode == "keys" or _mode == "sound":
			_mode = "menu"
			Sound.save()
		else:
			close()
	queue_redraw()


# ---------------------------------------------------------------- layout
func _menu_rect() -> Rect2:
	var s := Vector2(BTN_W + 20, 96)
	return Rect2(((size - s) / 2.0).floor(), s)


func _menu_button(i: int) -> Rect2:
	var m := _menu_rect()
	return Rect2(m.position + Vector2(10, 22 + i * (BTN_H + 4)), Vector2(BTN_W, BTN_H))


func _keys_rect() -> Rect2:
	var s := Vector2(236, 156)
	return Rect2(((size - s) / 2.0).floor(), s)


func _sound_rect() -> Rect2:
	var s := Vector2(176, 92)
	return Rect2(((size - s) / 2.0).floor(), s)


func _slider_rect(i: int) -> Rect2:    # 0 = music, 1 = effects
	var r := _sound_rect()
	return Rect2(r.position + Vector2(12, 34 + i * 22), Vector2(r.size.x - 24, 6))


func _sound_back() -> Rect2:
	var r := _sound_rect()
	return Rect2(r.position + Vector2((r.size.x - 70) / 2.0, r.size.y - 22), Vector2(70, 16))


func _slider_value(i: int, x: float) -> float:
	var s := _slider_rect(i)
	return clampf((x - s.position.x) / s.size.x, 0.0, 1.0)


func _list_rect() -> Rect2:
	var k := _keys_rect()
	return Rect2(k.position + Vector2(6, 18), Vector2(k.size.x - 12, 108))


func _max_scroll() -> float:
	return maxf(_entries.size() * ROW_H - _list_rect().size.y, 0.0)


func _key_button(i: int) -> Rect2:    # 0 = reset, 1 = back
	var k := _keys_rect()
	return Rect2(k.position + Vector2(6 + i * 118, k.size.y - 22), Vector2(112, 16))


func _row_rect(i: int) -> Rect2:
	var l := _list_rect()
	return Rect2(l.position + Vector2(0, i * ROW_H - _scroll), Vector2(l.size.x, ROW_H))


# ---------------------------------------------------------------- mouse
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _drag != "":
			_set_slider(_drag, _mouse.x)
		_update_hover()
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag != "":
			_drag = ""
			Sound.save()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _mode == "keys":
				_scroll = clampf(_scroll + (-ROW_H if event.button_index == MOUSE_BUTTON_WHEEL_UP else ROW_H) * 2.0, 0.0, _max_scroll())
				_update_hover()
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.position)
	accept_event()


func _set_slider(which: String, x: float) -> void:
	if which == "music":
		Sound.set_music_volume(_slider_value(0, x))
	else:
		Sound.set_sfx_volume(_slider_value(1, x))


func _update_hover() -> void:
	_hover = ""
	if _mode == "menu":
		for i in 4:
			if _menu_button(i).has_point(_mouse):
				_hover = "m%d" % i
	elif _mode == "sound":
		if _sound_back().has_point(_mouse):
			_hover = "sb"
		for i in 2:
			if _slider_rect(i).grow(4).has_point(_mouse):
				_hover = "s%d" % i
	else:
		for i in 2:
			if _key_button(i).has_point(_mouse):
				_hover = "k%d" % i
		if _list_rect().has_point(_mouse):
			for i in _entries.size():
				if _entries[i].has("action") and _row_rect(i).has_point(_mouse):
					_hover = "row:%d" % i


func _click(p: Vector2) -> void:
	_mouse = p
	_update_hover()
	if _mode == "menu":
		match _hover:
			"m0": close()
			"m1": _mode = "sound"
			"m2":
				_mode = "keys"
				_scroll = 0.0
			"m3": get_tree().quit()
	elif _mode == "sound":
		if _hover == "sb":
			_mode = "menu"
			Sound.save()
		elif _hover == "s0":
			_drag = "music"
			_set_slider("music", p.x)
		elif _hover == "s1":
			_drag = "sfx"
			_set_slider("sfx", p.x)
	else:
		if _hover == "k0":
			Keybinds.reset_all()
			_listening = ""
		elif _hover == "k1":
			_mode = "menu"
			_listening = ""
		elif _hover.begins_with("row:"):
			_listening = _entries[int(_hover.substr(4))]["action"]
		else:
			_listening = ""
	queue_redraw()


# ---------------------------------------------------------------- drawing
func _button(r: Rect2, text: String, hot: bool) -> void:
	UiStyle.slot(self, r, hot)
	var px := 0.5
	var w := HiFont.text_width(text, px)
	HiFont.draw(self, r.position + Vector2(floorf((r.size.x - w) / 2.0), floorf((r.size.y - HiFont.H * px) / 2.0)), text,
			UiStyle.GOLD if hot else UiStyle.TEXT, px)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	var px := 0.5
	if _mode == "menu":
		var m := _menu_rect()
		UiStyle.panel(self, m)
		HiFont.draw(self, m.position + Vector2(floorf((m.size.x - HiFont.text_width("MENU", px)) / 2.0), 8), "MENU", UiStyle.GOLD, px)
		var labels := ["Resume", "Sound", "Hotkeys", "Quit Game"]
		for i in 4:
			_button(_menu_button(i), labels[i], _hover == "m%d" % i)
		return
	if _mode == "sound":
		var sr := _sound_rect()
		UiStyle.panel(self, sr)
		HiFont.draw(self, sr.position + Vector2(8, 7), "SOUND", UiStyle.GOLD, px)
		var names := ["Music", "Sound effects"]
		var vals := [Sound.music_volume, Sound.sfx_volume]
		for i in 2:
			var t := _slider_rect(i)
			HiFont.draw(self, t.position + Vector2(0, -10), names[i], UiStyle.TEXT, px)
			var pct := "%d%%" % roundi(vals[i] * 100.0)
			HiFont.draw(self, t.position + Vector2(t.size.x - HiFont.text_width(pct, px), -10), pct, UiStyle.TEXT_DIM, px)
			draw_rect(t, Color(0.1, 0.08, 0.14, 1.0))
			draw_rect(Rect2(t.position, Vector2(t.size.x * float(vals[i]), t.size.y)), Color(0.75, 0.6, 0.3, 0.9))
			draw_rect(t, Color(0.4, 0.33, 0.2), false, 1.0)
			var hot := _hover == "s%d" % i or _drag == ("music" if i == 0 else "sfx")
			var kx: float = t.position.x + t.size.x * float(vals[i])
			draw_rect(Rect2(kx - 2, t.position.y - 3, 4, t.size.y + 6), UiStyle.GOLD if hot else Color("e8d8b0"))
		_button(_sound_back(), "Back", _hover == "sb")
		return
	var k := _keys_rect()
	UiStyle.panel(self, k)
	HiFont.draw(self, k.position + Vector2(8, 7), "HOTKEYS", UiStyle.GOLD, px)
	var hint := "Click a row, then press a key.  Backspace clears."
	HiFont.draw(self, k.position + Vector2(k.size.x - 8 - HiFont.text_width(hint, px), 7), hint, UiStyle.TEXT_DIM, px)
	var l := _list_rect()
	draw_rect(l, Color(0.03, 0.02, 0.05, 0.6))
	for i in _entries.size():
		var r := _row_rect(i)
		if r.position.y < l.position.y or r.end.y > l.end.y + 0.01:
			continue
		var e: Dictionary = _entries[i]
		if e.has("header"):
			HiFont.draw(self, r.position + Vector2(3, 2), str(e["header"]).to_upper(), UiStyle.GOLD, px)
			draw_line(r.position + Vector2(0, ROW_H - 1), r.position + Vector2(r.size.x, ROW_H - 1), Color(0.55, 0.42, 0.22, 0.5), 1.0)
			continue
		var hot := _hover == "row:%d" % i
		if hot:
			draw_rect(r, Color(1, 1, 1, 0.07))
		HiFont.draw(self, r.position + Vector2(8, 2), str(e["label"]), UiStyle.TEXT, px)
		var listening: bool = _listening == e["action"]
		var txt := "PRESS KEY" if listening else Keybinds.label(e["action"])
		var box := Rect2(r.end.x - 62, r.position.y + 1, 58, ROW_H - 2)
		draw_rect(box, Color(0.1, 0.08, 0.14, 1.0))
		draw_rect(box, UiStyle.GOLD if listening else Color(0.4, 0.33, 0.2), false, 1.0)
		var tw := HiFont.text_width(txt, px)
		HiFont.draw(self, box.position + Vector2(floorf((box.size.x - tw) / 2.0), 2), txt,
				UiStyle.GOLD if listening else Color("8fd0ff"), px)
	# scrollbar
	if _max_scroll() > 0.0:
		var frac := _scroll / _max_scroll()
		var bar_h := maxf(l.size.y * l.size.y / (_entries.size() * ROW_H), 10.0)
		draw_rect(Rect2(l.end.x - 2, l.position.y + (l.size.y - bar_h) * frac, 2, bar_h), Color(0.75, 0.6, 0.3, 0.8))
	_button(_key_button(0), "Reset defaults", _hover == "k0")
	_button(_key_button(1), "Back", _hover == "k1")
