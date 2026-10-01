extends StaticBody2D
## Picks which tree art to show: oak, oak2, cherry, pine or the burnt dead trees.

const ART := {
	"oak": preload("res://art/tree_oak.png"),
	"oak2": preload("res://art/tree_oak2.png"),
	"cherry": preload("res://art/tree_cherry.png"),
	"pine": preload("res://art/tree_pine.png"),
	"dead": preload("res://art/tree_dead.png"),
	"dead2": preload("res://art/tree_dead2.png"),
	"dead3": preload("res://art/tree_dead3.png"),
}
const BASE := {"oak": 82, "oak2": 86, "cherry": 82, "pine": 94, "dead": 68, "dead2": 59, "dead3": 56}

@export_enum("oak", "oak2", "cherry", "pine", "dead", "dead2", "dead3") var kind := "oak"


func _ready() -> void:
	var s: Sprite2D = $Sprite2D
	s.texture = ART[kind]
	s.offset = Vector2(0, -BASE[kind] / 2.0 + 4)
