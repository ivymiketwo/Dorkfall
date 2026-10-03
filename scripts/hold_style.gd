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
## Extra nudges: standing west (applied after the east mirror), and facing north.
@export var offset_west := Vector2.ZERO
@export var offset_north := Vector2.ZERO
## Facing south only: grip fraction override (-1 = use `grip`), and how much of the hand is re-drawn over the
## item (1 = the whole hand sits on top, 0.5 = the item covers the bottom half of the hand).
@export var grip_south := -1.0
## Better than `grip_south` for items of any length: how many art pixels of the handle's end stick out past the
## hand when facing south (-1 = off). The grip is worked out from the item's drawn length.
@export var butt_overhang_south := -1.0
@export_range(0.0, 1.0) var hand_cover_south := 1.0
## Facing south: how many art pixels further left the re-drawn hand patch reaches (so an item nudged left stays under the hand).
@export var hand_cover_left_south := 0.0

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
## The standard style for the "handle at the bottom" preset (fishing rods, swords, anything gripped at the butt).
const BOTTOM_GRIP := "res://hold_styles/bottom_grip.tres"


## Which style an item is held with: its own Hold Style, else the bottom-grip preset for every ONE-HANDED
## weapon (swords, fishing rods, axes... anything with its handle at the bottom) and for any item with the
## `handle_at_bottom` box ticked, else the standard style for its weapon type (two-handed staves).
static func for_item(item: Item) -> HoldStyle:
	if item == null:
		return HoldStyle.new()
	if item.hold_style != null:
		return item.hold_style
	var one_handed_weapon := item.equip_slot == "weapon" and not item.two_handed
	if (item.handle_at_bottom or one_handed_weapon) and ResourceLoader.exists(BOTTOM_GRIP):
		var r := load(BOTTOM_GRIP) as HoldStyle
		if r != null:
			return r
	return for_kind(item.weapon_kind)


static func for_kind(kind: String) -> HoldStyle:
	var path := "res://hold_styles/%s.tres" % kind
	if ResourceLoader.exists(path):
		var r := load(path) as HoldStyle
		if r != null:
			return r
	return HoldStyle.new()
