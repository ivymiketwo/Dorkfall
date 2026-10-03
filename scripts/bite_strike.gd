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
var _struck := false


func _ready() -> void:
	rotation = direction.angle()


func _process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	_t += delta
	if not _struck and _t >= warn_time:
		_struck = true
		for player in Players.all(get_tree()):
			var p := to_local(player.global_position + AttackRules.CHEST)
			if p.length() <= length and absf(rad_to_deg(p.angle())) <= spread_deg * 0.5:
				AttackRules.deal(player, damage, caster, global_position)
	if _t >= warn_time + 0.12:
		queue_free()
		return
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
	hide()
	queue_free()
