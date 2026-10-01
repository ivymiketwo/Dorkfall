class_name ChatLog
extends Control
## Game messages in the bottom-left corner. Lines fade out after a while.
## Anyone can post with ChatLog.say(get_tree(), "text", color).

const MAX_LINES := 6
const MAX_CHARS := 90
const LIFETIME := 12.0
const FADE := 2.0

## True while the player is typing a message: movement and hotkeys are off.
static var typing := false

var _lines: Array = []      # [{text, color, age}]
var _text := ""
var _blink := 0.0
var _history: Array = []


static func say(tree: SceneTree, text: String, color := Color("efe6d2")) -> void:
	var log := tree.get_first_node_in_group("chat_log") as ChatLog
	if log:
		log.add(text, color)


func _ready() -> void:
	add_to_group("chat_log")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var code: int = event.physical_keycode
	if not typing:
		if event.echo or get_tree().paused:
			return
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			_begin("")
			get_viewport().set_input_as_handled()
		elif event.unicode == 47 and ChatCommands.ENABLED:      # "/" starts a command
			_begin("/")
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if code == KEY_ESCAPE:
		_end()
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		var text := _text.strip_edges()
		_end()
		if text != "":
			_submit(text)
	elif event.is_command_or_control_pressed() and code in [KEY_V, KEY_C, KEY_X, KEY_A]:
		match code:
			KEY_V:
				_text = (_text + _clean(DisplayServer.clipboard_get())).left(MAX_CHARS)
			KEY_C:
				DisplayServer.clipboard_set(_text)
			KEY_X:
				DisplayServer.clipboard_set(_text)
				_text = ""
			KEY_A:
				pass
	elif event.shift_pressed and code == KEY_INSERT:
		_text = (_text + _clean(DisplayServer.clipboard_get())).left(MAX_CHARS)
	elif code == KEY_BACKSPACE:
		_text = _text.substr(0, _text.length() - 1)
	elif code == KEY_UP and not _history.is_empty():
		_text = _history[-1]
	elif event.unicode >= 32 and event.unicode < 127 and _text.length() < MAX_CHARS:
		_text += char(event.unicode)
	_blink = 0.0
	queue_redraw()


## Pasted text: one line, plain characters only.
func _clean(raw: String) -> String:
	var out := ""
	for c in raw.replace("\n", " ").replace("\r", " ").replace("\t", " "):
		var u := c.unicode_at(0)
		if u >= 32 and u < 127:
			out += c
	return out


func _begin(prefill: String) -> void:
	typing = true
	_text = prefill
	_blink = 0.0
	queue_redraw()


func _end() -> void:
	typing = false
	_text = ""
	queue_redraw()


func _submit(text: String) -> void:
	_history.append(text)
	var player := Players.local(get_tree())
	if text.begins_with("/") and ChatCommands.can_use(player):
		if player == null:
			return
		var r := ChatCommands.run(text, player)
		for line in r["lines"]:
			add(line, Color("9ad0ff") if r["ok"] else Color("e0a040"))
	else:
		var who := String(player.display_name) if player != null else "You"
		add("%s: %s" % [who, text], Color("efe6d2"))


func add(text: String, color: Color) -> void:
	_lines.append({"text": text, "color": color, "age": 0.0})
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	queue_redraw()


func _process(delta: float) -> void:
	if typing:
		_blink += delta
		queue_redraw()
		for l in _lines:
			l["age"] = minf(l["age"], LIFETIME - FADE)    # keep the log readable while typing
	if _lines.is_empty():
		return
	for l in _lines:
		l["age"] += delta
	while not _lines.is_empty() and _lines[0]["age"] > LIFETIME:
		_lines.pop_front()
	queue_redraw()


func _draw() -> void:
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	var px := 0.5
	var lh := 9.0
	var y := screen.y - 24.0 - _lines.size() * lh
	if typing:
		y -= 11.0
		var shown := _text + ("_" if int(_blink * 2.0) % 2 == 0 else "")
		var box := Rect2(3, screen.y - 33.0, 190, 10)
		draw_rect(box, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 0.5)), UiStyle.BRONZE_MID)
		draw_rect(Rect2(box.position + Vector2(0, box.size.y - 0.5), Vector2(box.size.x, 0.5)), UiStyle.BRONZE_MID)
		HiFont.draw(self, box.position + Vector2(2, 2.5), shown.right(46) if shown.length() > 46 else shown, Color("ffe066"), px)
	for l in _lines:
		var a := clampf((LIFETIME - l["age"]) / FADE, 0.0, 1.0)
		var w := HiFont.text_width(l["text"], px)
		draw_rect(Rect2(3, y - 1, w + 4, lh - 1), Color(0, 0, 0, 0.45 * a))
		var c: Color = l["color"]
		HiFont.draw(self, Vector2(5, y + 1), l["text"], Color(c.r, c.g, c.b, a), px)
		y += lh
