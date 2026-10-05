class_name KnifeThrow
extends Node2D
## A telegraphed butcher-knife throw: a long rectangle glows red on the ground,
## then a knife flies down it and hurts the player if they're still inside.

@export var length := 110.0
@export var width := 14.0
@export var warn_time := 0.9
@export var damage := 50.0
@export var fly_time := 0.16

var direction := Vector2.RIGHT
var caster: Node
var _t := 0.0
var _hit := false
var _timeline: AttackTimeline   ## when the knife flies (rules); drawing reads _t
var _fx: Node2D


func _ready() -> void:
	rotation = direction.angle()
	_fx = Node2D.new()          # the flying knife, drawn above characters
	_fx.z_index = 5
	_fx.draw.connect(_draw_knife)
	add_child(_fx)
	_timeline = AttackTimeline.new().during(warn_time, warn_time + fly_time, _fly)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


## Every tick while the knife is in the air: hits the first player its blade passes.
func _fly(progress: float) -> void:
	if _hit:
		return
	for player in Players.all(get_tree()):
		var p := to_local(player.global_position + AttackRules.CHEST)
		if AttackRules.knife_hits(p, length, width, progress):
			AttackRules.deal(player, damage, caster, global_position)
			_hit = true


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


func _draw() -> void:
	if _t >= warn_time:
		return
	var k := _t / warn_time
	var r := Rect2(0, -width * 0.5, length, width)
	draw_rect(r, Color(1.0, 0.85, 0.2, 0.15 + 0.15 * k))                       # danger zone
	draw_rect(Rect2(0, -width * 0.5, length * k, width), Color(0.95, 0.12, 0.1, 0.25 + 0.3 * k))  # fills red
	draw_rect(r, Color(0.95, 0.2, 0.15, 0.7), false, 1.0)


func _draw_knife() -> void:
	if _t < warn_time:
		return
	var f := clampf((_t - warn_time) / fly_time, 0.0, 1.0)
	var x := length * f
	var spin := f * TAU * 2.0
	_fx.draw_set_transform(Vector2(x, 0), spin, Vector2.ONE)
	_fx.draw_rect(Rect2(-5, -1, 4, 2), Color("6a4020"))                           # handle
	_fx.draw_rect(Rect2(-1, -3, 8, 6), Color("dfe3ea"))                            # cleaver blade
	_fx.draw_rect(Rect2(-1, 1, 8, 2), Color("8a90a0"))
	_fx.draw_rect(Rect2(3, -2, 2, 1), Color("2a2018"))

## Called if whoever cast this dies: gone instantly, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
