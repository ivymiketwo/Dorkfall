extends StaticBody2D
## The village notice board. Walk up and press F to see the kill quests.

@export var interact_range := 44.0

const PX := 0.5
var _near := false


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("quest_giver_board")


func _process(_delta: float) -> void:
	var player := Players.local(get_tree())
	var near := player != null and global_position.distance_to(player.global_position) <= interact_range
	if near != _near:
		_near = near
		queue_redraw()


func interact(player: Node2D) -> void:
	var ui := get_tree().get_first_node_in_group("quest_ui")
	if ui:
		ui.open(self, player)


func _draw() -> void:
	var name_text := "NOTICE BOARD"
	HiFont.draw(self, Vector2(-floorf(HiFont.text_width(name_text, PX) / 2.0), -38), name_text, Color("ffd98a"), PX)
	if _near:
		var t := "F  QUESTS"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), -31), t, Color("f0d040"), PX)
