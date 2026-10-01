class_name DayNight
extends CanvasModulate
## Day/night cycle. Tints the whole world by time of day (dawn glow, bright noon,
## orange dusk, blue night), lights up lamps and windows after dark, and tells
## the ShadowLayer where the sun is. Press T to skip an hour (debug).

@export var day_seconds_per_hour := 80.0    ## real seconds per daytime hour (Hearthlight: 80)
@export var night_seconds_per_hour := 45.0  ## real seconds per night hour (20:00-06:00)
@export_range(0.0, 24.0) var start_hour := 10.0
@export var paused := false

## Time of day in hours, 0..24.
var hour := 10.0
## 0 (noon) .. 1 (deep night): drives lamps and window glow.
var night_amount := 0.0
## Sun height 0 (horizon / night) .. 1 (noon) and its sweep angle (0 sunrise .. PI sunset).
var sun_height := 1.0
var sun_angle := PI * 0.5

## Colour stops after Hearthlight's day: a long warm day, a slow gold-to-violet dusk,
## then several shades of blue through the night and a pink dawn.
const KEYS := [
	[0.0, Color(0.27, 0.32, 0.62)],
	[2.5, Color(0.24, 0.29, 0.58)],
	[4.5, Color(0.30, 0.35, 0.66)],
	[5.8, Color(0.78, 0.66, 0.80)],
	[6.6, Color(1.00, 0.84, 0.74)],
	[7.5, Color(1.00, 0.93, 0.84)],
	[9.0, Color(1.00, 0.98, 0.94)],
	[13.0, Color(1.00, 1.00, 1.00)],
	[16.5, Color(1.00, 0.96, 0.88)],
	[18.2, Color(1.00, 0.76, 0.58)],
	[19.3, Color(0.78, 0.55, 0.70)],
	[20.0, Color(0.50, 0.46, 0.76)],
	[20.8, Color(0.34, 0.40, 0.72)],
	[22.0, Color(0.28, 0.33, 0.64)],
	[24.0, Color(0.27, 0.32, 0.62)],
]
const INDOOR := Color(1.0, 0.95, 0.86)

var _indoor := 0.0
var _lantern: PointLight2D


func _ready() -> void:
	add_to_group("day_night")
	hour = start_hour
	_make_lantern.call_deferred()
	_apply()


func _make_lantern() -> void:
	# A small lantern glow that follows the player after dark.
	var player := Players.local(get_tree())
	if player:
		_lantern = PointLight2D.new()
		_lantern.name = "Lantern"
		_lantern.texture = NightGlow.light_texture()
		_lantern.texture_scale = 0.7
		_lantern.color = Color(1.0, 0.85, 0.6)
		_lantern.position = Vector2(0, -10)
		_lantern.energy = 0.0
		player.add_child(_lantern)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T:
		hour = fposmod(hour + 1.0, 24.0)


func _process(delta: float) -> void:
	if not paused:
		var spd := night_seconds_per_hour if (hour >= 20.0 or hour < 6.0) else day_seconds_per_hour
		hour = fposmod(hour + delta / spd, 24.0)
	var player := Players.local(get_tree())
	var inside := player != null and player.global_position.y > 2300.0
	_indoor = move_toward(_indoor, 1.0 if inside else 0.0, delta * 3.0)
	_apply()


func _apply() -> void:
	var c := _sample(hour)
	night_amount = clampf((0.86 - (c.r + c.g + c.b) / 3.0) / 0.45, 0.0, 1.0)
	sun_angle = clampf((hour - 5.8) / 13.5, 0.0, 1.0) * PI
	sun_height = sin(sun_angle) if hour > 5.8 and hour < 19.3 else 0.0
	color = c.lerp(INDOOR, _indoor)
	var outdoor_night := night_amount * (1.0 - _indoor)
	for n in get_tree().get_nodes_in_group("night_glow"):
		n.strength = outdoor_night
		n.ambient = color
	if _lantern:
		_lantern.energy = outdoor_night * 0.9


func _sample(h: float) -> Color:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= a[0] and h <= b[0]:
			return (a[1] as Color).lerp(b[1], inverse_lerp(a[0], b[0], h))
	return KEYS[0][1]


## "HH:MM" for a clock display.
func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int((hour - floorf(hour)) * 60.0)]
