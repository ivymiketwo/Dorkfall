@tool
extends StaticBody2D
## Scenery from the decor art: stalls, bushes, signs, benches and so on.
## Pick with `kind`. Bushes have no collision, so they never get in the way of walking or spells.

const KINDS := {
	"stall_red": ["res://art/stall_red.png", Vector2(30, 5), true],
	"stall_blue": ["res://art/stall_blue.png", Vector2(30, 5), true],
	"bush": ["res://art/bush.png", Vector2.ZERO, true],
	"bush_pink": ["res://art/bush_pink.png", Vector2.ZERO, true],
	"bush_yellow": ["res://art/bush_yellow.png", Vector2.ZERO, true],
	"house_brick": ["res://art/house_brick.png", Vector2(80, 14), true],
	"house_pink": ["res://art/house_pink.png", Vector2(76, 14), true],
	"house_blue": ["res://art/house_blue.png", Vector2(74, 14), true],
	"sign": ["res://art/sign.png", Vector2(3, 3), true],
	"bench": ["res://art/bench.png", Vector2(20, 5), true],
	"haybale": ["res://art/haybale.png", Vector2(16, 6), true],
	"planter": ["res://art/planter.png", Vector2(10, 4), true],
	"sacks": ["res://art/sacks.png", Vector2(14, 2), true],
	"grave_round": ["res://art/grave_round.png", Vector2(10, 4), true],
	"grave_cross": ["res://art/grave_cross.png", Vector2(12, 4), true],
	"grave_obelisk": ["res://art/grave_obelisk.png", Vector2(10, 4), true],
	"grave_broken": ["res://art/grave_broken.png", Vector2(10, 4), true],
	"grave_mound": ["res://art/grave_mound.png", Vector2.ZERO, true],
	"wfence_a": ["res://art/wfence_a.png", Vector2(16, 3), true],
	"wfence_b": ["res://art/wfence_b.png", Vector2(16, 3), true],
	"wfence_c": ["res://art/wfence_c.png", Vector2(16, 3), true],
	"wfence_d": ["res://art/wfence_d.png", Vector2(16, 3), true],
	"wfence_side_a": ["res://art/wfence_side_a.png", Vector2(4, 16), true],
	"wfence_side_b": ["res://art/wfence_side_b.png", Vector2(4, 16), true],
	"wfence_side_c": ["res://art/wfence_side_c.png", Vector2(4, 16), true],
	"wgate_post": ["res://art/wgate_post.png", Vector2(6, 4), true],
	"wgate_leaf_h": ["res://art/wgate_leaf_h.png", Vector2(16, 3), true],
	"wgate_leaf_v": ["res://art/wgate_leaf_v.png", Vector2(4, 10), true],
	"fence_seg": ["res://art/fence_seg.png", Vector2(16, 3), true],
	"fence_post": ["res://art/fence_post.png", Vector2(4, 3), true],
	"fence_pillar": ["res://art/fence_pillar.png", Vector2(7, 4), true],
	"cave_rock1": ["res://art/cave_rock1.png", Vector2.ZERO, true],
	"cave_rock2": ["res://art/cave_rock2.png", Vector2.ZERO, true],
	"cave_stalag": ["res://art/cave_stalag.png", Vector2.ZERO, true],
	"cave_bones": ["res://art/cave_bones.png", Vector2.ZERO, true],
	"cave_crystal": ["res://art/cave_crystal.png", Vector2.ZERO, true],
	"cactus_a": ["res://art/cactus_a.png", Vector2(6, 3), true],
	"cactus_b": ["res://art/cactus_b.png", Vector2(6, 3), true],
	"cactus_c": ["res://art/cactus_c.png", Vector2(6, 3), true],
	"warn_sign_skull": ["res://art/warn_sign_skull.png", Vector2(4, 3), true],
	"warn_sign_x": ["res://art/warn_sign_x.png", Vector2(4, 3), true],
	"warn_sign_bang": ["res://art/warn_sign_bang.png", Vector2(4, 3), true],
	"warn_sign_arrow": ["res://art/warn_sign_arrow.png", Vector2(4, 3), true],
}

@export var kind := "bush":
	set(value):
		kind = value
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


## Builds the picture and collision. @tool, so the pieces also show up in the editor
## (they are not owned by the scene, so they are never saved into it).
func _build() -> void:
	for c in get_children():
		if c.has_meta("decor_part"):
			remove_child(c)
			c.queue_free()
	if not KINDS.has(kind):
		return
	var spec: Array = KINDS[kind]
	var tex: Texture2D = load(spec[0])
	var s := Sprite2D.new()
	s.set_meta("decor_part", true)
	s.texture = tex
	s.scale = Vector2(0.5, 0.5)
	s.offset = Vector2(0, -tex.get_height() / 2.0 + 4)
	add_child(s)
	if spec[1] == Vector2.ZERO:
		return
	var cs := CollisionShape2D.new()
	cs.set_meta("decor_part", true)
	var r := RectangleShape2D.new()
	r.size = spec[1]
	cs.shape = r
	cs.position = Vector2(0, -r.size.y / 2.0)
	add_child(cs)
