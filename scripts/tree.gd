extends StaticBody2D
## Picks which tree art to show.
##   - The standard living trees (oak, oak2, cherry, pine) use Rex's new tree set (std_* in
##     tree_art.gd). Each spot picks one of its kind's looks from where it stands, so a meadow of
##     "oak" trees isn't all the same tree, and the same spot always shows the same tree.
##   - The burnt dead trees keep their old art.
##   - Rex's big forest trees (tree_art.gd) can be picked by name too.

const DEAD := {
	"dead": preload("res://art/tree_dead.png"),
	"dead2": preload("res://art/tree_dead2.png"),
	"dead3": preload("res://art/tree_dead3.png"),
}
const DEAD_BASE := {"dead": 68, "dead2": 59, "dead3": 56}
## The standard kinds and the looks each can take.
const STANDARD := {
	"oak": ["std_round_big", "std_round_wide", "std_round_light"],
	"oak2": ["std_round_light", "std_round_small", "std_round_wide"],
	"cherry": ["std_gnarled"],
	"pine": ["std_pine", "std_pine_dark"],
}

@export_enum("oak", "oak2", "cherry", "pine", "dead", "dead2", "dead3",
		"oak_round", "oak_dark", "willow_twisted", "willow_teal", "willow_mossy", "birch_willow",
		"fir", "autumn_round", "autumn_gnarled", "jungle", "pine_small", "apple", "blossom",
		"twisted") var kind := "oak"


func _ready() -> void:
	var s: Sprite2D = $Sprite2D
	var art := kind
	if STANDARD.has(kind):
		var looks: Array = STANDARD[kind]
		var h := absi(int(global_position.x) * 7919 + int(global_position.y) * 104729)
		art = looks[h % looks.size()]
	if TreeArt.has(art):
		TreeArt.apply(s, art)
		set_meta("shadow_scale", TreeArt.shadow_scale(art))
		var trunk := CircleShape2D.new()
		var tall := TreeArt.size(art).y
		trunk.radius = 7.0 if tall > 100.0 else (5.0 if tall > 70.0 else 4.0)
		($CollisionShape2D as CollisionShape2D).shape = trunk
		return
	s.texture = DEAD[kind]
	s.offset = Vector2(0, -DEAD_BASE[kind] / 2.0 + 4)
