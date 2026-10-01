class_name HeldWeapon
extends Sprite2D
## The equipped weapon, glued to the player's right hand.
##
## data/hands.json (made by tools/gen_hand_data.py) says where the right hand is in every frame of the
## player sheets, and whether the weapon should be hidden behind the body in that frame (right hand on the
## far side, or no hand visible). Each frame this node moves the weapon to the hand and, when needed, moves
## itself below the body sprite in the draw order so the body covers the part of the weapon it should.
##
## Equipment sets `texture` to the item's worn sheet; this node crops the weapon out of it.

const HANDS_PATH := "res://data/hands.json"
const SRC_FRAME := Rect2i(96, 0, 24, 40)    # standing, facing down, in the old 24x40 worn sheets
const WEST_VISIBLE := 1.0                  # facing west only the top half of the staff shows (the rest is "behind" the body)
const WEST_SHIFT := Vector2(0, 0)         # art px
const SOUTH_SCALE := 1.0
const WEST_SCALE := 1.3
const SOUTH_GRIP := 0.55
const OTHER_GRIP := 0.485                 # keeps the lower end where it was after the size change
const GRIP := 0.33                          # how far down the weapon the hand holds it (0 = tip)
const FRAME_PX := 48.0
## Hand-placed staff pose for every east / west jump frame: (centre x, centre y relative to the body, angle in degrees).
const JUMP_STAFF_W := [Vector3(-3.1, -9.0, -76.4), Vector3(-3.5, -9.5, -85.1), Vector3(-2.0, -6.0, -83.9), Vector3(-0.5, -19.5, -91.1), Vector3(-0.5, -18.8, -92.3), Vector3(-3.4, -13.9, -88.2), Vector3(-2.5, -6.6, -88.1), Vector3(-3.0, -7.4, -68.3)]
const JUMP_STAFF_E := [Vector3(-3.4, -7.2, 73.5), Vector3(-3.6, -7.8, 77.9), Vector3(-2.2, -6.5, 87.8), Vector3(-0.5, -19.8, 80.8), Vector3(-0.5, -18.8, 87.9), Vector3(-1.5, -13.9, 89.5), Vector3(-1.0, -6.4, 92.5), Vector3(-4.1, -4.5, 72.5)]
const LEAN := [-5.0, 5.0, -35.0, 15.0]    # degrees per facing (down, up, left, right): the top leans forward / outward

static var _hands: Dictionary = {}

var body: Sprite2D
var player: Node2D
var _src: Texture2D
var _crop: AtlasTexture
var _behind := false
var _full_region := Rect2()
var _west := false
var _hand: Sprite2D          # a copy of the hand pixels, drawn on top of the weapon so the hand grips it
const HAND_BOX := 6                    # art px around the hand that get re-drawn over the weapon


