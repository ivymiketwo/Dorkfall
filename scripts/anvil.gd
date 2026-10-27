class_name Anvil
extends Node2D
## The blacksmith's anvil: walk up and press F to open the enhancing window (enhance_ui.gd).
## The anvil itself is painted into the room picture; this node just marks where it is.

@export var interact_range := 40.0   # reaches over the counter too

const PX := 0.5   # one real screen pixel in world units (camera zoom is 2)

var _near := false


func _ready() -> void:
	add_to_group("interactables")
	z_index = 3


func _process(_delta: float) -> void:
	var player := Players.local(get_tree())
	var near := player != null and global_position.distance_to(player.global_position) <= interact_range
	if near != _near:
		_near = near
		queue_redraw()


func interact(player: Node2D) -> void:
	var ui := get_tree().get_first_node_in_group("enhance_ui")
	if ui:
		ui.open(self, player)


func _draw() -> void:
	if _near:
		var t := "F  ENHANCE"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), -24.0), t, Color("f0d040"), PX)
