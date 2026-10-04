extends Node
## Audio autoload ("Sound"): the Music and SFX buses, the background soundtrack, and the saved
## volume settings (user://settings.cfg). Every AudioStreamPlayer that enters the tree on the
## default bus is routed to SFX automatically, so new sound effects obey the SFX slider.

const SETTINGS_PATH := "user://settings.cfg"
const MUSIC := preload("res://audio/music_our_town.ogg")

var music_volume := 0.7    ## 0..1 (slider position; mapped to decibels)
var sfx_volume := 0.8

var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # music keeps playing while the escape menu pauses the game
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load()
	_apply()
	get_tree().node_added.connect(_on_node_added)
	var song: AudioStreamOggVorbis = MUSIC
	song.loop = true
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = MUSIC
	_music_player.bus = "Music"
	add_child(_music_player)
	_music_player.play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


func _on_node_added(n: Node) -> void:
	if n == _music_player:
		return
	if (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D) and n.bus == &"Master":
		n.bus = &"SFX"


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply()


func _apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _to_db(music_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _to_db(sfx_volume))


func _to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func save() -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)       # keep anything else stored there
	c.set_value("audio", "music", music_volume)
	c.set_value("audio", "sfx", sfx_volume)
	c.save(SETTINGS_PATH)


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		music_volume = clampf(float(c.get_value("audio", "music", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(c.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
