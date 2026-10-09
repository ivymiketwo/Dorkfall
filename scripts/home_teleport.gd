class_name HomeTeleport
extends Node2D
## Press H: a blue summoning circle spins under the player while a bar fills for
## about 5 seconds, then the player is teleported back to the respawn point.
## Moving or taking damage interrupts it.

@export var cast_time := 5.0
@export var radius := 20.0

var _t := 0.0
var _active := false
var _fx: Node2D          ## the circle, drawn behind the character
var _bar: Node2D         ## the progress bar, drawn above everything

@onready var player: CharacterBody2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")


func _ready() -> void:
	set_physics_process(false)
	_fx = Node2D.new()
	_fx.draw.connect(_draw_circle)
	player.add_child.call_deferred(_fx)
	_fx.hide()
	_place_fx.call_deferred()
	_bar = Node2D.new()
	_bar.z_index = 20
	_bar.draw.connect(_draw_bar)
	player.add_child.call_deferred(_bar)
	_bar.hide()
	stats.damaged.connect(func(_a: float) -> void: cancel())
	stats.died.connect(cancel)


func _place_fx() -> void:
	if is_instance_valid(_fx) and _fx.get_parent() == player:
		player.move_child(_fx, 0)      # first child = drawn before the sprite, so under the character


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("home_teleport") and not event.is_echo():
		if not _active:
			start()
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return _active


func progress() -> float:
	return clampf(_t / cast_time, 0.0, 1.0)


func start() -> void:
	if _active or stats.health <= 0.0 or not player.is_physics_processing():
		return
	_active = true
	_t = 0.0
	_fx.show()
	_bar.show()
	set_physics_process(true)


func cancel() -> void:
	if not _active:
		return
	_active = false
	set_physics_process(false)
	_fx.hide()
	_bar.hide()


## The cast counts on the fixed game tick (a server runs the same).
func _physics_process(delta: float) -> void:
	if not player.is_physics_processing():     # a door / fade took over
		cancel()
		return
	if player.velocity.length() > 4.0 or player.input_dir != Vector2.ZERO:
		cancel()
		return
	_t += delta
	if _t >= cast_time:
		_finish()
		return
	_fx.queue_redraw()
	_bar.queue_redraw()


func _finish() -> void:
	cancel()
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("go_home"):
		world.go_home()
	else:
		player.position = player._spawn_point
		player.reset_physics_interpolation()


func _ring(c: Vector2, r: float, rot: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := rot + TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.5))     # squashed: seen from above at an angle
	return pts


func _draw_circle() -> void:
	var k := _t / cast_time
	var fade_in := clampf(_t / 0.35, 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(_t * 6.0)
	var c := Vector2(0, -1)
	var col := Color(0.35, 0.65, 1.0)
	_fx.draw_colored_polygon(_ring(c, radius, 0.0, 28), Color(0.15, 0.35, 0.85, 0.20 * fade_in * pulse))
	_fx.draw_polyline(_ring(c, radius, 0.0, 40), Color(0.55, 0.8, 1.0, 0.9 * fade_in), 1.0)
	_fx.draw_polyline(_ring(c, radius * 0.82, 0.0, 40), Color(col.r, col.g, col.b, 0.7 * fade_in), 1.0)
	# rotating runic star and ticks
	var rot := _t * 1.1
	var star := PackedVector2Array()
	for i in 6:
		var a := rot + TAU * float(i) / 6.0
		star.append(c + Vector2(cos(a) * radius * 0.78, sin(a) * radius * 0.78 * 0.5))
	for i in 6:
		_fx.draw_line(star[i], star[(i + 2) % 6], Color(0.7, 0.88, 1.0, 0.8 * fade_in), 1.0)
	for i in 12:
		var a := -rot * 0.7 + TAU * float(i) / 12.0
		var p1 := c + Vector2(cos(a) * radius * 0.86, sin(a) * radius * 0.86 * 0.5)
		var p2 := c + Vector2(cos(a) * radius * 0.98, sin(a) * radius * 0.98 * 0.5)
		_fx.draw_line(p1, p2, Color(0.8, 0.92, 1.0, 0.9 * fade_in), 1.0)
	# rising motes that get denser as the spell charges
	var motes := 6 + int(14.0 * k)
	for i in motes:
		var seed_a := float(i) * 2.399
		var life := fposmod(_t * (0.9 + 0.4 * fmod(float(i) * 0.37, 1.0)) + float(i) * 0.31, 1.0)
		var a := seed_a + _t * 0.5
		var rr := radius * (0.25 + 0.65 * fmod(float(i) * 0.61, 1.0))
		var p := c + Vector2(cos(a) * rr, sin(a) * rr * 0.5) + Vector2(0, -life * 24.0)
		_fx.draw_rect(Rect2(p, Vector2(1, 1)), Color(0.7, 0.9, 1.0, (1.0 - life) * fade_in))
	# a brightening pillar of light near the end
	if k > 0.75:
		var f := (k - 0.75) / 0.25
		_fx.draw_rect(Rect2(Vector2(-radius * 0.35, -30.0 * f), Vector2(radius * 0.7, 30.0 * f)), Color(0.6, 0.85, 1.0, 0.12 * f))


func _draw_bar() -> void:
	var w := 26.0
	var pos := Vector2(-w * 0.5, 7.0)
	_bar.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(w + 2, 5)), Color(0.05, 0.07, 0.15, 0.9))
	_bar.draw_rect(Rect2(pos, Vector2(w, 3)), Color(0.12, 0.2, 0.42))
	_bar.draw_rect(Rect2(pos, Vector2(w * clampf(_t / cast_time, 0.0, 1.0), 3)), Color(0.45, 0.78, 1.0))
	_bar.draw_rect(Rect2(pos, Vector2(w * clampf(_t / cast_time, 0.0, 1.0), 1)), Color(0.85, 0.95, 1.0))
