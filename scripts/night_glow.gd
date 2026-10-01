class_name NightGlow
extends Node2D
## Glowing windows / lamps after dark. Give it rectangles (in the parent's local
## units); each becomes a warm, bright patch plus a soft point light that fade in
## as night falls. DayNight drives `strength` and `ambient`.

@export var rects: Array[Rect2] = []
@export var glow_color := Color(1.0, 0.78, 0.38)
@export var light_scale := 0.55           ## light size (1.0 = 64 units across)
@export var light_energy := 1.0
@export var draw_rects := true            ## paint the window itself bright

var strength := 0.0:
	set(v):
		strength = v
		_update()
var ambient := Color.WHITE:
	set(v):
		ambient = v
		_update()

var _lights: Array[PointLight2D] = []
var _paint: Node2D
static var _tex: GradientTexture2D


static func light_texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
		_tex.width = 128
		_tex.height = 128
	return _tex


func _ready() -> void:
	add_to_group("night_glow")
	_paint = Node2D.new()          # separate node so its brightness fix doesn't touch the lights
	_paint.z_index = 1
	_paint.draw.connect(_draw_rects)
	add_child(_paint)
	for r in rects:
		var l := PointLight2D.new()
		l.texture = light_texture()
		l.texture_scale = light_scale
		l.color = glow_color
		l.energy = 0.0
		l.position = r.get_center()
		add_child(l)
		_lights.append(l)
	_update()


func _update() -> void:
	for l in _lights:
		l.energy = strength * light_energy
	if _paint:
		# Cancel the night tint on the painted windows so they read as truly lit.
		var inv := Color(minf(1.0 / maxf(ambient.r, 0.05), 4.0), minf(1.0 / maxf(ambient.g, 0.05), 4.0),
				minf(1.0 / maxf(ambient.b, 0.05), 4.0), clampf(strength * 1.1, 0.0, 0.9))
		_paint.modulate = inv
		_paint.visible = strength > 0.02
		_paint.queue_redraw()


func _draw_rects() -> void:
	if not draw_rects:
		return
	for r in rects:
		_paint.draw_rect(r, glow_color)
		_paint.draw_rect(r.grow(-1.5), Color(1.0, 0.93, 0.7))
