extends "res://scripts/skeleton.gd"
## Pirate Captain: same brawler AI as the skeleton (chase, red lane telegraph,
## lunge) but with a 4-direction idle/walk sheet.
## Sheet: art/pirate.png, 64px cells, 10 columns x 4 rows.
## Columns 0-3 idle, 4-9 walk. Rows: down, up, left, right.

var _face := 0


func _animate(move: Vector2) -> void:
	sprite.flip_h = false
	sprite.rotation = 0.0
	var dir := move
	if _lunging > 0.0:
		dir = _lunge_dir
	elif _winding > 0.0:
		dir = _lunge_dir
	if dir != Vector2.ZERO:
		if absf(dir.x) > absf(dir.y):
			_face = 2 if dir.x < 0.0 else 3
		else:
			_face = 0 if dir.y > 0.0 else 1
	var col := 0
	if _lunging > 0.0 or _recover > 0.0:
		col = 6                       # mid-stride pose for the dash
	elif _winding > 0.0:
		col = int(_t * 5.0) % 4       # idle while winding up
	elif move != Vector2.ZERO:
		col = 4 + int(_t * 9.0) % 6
	else:
		col = int(_t * 4.0) % 4
	sprite.frame_coords = Vector2i(col, _face)
