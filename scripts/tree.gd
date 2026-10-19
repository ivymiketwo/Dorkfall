extends StaticBody2D
## Picks which tree art to show: the old small trees (oak, oak2, cherry, pine, the burnt dead
## trees) or one of Rex's big forest trees (see tree_art.gd).

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

@export_enum("oak", "oak2", "cherry", "pine", "dead", "dead2", "dead3",
		"oak_round", "oak_dark", "willow_twisted", "willow_teal", "willow_mossy", "birch_willow",
		"fir", "autumn_round", "autumn_gnarled", "jungle", "pine_small", "apple", "blossom",
		"twisted") var kind := "oak"


func _ready() -> void:
	var s: Sprite2D = $Sprite2D
	if TreeArt.has(kind):
		TreeArt.apply(s, kind)
		set_meta("shadow_scale", TreeArt.shadow_scale(kind))
		var trunk := CircleShape2D.new()
		trunk.radius = 7.0 if TreeArt.size(kind).y > 100.0 else 5.0
		($CollisionShape2D as CollisionShape2D).shape = trunk
		return
	s.texture = ART[kind]
	s.offset = Vector2(0, -BASE[kind] / 2.0 + 4)
