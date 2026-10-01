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
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
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
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))


## Items are Resources (.tres files); the save file just stores their paths.
static func item_to_path(item: Item) -> String:
	return item.resource_path if item != null else ""


static func item_from_path(path: String) -> Item:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Item
