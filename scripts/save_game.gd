class_name SaveGame
extends RefCounted
## Tiny save file (JSON in Godot's user folder). Anything that wants to
## persist calls SaveGame.put("key", value) and SaveGame.get_value("key").
## On Windows the file lives at %APPDATA%\Godot\app_userdata\<project>\save.json

const PATH := "user://save.json"

static var _data := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := PATH
	if not FileAccess.file_exists(path):
		# On Windows the swap in _write is "delete the old file, then rename the new one": if the
		# game stopped right between the two, the save is still there under its temporary name.
		path = PATH + ".tmp"
		if not FileAccess.file_exists(path):
			return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed


static func get_value(key: String, default: Variant = null) -> Variant:
	_load()
	return _data.get(key, default)


static func put(key: String, value: Variant) -> void:
	_load()
	_data[key] = value
	if _batch_depth > 0:
		_dirty = true
		return
	_write()


## Forgets these keys (one write).
static func erase(keys: Array) -> void:
	_load()
	for k in keys:
		_data.erase(k)
	if _batch_depth > 0:
		_dirty = true
		return
	_write()


static var _batch_depth := 0
static var _dirty := false


## Runs `changes` and saves everything it changed in ONE write at the end. Use it whenever
## something moves between two saved places (bag -> gravestone, pet -> bag): either both
## sides land in the file or neither does, so a crash in between can never duplicate items.
static func batch(changes: Callable) -> Variant:
	_batch_depth += 1
	var result = changes.call()
	_batch_depth -= 1
	if _batch_depth == 0 and _dirty:
		_dirty = false
		_write()
	return result


## Writes to a temporary file first and then swaps it in, so a crash mid-write
## leaves the old save intact instead of a half-written one.
static func _write() -> void:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH)) != OK:
		var direct := FileAccess.open(PATH, FileAccess.WRITE)   # couldn't swap: write in place as before
		if direct:
			direct.store_string(JSON.stringify(_data, "\t"))


## Items are Resources (.tres files); the save file just stores their paths. An enhanced item
## (see Enhance) is its own copy of the item and is stored as "<path>#+<level>", e.g.
## "res://items/astral_staff.tres#+5".
static func item_to_path(item: Item) -> String:
	if item == null:
		return ""
	var base := item.base_path()
	if base != "" and item.enhance > 0:
		return "%s#+%d" % [base, item.enhance]
	return base


static func item_from_path(path: String) -> Item:
	var level := 0
	var cut := path.find("#+")
	if cut != -1:
		level = clampi(int(path.substr(cut + 2)), 0, Item.MAX_ENHANCE)
		path = path.substr(0, cut)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var it := load(path) as Item
	if it != null and level > 0:
		it = it.enhanced_copy(level)
	return it
