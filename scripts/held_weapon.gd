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
const GRIP := 0.55                          # how far down the weapon the hand holds it (0 = tip)
const FRAME_PX := 48.0

static var _hands: Dictionary = {}

var body: Sprite2D
var player: Node2D
var _src: Texture2D
var _crop: AtlasTexture
var _behind := false


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
	position = body.position + local * body.scale
	_set_behind(int(h[2]) == 1)


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
	_crop.region = Rect2(SRC_FRAME.position + used.position, used.size)
	offset = Vector2(-used.size.x / 2.0, -used.size.y * GRIP)   # origin = the grip point
	texture = _crop