func _ready() -> void:
	if _hands.is_empty():
		var f := FileAccess.open(HANDS_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_hands = parsed
	centered = false
	hframes = 1
	vframes = 1
	offset = Vector2.ZERO
	scale = body.scale
	_hand = Sprite2D.new()
	_hand.name = "HeldWeaponHand"
	_hand.centered = false
	_hand.region_enabled = true
	_hand.scale = body.scale
	_hand.visible = false
	get_parent().add_child.call_deferred(_hand)


func _process(_delta: float) -> void:
	if texture != _crop:
		_rebuild(texture)
	if _crop == null or body == null:
		return
	var key := "robe" if body.texture.resource_path.ends_with("player_new_robe.png") else "naked"
	var cols := body.hframes
	var row := body.frame / cols
	var col := body.frame % cols
	var rows: Dictionary = _hands.get(key, {})
	var entry = rows.get(str(row), [])
	var h = entry[col] if col < entry.size() else null
	if h == null:
		visible = false
		return
	visible = true
	var local := Vector2(float(h[0]) - FRAME_PX / 2.0, float(h[1]) - FRAME_PX / 2.0) + body.offset
	if row % 4 == 0:
		local += Vector2(2, 0)             # facing south: hold it a little closer to the body
	if row < 4 and (row % 4 == 0 or row % 4 == 3):
		local += Vector2(0, -3 - (4 if row % 4 == 0 else 0))
		if row % 4 == 3:
			local += Vector2(2, 0)     # facing east: 2 art px to the right            # standing facing south / east: the staff sits a bit higher
	if row % 4 == 2:
		local += WEST_SHIFT      # facing west: hold it a bit forward so the top pokes out in front of the shoulder
	position = body.position + local * body.scale
	var facing := row % 4
	rotation_degrees = LEAN[facing]
	if row == 2:
		rotation_degrees = -LEAN[3]          # west idle: mirror of the east idle angle
	var jump_pose := Vector3.ZERO
	var has_jump_pose := false
	if row >= 8 and (facing == 2 or facing == 3):
		var table: Array = JUMP_STAFF_W if facing == 2 else JUMP_STAFF_E
		if col < table.size():
			jump_pose = table[col]
			has_jump_pose = true
	_show_top_only(row % 4 == 2)
	# facing south the staff is drawn taller (top above the head) and held nearer its middle
	scale = body.scale * WEST_SCALE     # same staff size in every direction
	var g := SOUTH_GRIP if facing == 2 else OTHER_GRIP
	offset = Vector2(-_full_region.size.x / 2.0, -_full_region.size.y * g)
	if has_jump_pose:
		rotation_degrees = jump_pose.z
		var up := Vector2(0, -1).rotated(deg_to_rad(jump_pose.z))
		var length := _full_region.size.y * scale.y
		position = body.position + Vector2(jump_pose.x, jump_pose.y) + up * (0.5 - g) * length
	var behind := int(h[2]) == 1
	_set_behind(behind)
	_update_hand(facing, col, row, h, behind)


## Facing down or right the weapon is held in front of the body, so re-draw the hand over it:
## the hand sits in front of the staff and the rest of the body behind it.
func _update_hand(facing: int, col: int, row: int, h: Array, behind: bool) -> void:
	if _hand == null or _hand.get_parent() == null:
		return
	var on := (facing == 0 or facing == 3) and not behind
	_hand.visible = on
	if not on:
		return
	var half := HAND_BOX / 2.0
	var x0 := clampf(float(h[0]) - half, 0.0, FRAME_PX - HAND_BOX)
	var y0 := clampf(float(h[1]) - half, 0.0, FRAME_PX - HAND_BOX)
	_hand.texture = body.texture
	_hand.region_rect = Rect2(col * FRAME_PX + x0, row * FRAME_PX + y0, HAND_BOX, HAND_BOX)
	_hand.position = body.position + (Vector2(x0 - FRAME_PX / 2.0, y0 - FRAME_PX / 2.0) + body.offset) * body.scale
	var p := get_parent()
	if p.get_child(p.get_child_count() - 1) != _hand:
		p.move_child(self, p.get_child_count() - 1)
		p.move_child(_hand, p.get_child_count() - 1)


func _show_top_only(on: bool) -> void:
	if on == _west or _crop == null:
		return
	_west = on
	var r := _full_region
	_crop.region = Rect2(r.position, Vector2(r.size.x, r.size.y * WEST_VISIBLE)) if on else r


func _set_behind(b: bool) -> void:
	if b == _behind:
		return
	_behind = b
	var parent := get_parent()
	if parent == null or body == null:
		return
	if b:
		parent.move_child(self, mini(body.get_index(), get_index()))   # drawn before (under) the body
	else:
		parent.move_child(self, parent.get_child_count() - 1)


func _rebuild(tex: Texture2D) -> void:
	_src = tex
	_crop = null
	if tex == null:
		texture = null
		return
	var img := tex.get_image()
	var used := img.get_region(SRC_FRAME).get_used_rect()
	if used.size == Vector2i.ZERO:
		texture = null
		return
	_crop = AtlasTexture.new()
	_crop.atlas = tex
	_full_region = Rect2(SRC_FRAME.position + used.position, used.size)
	_west = false
	_crop.region = _full_region
	offset = Vector2(-used.size.x / 2.0, -used.size.y * GRIP)   # origin = the grip point
	texture = _crop
