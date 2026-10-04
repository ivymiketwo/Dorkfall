extends Node
## Audio autoload ("Sound"): the Ambient and SFX buses and the saved volume settings
## (user://settings.cfg). Ambient sounds (wind, birds, ...) should set their player's bus to "Ambient". Every AudioStreamPlayer that enters the tree on the
## default bus is routed to SFX automatically, so new sound effects obey the SFX slider.

const SETTINGS_PATH := "user://settings.cfg"

var ambient_volume := 0.8  ## 0..1 (slider position; mapped to decibels)
var sfx_volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Ambient")
	_ensure_bus("SFX")
	_load()
	_apply()
	get_tree().node_added.connect(_on_node_added)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


func _on_node_added(n: Node) -> void:
	if (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D) and n.bus == &"Master":
		n.bus = &"SFX"


func set_ambient_volume(v: float) -> void:
	ambient_volume = clampf(v, 0.0, 1.0)
	_apply()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply()


func _apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), _to_db(ambient_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _to_db(sfx_volume))


func _to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func save() -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)       # keep anything else stored there
	c.set_value("audio", "ambient", ambient_volume)
	c.set_value("audio", "sfx", sfx_volume)
	c.save(SETTINGS_PATH)


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		ambient_volume = clampf(float(c.get_value("audio", "ambient", ambient_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(c.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
