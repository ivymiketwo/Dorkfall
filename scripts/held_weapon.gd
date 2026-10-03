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
const FRAME_PX := 48.0

static var _hands: Dictionary = {}

var body: Sprite2D
## How this item sits in the hand (Item > Hold Style). Null means the default (staff) style.
var style: HoldStyle = HoldStyle.new()
## Item > Hold Scale: shrinks or grows this one item relative to its style.
var item_scale := 1.0
## Item > Hold Grip Offset: art pixels of the item left showing below the hand (+ = hand higher up the item).
var grip_extra := 0.0
var _grip_tex := 0.0           # half the length of the handle section at the bottom of the picture (texture px)
var player: Node2D
var _src: Texture2D
var _crop: AtlasTexture
var _behind := false
var _full_region := Rect2()
var _west := false
var _hand: Sprite2D          # a copy of the hand pixels, drawn on top of the weapon so the hand grips it
const HAND_BOX := 6                    # art px around the hand that get re-drawn over the weapon


func _init() -> void:
	add_to_group("held_weapon")


## Where the orb at the top of the staff is, in global coordinates.
func orb_global() -> Vector2:
	return to_global(Vector2(0.0, offset.y + style.tip_inset))


## Where a beam fired by `caster` should start: the staff's orb when the weapon is out and already posed
## for the direction the caster faces, otherwise a typical idle orb position for that direction.
static func beam_origin(caster: Node2D) -> Vector2:
	var plain := caster.global_position + Vector2(0, -10)
	var facing: int = caster.facing if "facing" in caster else 0
	for n in caster.get_tree().get_nodes_in_group("held_weapon"):
		var w := n as HeldWeapon
		if w == null or w.player != caster:
			continue
		if not w.visible or w.body == null:
			return plain
		if (w.body.frame / w.body.hframes) % 4 == facing:
			return w.orb_global()
		return caster.global_position + w.style.tip_idle[facing]
	return plain


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
		local += Vector2(style.offset_south.x, 0)       # facing south: held a little closer to the body
	if row < 4 and row % 4 == 0:
		local += Vector2(0, style.offset_south.y)       # standing: sits a bit higher
	if row < 4 and row % 4 == 3:
		local += style.offset_east                      # standing facing east
	if row % 4 == 2:
		local += style.offset_west_run
	if row % 4 == 1:
		local += style.offset_north
	position = body.position + local * body.scale
	var facing := row % 4
	rotation_degrees = [style.lean_south, style.lean_north, style.lean_west_run, style.lean_east][facing]
	if row == 2:
		rotation_degrees = -style.lean_east          # west idle: mirror of the east idle angle
		# ...and mirror the east idle position too, so the orb sits just in front of the head
		var he = rows.get("3", [])
		if col < he.size() and he[col] != null:
			var le := Vector2(float(he[col][0]) - FRAME_PX / 2.0, float(he[col][1]) - FRAME_PX / 2.0) + body.offset
			le += style.offset_east
			position = body.position + (Vector2(-le.x, le.y) + style.offset_west) * body.scale
	var jump_pose := Vector3.ZERO
	var has_jump_pose := false
	if row >= 8 and (facing == 2 or facing == 3):
		var table: Array = style.jump_pose_west if facing == 2 else style.jump_pose_east
		var pc: int = style.naked_jump_map[col] if key == "naked" and col < style.naked_jump_map.size() else col
		if pc < table.size():
			jump_pose = table[pc]
			has_jump_pose = true
	_show_top_only(row % 4 == 2)
	var along := style.length_south if facing == 0 else (style.length_north if facing == 1 else 1.0)
	scale = body.scale * style.size_scale * item_scale * Vector2(1.0, along)     # same size in every direction (a rod pointing at / away from the camera is foreshortened)
	var g := style.grip_west_motion if (facing == 2 and row != 2) else style.grip
	if style.grip_from_sprite:
		# melee (1hand) module: measure from the bottom of the picture, in screen art pixels
		var mult := style.size_scale * item_scale * along
		var up_px := _grip_tex * mult + grip_extra
		if facing == 0 and style.butt_overhang_south >= 0.0:
			up_px += style.butt_overhang_south
		g = clampf(1.0 - up_px / maxf(_full_region.size.y * mult, 1.0), 0.0, 1.0)
	elif facing == 0 and style.butt_overhang_south >= 0.0:
		var shown := _full_region.size.y * style.size_scale * item_scale * style.length_south
		g = clampf(1.0 - style.butt_overhang_south / maxf(shown, 1.0), 0.0, 1.0)
	elif facing == 0 and style.grip_south >= 0.0:
		g = style.grip_south
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
	var cover := style.hand_cover_south if facing == 0 else 1.0
	var left := style.hand_cover_left_south if facing == 0 else 0.0
	_hand.region_rect = Rect2(col * FRAME_PX + x0 - left, row * FRAME_PX + y0, HAND_BOX + left, HAND_BOX * cover)
	_hand.position = body.position + (Vector2(x0 - left - FRAME_PX / 2.0, y0 - FRAME_PX / 2.0) + body.offset) * body.scale
	var p := get_parent()
	if p.get_child(p.get_child_count() - 1) != _hand:
		p.move_child(self, p.get_child_count() - 1)
		p.move_child(_hand, p.get_child_count() - 1)


func _show_top_only(on: bool) -> void:
	if on == _west or _crop == null:
		return
	_west = on
	var r := _full_region
	_crop.region = Rect2(r.position, Vector2(r.size.x, r.size.y * style.west_visible_fraction)) if on else r


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
	_grip_tex = _measure_grip(img.get_region(SRC_FRAME), used)
	_crop = AtlasTexture.new()
	_crop.atlas = tex
	_full_region = Rect2(SRC_FRAME.position + used.position, used.size)
	_west = false
	_crop.region = _full_region
	offset = Vector2(-used.size.x / 2.0, -used.size.y * style.grip)   # origin = the grip point
	texture = _crop


## Half the length of the narrow handle section at the bottom of the picture (texture px): the middle of a sword's
## grip under its crossguard. Items without a short handle (a long fishing-rod butt) get 0: held at the very bottom.
func _measure_grip(img: Image, used: Rect2i) -> float:
	var widths: Array[int] = []
	for y in range(used.end.y - 1, used.position.y - 1, -1):
		var n := 0
		for x in range(used.position.x, used.end.x):
			if img.get_pixel(x, y).a > 0.0:
				n += 1
		widths.append(n)
	if widths.is_empty():
		return 0.0
	var ref := widths[0]
	for i in mini(3, widths.size()):
		ref = mini(ref, widths[i])
	var rows := 0
	for w in widths:
		if w <= ref + 1:
			rows += 1
		else:
			break
	return rows * 0.5 if rows <= 4 and rows < widths.size() else 0.0
