extends "res://scripts/skeleton_look.gd"
## Pirate Captain look: same brain as the skeleton (skeleton.gd) with a 4-direction
## idle/walk sheet. Sheet: art/pirate.png, 64px cells, 10 columns x 4 rows.
## Columns 0-3 idle, 4-9 walk. Rows: down, up, left, right.

var _face := 0


func _animate(move: Vector2) -> void:
	sprite.flip_h = false
	sprite.rotation = 0.0
	var dir := move
	if brain.is_lunging() or brain.is_winding():
		dir = brain.lunge_dir
	if dir != Vector2.ZERO:
		if absf(dir.x) > absf(dir.y):
			_face = 2 if dir.x < 0.0 else 3
		else:
			_face = 0 if dir.y > 0.0 else 1
	var col := 0
	if brain.is_lunging() or brain.is_recovering():
		col = 6                       # mid-stride pose for the dash
	elif brain.is_winding():
		col = int(_t * 5.0) % 4       # idle while winding up
	elif move != Vector2.ZERO:
		col = 4 + int(_t * 9.0) % 6
	else:
		col = int(_t * 4.0) % 4
	sprite.frame_coords = Vector2i(col, _face)

