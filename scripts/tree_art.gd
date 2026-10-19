class_name TreeArt
## Rex's big forest trees (art/trees/), shared by single trees (tree.gd) and forests (forest.gd).
## Drawn one picture pixel per world pixel, like the buildings, so a 128 px tree is about as tall
## as a cottage. "base" is where the trunk meets the ground in the picture: the tree's position.

const KINDS := {
	"oak_round": {"tex": preload("res://art/trees/oak_round.png"), "base": Vector2(63, 120)},
	"oak_dark": {"tex": preload("res://art/trees/oak_dark.png"), "base": Vector2(63, 120)},
	"willow_twisted": {"tex": preload("res://art/trees/willow_twisted.png"), "base": Vector2(63, 122)},
	"willow_teal": {"tex": preload("res://art/trees/willow_teal.png"), "base": Vector2(63, 121)},
	"willow_mossy": {"tex": preload("res://art/trees/willow_mossy.png"), "base": Vector2(61, 120)},
	"birch_willow": {"tex": preload("res://art/trees/birch_willow.png"), "base": Vector2(64, 120)},
	"fir": {"tex": preload("res://art/trees/fir.png"), "base": Vector2(64, 120)},
	"autumn_round": {"tex": preload("res://art/trees/autumn_round.png"), "base": Vector2(61, 119)},
	"autumn_gnarled": {"tex": preload("res://art/trees/autumn_gnarled.png"), "base": Vector2(61, 122)},
	# the smaller ones (80 px)
	"jungle": {"tex": preload("res://art/trees/jungle.png"), "base": Vector2(39, 77)},
	"pine_small": {"tex": preload("res://art/trees/pine_small.png"), "base": Vector2(40, 77)},
	"apple": {"tex": preload("res://art/trees/apple.png"), "base": Vector2(40, 76)},
	"blossom": {"tex": preload("res://art/trees/blossom.png"), "base": Vector2(40, 77)},
	"twisted": {"tex": preload("res://art/trees/twisted.png"), "base": Vector2(41, 77)},
}


static func has(kind: String) -> bool:
	return KINDS.has(kind)


## Sets up a Sprite2D to show this tree with its trunk base at the sprite's position.
static func apply(s: Sprite2D, kind: String) -> void:
	var k: Dictionary = KINDS[kind]
	s.texture = k.tex
	s.centered = false
	s.scale = Vector2.ONE
	s.offset = -(k.base as Vector2)


## How much bigger than an old tree this one's shadow should be.
static func shadow_scale(kind: String) -> float:
	var t: Texture2D = KINDS[kind].tex
	return 2.4 if t.get_height() > 100 else 1.6
