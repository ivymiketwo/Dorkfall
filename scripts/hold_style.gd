class_name HoldStyle
extends Resource
## How one held item (staff, sword, torch...) sits in the character's right hand.
##
## Every number here is a tweak on top of the shared hand tracking in held_weapon.gd, which already
## follows the hand in every animation frame. The defaults are the wooden staff's values, so a new
## weapon starts as a staff and you only change what looks wrong. Give an Item its own HoldStyle
## (Item > Hold Style) to override. Distances are art pixels (the 48x48 sheet) unless noted.

@export_group("Size and grip")
## Drawn size relative to the 24x40 worn art.
@export var size_scale := 1.3
## Length multipliers along the item when facing south / north. A rod held pointing at the camera (south) or away
## from it (north) looks shorter on screen. 1 = no change.
@export var length_south := 1.0
@export var length_north := 1.0
## How far down the item the hand holds it (0 = the very tip, 1 = the bottom end). Used standing and running.
@export var grip := 0.485
## Same, but while running or jumping west (hand on the far side of the body).
@export var grip_west_motion := 0.55
## Facing west while moving, only this top fraction of the item is drawn (1 = all of it; the body covers the rest).
@export_range(0.1, 1.0) var west_visible_fraction := 1.0

@export_group("Angle")
## Degrees from upright. Positive leans the top to the right of the screen.
@export var lean_south := -5.0
@export var lean_north := 5.0
@export var lean_east := 15.0
## Running west. (Standing west is the mirror of lean_east.)
@export var lean_west_run := -35.0

@export_group("Standing and running offsets")
## Nudges from the hand position.
@export var offset_south := Vector2(2, -7)
@export var offset_east := Vector2(2, -3)
@export var offset_west_run := Vector2.ZERO

@export_group("Jumping")
## One hand-placed pose per frame of the east / west jump (robed frames): x, y from the character's origin in
## world units, and the angle in degrees. East and west are separate because west is drawn behind the body.
@export var jump_pose_east: Array[Vector3] = [Vector3(-3.67, -4.21, 75.5), Vector3(-2.83, -4.39, 78.1), Vector3(-3.11, -1.59, 84.1), Vector3(-2.20, -12.75, 81.6), Vector3(-3.91, -14.30, 87.7), Vector3(-3.21, -5.37, 85.4), Vector3(-1.51, 1.18, 85.3), Vector3(-3.28, -2.64, 73.2)]
@export var jump_pose_west: Array[Vector3] = [Vector3(-3.1, -9.0, -76.4), Vector3(-3.5, -9.5, -85.1), Vector3(-2.0, -6.0, -83.9), Vector3(-0.5, -19.5, -91.1), Vector3(-0.5, -18.8, -92.3), Vector3(-3.4, -13.9, -88.2), Vector3(-2.5, -6.6, -88.1), Vector3(-3.0, -7.4, -68.3)]
## The naked jump has 9 frames, the robed one 8: which robed frame's pose each naked frame uses.
@export var naked_jump_map := PackedInt32Array([0, 1, 2, 3, 4, 4, 5, 6, 7])

@export_group("Magic effects")
## Where beams leave from, measured down from the top of the item, in art pixels (the staff's orb).
@export var tip_inset := 4.0
## Typical tip position from the character's feet, per facing (south, north, west, east), in world units.
## Only used for the one shot fired while turning, before the item has swung to its new pose.
@export var tip_idle := PackedVector2Array([Vector2(-4.2, -17.5), Vector2(4.9, -17.0), Vector2(-3.8, -15.5), Vector2(3.8, -15.5)])


## The standard style for a weapon type: res://hold_styles/<weapon_kind>.tres when there is one (edit that file
## to change how every weapon of that type is held), otherwise the defaults above. An Item's own
## Hold Style, if set, wins over this.
static func for_kind(kind: String) -> HoldStyle:
	var path := "res://hold_styles/%s.tres" % kind
	if ResourceLoader.exists(path):
		var r := load(path) as HoldStyle
		if r != null:
			return r
	return HoldStyle.new()
