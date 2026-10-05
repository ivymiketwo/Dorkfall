class_name BiteStrike
extends Node2D
## Short telegraph for a melee bite: a wedge in front of the attacker fills red,
## then snaps shut and hurts anyone still inside. Gone instantly if the caster dies.

@export var length := 36.0
@export var spread_deg := 80.0
@export var warn_time := 0.4
@export var damage := 30.0

var direction := Vector2.RIGHT
var caster: Node
var _t := 0.0
var _timeline: AttackTimeline   ## when it snaps shut (rules); drawing reads _t


func _ready() -> void:
	rotation = direction.angle()
	_timeline = AttackTimeline.new().at(warn_time, _snap).lasts(warn_time + 0.12)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


func _snap() -> void:
	for player in Players.all(get_tree()):
		var p := to_local(player.global_position + AttackRules.CHEST)
		if AttackRules.wedge_hits(p, length, spread_deg):
			AttackRules.deal(player, damage, caster, global_position)


func _process(_delta: float) -> void:
	queue_redraw()


func _wedge(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	var half := deg_to_rad(spread_deg * 0.5)
	for i in 13:
		pts.append(Vector2.from_angle(lerpf(-half, half, float(i) / 12.0)) * radius)
	return pts


func _draw() -> void:
	if _t < warn_time:
		var k := _t / warn_time
		draw_colored_polygon(_wedge(length), Color(1.0, 0.85, 0.2, 0.15 + 0.15 * k))
		draw_colored_polygon(_wedge(length * k), Color(0.95, 0.12, 0.1, 0.25 + 0.3 * k))
		var edge := _wedge(length)
		edge.append(Vector2.ZERO)
		draw_polyline(edge, Color(0.95, 0.2, 0.15, 0.7), 1.0)
	else:
		var a := 1.0 - (_t - warn_time) / 0.12
		draw_colored_polygon(_wedge(length), Color(1.0, 0.95, 0.85, 0.6 * a))


func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
