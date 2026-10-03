class_name Pickup
extends Area2D
## An item lying on the ground. Walk over it to pick it up.

@export var item: Item
@export var count := 1

## Set on drops from monsters. Grab pets only fetch these.
var monster_loot := false
var age := 0.0
var _check := 0.0


func _ready() -> void:
	add_to_group("pickups")
	# always match the icon sheet (32px frames), so adding icons can't misalign ground items again
	var sheet: Sprite2D = $Sprite2D
	sheet.hframes = maxi(sheet.texture.get_width() / 32, 1)
	_refresh()
	# little hop when it appears
	var sprite: Sprite2D = $Sprite2D
	var base := sprite.position.y
	sprite.position.y = base - 10.0
	create_tween().tween_property(sprite, "position:y", base, 0.3) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	age += delta
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_try_pick_up(body)
			return


## Called by a grab pet: picks the pile up for `player`. Returns true if the pile is gone.
func grab_for(player: Node2D) -> bool:
	_try_pick_up(player)
	return not is_inside_tree() or is_queued_for_deletion()


func _try_pick_up(player: Node2D) -> void:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or item == null:
		return
	var left := inv.add(item, count)
	var taken := count - left
	if taken > 0:
		FloatingText.spawn(get_parent(), player.position + Vector2(0, -26),
				"+%d %s" % [taken, item.display_name.to_upper()], Color("f0d040"))
	count = left
	if count <= 0:
		queue_free()
	else:
		_check = 1.5   # inventory full: don't spam
		FloatingText.spawn(get_parent(), player.position + Vector2(0, -26), "FULL", Color("e03c3c"))
		_refresh()


func _refresh() -> void:
	$Sprite2D.frame = item.frame_for(count) if item else 0
