class_name LungeStrike
extends Node2D
## Telegraph for a melee lunge: a rectangle in front of the attacker glows red
## and fills up; when it's full the attacker lunges forward down it and hurts
## anyone still inside. The marker is gone the instant the lunge starts.
## The caster needs a `begin_lunge(direction: Vector2)` method.

@export var length := 44.0
@export var width := 18.0
@export var warn_time := 0.7
@export var damage := 60.0

var direction := Vector2.RIGHT
var caster: Node
var _t := 0.0
var _timeline: AttackTimeline   ## when it strikes (rules); drawing reads _t
var _fx: Node2D


func _ready() -> void:
	rotation = direction.angle()
	_fx = Node2D.new()          # the slash flash, drawn above characters
	_fx.z_index = 5
	_fx.draw.connect(_draw_slash)
	add_child(_fx)
	_timeline = AttackTimeline.new().at(warn_time, _strike).lasts(warn_time + 0.22)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


func _strike() -> void:
	if caster and is_instance_valid(caster) and caster.has_method("begin_lunge"):
		caster.begin_lunge(direction)
	for player in Players.all(get_tree()):
		var p := to_local(player.global_position + AttackRules.CHEST)
		if AttackRules.lunge_hits(p, length, width):
			AttackRules.deal(player, damage, caster, global_position)


func _draw() -> void:
	if _t >= warn_time:
		return
	var k := _t / warn_time
	var r := Rect2(0, -width * 0.5, length, width)
	draw_rect(r, Color(1.0, 0.85, 0.2, 0.15 + 0.15 * k))                                      # danger zone
	draw_rect(Rect2(0, -width * 0.5, length * k, width), Color(0.95, 0.12, 0.1, 0.25 + 0.3 * k))  # fills red
	draw_rect(r, Color(0.95, 0.2, 0.15, 0.7), false, 1.0)


func _draw_slash() -> void:
	if _t < warn_time:
		return
	var f := clampf((_t - warn_time) / 0.2, 0.0, 1.0)
	var a := 1.0 - f
	var reach := length * (0.35 + 0.65 * minf(f * 3.0, 1.0))
	# a fast white-hot thrust streak down the lane
	for i in 4:
		var y := (float(i) - 1.5) * width * 0.16
		_fx.draw_line(Vector2(reach * 0.15, y), Vector2(reach, y * 0.4), Color(1.0, 0.95, 0.85, a * (0.9 - 0.15 * float(i))), 2.0 - 0.3 * float(i))
	_fx.draw_line(Vector2(reach * 0.2, 0), Vector2(reach + 4.0, 0), Color(1.0, 0.35, 0.25, a * 0.7), 4.0)


## Called if whoever cast this dies: gone instantly, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
