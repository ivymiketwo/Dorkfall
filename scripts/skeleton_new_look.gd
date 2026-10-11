extends "res://scripts/skeleton_look.gd"
## The regular skeleton's look: Rex's 4-direction sheet (art/skeleton_new.png, 64 px cells,
## 7 columns, originals in art/skeleton_src). Rows = animation * 4 + facing (down, up,
## left, right). Animations: 0 idle (1 frame), 1 walk (6), 2 attack (6: wind-up, last frame
## is the punch), 3 death (7). Lord Placeholder and the pirates keep their own looks.

const WALK_FPS := 9.0
const DEATH_FPS := 10.0
const ROW_IDLE := 0
const ROW_WALK := 4
const ROW_ATTACK := 8
const ROW_DEATH := 12

var _face := 0
var _dying := -1.0


func _process(delta: float) -> void:
	if _dying >= 0.0:
		_dying += delta
		sprite.frame = (ROW_DEATH + _face) * 7 + mini(int(_dying * DEATH_FPS), 6)
		return
	super(delta)


func _animate(move: Vector2) -> void:
	sprite.flip_h = false
	sprite.rotation = 0.0
	var dir := move
	if brain.is_lunging() or brain.is_winding() or brain.is_recovering():
		dir = brain.lunge_dir
	if dir != Vector2.ZERO:
		if absf(dir.x) > absf(dir.y):
			_face = 2 if dir.x < 0.0 else 3
		else:
			_face = 0 if dir.y > 0.0 else 1
	var row := ROW_IDLE
	var col := 0
	if brain.is_lunging() or brain.is_recovering():
		row = ROW_ATTACK
		col = 5                                   # the punch
	elif brain.is_winding():
		row = ROW_ATTACK                          # wind-up spread over the warning time
		var k: float = 1.0 - brain._winding / maxf(brain.lunge_warn, 0.01)
		col = clampi(int(k * 5.0), 0, 4)
	elif move != Vector2.ZERO:
		row = ROW_WALK
		col = int(_t * WALK_FPS) % 6
	sprite.frame = (row + _face) * 7 + col


func _on_died() -> void:
	# Rex's collapse animation, then fade (the brain waits DEATH_ANIM before counting down)
	_dying = 0.0
	_death_tween = create_tween()
	_death_tween.tween_interval(1.0)
	_death_tween.tween_property(brain, "modulate:a", 0.0, 0.6)


func _on_respawn() -> void:
	_dying = -1.0
	super()
