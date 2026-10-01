class_name Keybinds
extends RefCounted
## Rebindable keys. Every action listed here can be changed from Esc > Hotkeys.
## Changes are saved and re-applied at startup (see Player._ensure_input_actions).

## Actions shown in the Hotkeys menu: [action, label, group].
static func entries() -> Array:
	var out: Array = [
		["inventory", "Inventory", "Windows"],
		["spellbook", "Spellbook", "Windows"],
		["paperdoll", "Equipment", "Windows"],
		["stats", "Stats", "Windows"],
		["home_teleport", "Home teleport", "Actions"],
		["interact", "Talk / interact", "Actions"],
		["bar_up", "Previous hotbar", "Hotbar"],
		["bar_down", "Next hotbar", "Hotbar"],
	]
	for s in Hotbar.PER_BAR:
		out.append(["hotbar_%d" % (s + 1), "Visible bar, slot %d" % (s + 1), "Visible hotbar"])
	for b in Hotbar.BARS:
		for s in Hotbar.PER_BAR:
			out.append(["bar%d_slot%d" % [b + 1, s + 1], "Bar %d, slot %d" % [b + 1, s + 1], "Bar %d" % (b + 1)])
	return out


static func default_key(action: String) -> Array:   # [keycode, shift, ctrl, alt] or []
	match action:
		"inventory": return [KEY_B, false, false, false]
		"spellbook": return [KEY_K, false, false, false]
		"paperdoll": return [KEY_P, false, false, false]
		"stats": return [KEY_C, false, false, false]
		"home_teleport": return [KEY_H, false, false, false]
		"interact": return [KEY_F, false, false, false]
	if action.begins_with("hotbar_"):
		return [KEY_1 + int(action.substr(7)) - 1, false, false, false]
	return []


static func _make_event(spec: Array) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = spec[0]
	ev.shift_pressed = spec[1]
	ev.ctrl_pressed = spec[2]
	ev.alt_pressed = spec[3]
	return ev


static func current(action: String) -> Array:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return [ev.physical_keycode, ev.shift_pressed, ev.ctrl_pressed, ev.alt_pressed]
	return []


static func label_of(spec: Array, short := false) -> String:
	if spec.is_empty():
		return "" if short else "---"
	var k := OS.get_keycode_string(spec[0]).to_upper()
	if short and k.length() > 3:
		k = k.substr(0, 3)
	var pre := ""
	if spec[2]: pre += "C+"
	if spec[3]: pre += "A+"
	if spec[1]: pre += "S+"
	return pre + k


static func label(action: String, short := false) -> String:
	return label_of(current(action), short)


## Registers every action and applies saved overrides.
static func apply() -> void:
	var saved = SaveGame.get_value("keybinds", {})
	for e in entries():
		var a: String = e[0]
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var d := default_key(a)
			if not d.is_empty():
				InputMap.action_add_event(a, _make_event(d))
		if saved is Dictionary and saved.has(a):
			InputMap.action_erase_events(a)
			var v = saved[a]
			if v is Array and v.size() == 4:
				InputMap.action_add_event(a, _make_event(v))


static func _store(action: String, spec: Array) -> void:
	var saved = SaveGame.get_value("keybinds", {})
	if not (saved is Dictionary):
		saved = {}
	saved[action] = spec
	SaveGame.put("keybinds", saved)


static func _same(a: Array, b: Array) -> bool:
	return not a.is_empty() and not b.is_empty() and a[0] == b[0] and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]


## Binds `spec` to `action` (empty = unbind). Any other listed action that used the same key is unbound.
static func bind(action: String, spec: Array) -> void:
	if not spec.is_empty():
		for e in entries():
			var other: String = e[0]
			if other != action and _same(current(other), spec):
				InputMap.action_erase_events(other)
				_store(other, [])
	InputMap.action_erase_events(action)
	if not spec.is_empty():
		InputMap.action_add_event(action, _make_event(spec))
	_store(action, spec)


static func reset_all() -> void:
	SaveGame.put("keybinds", {})
	for e in entries():
		var a: String = e[0]
		InputMap.action_erase_events(a)
		var d := default_key(a)
		if not d.is_empty():
			InputMap.action_add_event(a, _make_event(d))
