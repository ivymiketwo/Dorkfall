class_name Pickup
extends Area2D
## An item lying on the ground. Walk over it to pick it up.
## The rules of taking it (who, from how close, how much fits) are in LootClaim;
## this node only notices players walking over it and shows the result.

@export var item: Item
@export var count := 1

## Set on drops from monsters. Grab pets only fetch these.
var monster_loot := false
## Instance id of the player this pile belongs to (0 = anyone). See LootClaim.
var owner_id := 0
## GameClock time when anyone may take it.
var public_at := 0.0
## GameClock time it appeared.
var spawned_at := 0.0
var _check := 0.0


func _ready() -> void:
	add_to_group("pickups")
	spawned_at = GameClock.now
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


## Seconds it has been lying there.
func age() -> float:
	return GameClock.now - spawned_at


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_try_pick_up(body, body.global_position)
			return


## Called by a grab pet standing at `from`: picks the pile up for `player`. Returns true if the pile is gone.
func grab_for(player: Node2D, from: Vector2) -> bool:
	_try_pick_up(player, from)
	return not is_inside_tree() or is_queued_for_deletion()


func _try_pick_up(player: Node2D, from: Vector2) -> void:
	var r := LootClaim.claim(self, player, from)
	var at := player.position + Vector2(0, -26)
	if r["taken"] > 0:
		FloatingText.spawn(get_parent(), at, "+%d %s" % [r["taken"], item.display_name.to_upper()], Color("f0d040"))
	if count <= 0:
		queue_free()
		return
	match r["reason"]:
		"full":
			_check = 1.5   # inventory full: don't spam
			FloatingText.spawn(get_parent(), at, "FULL", Color("e03c3c"))
			_refresh()
		"not_yours":
			_check = 1.5
			FloatingText.spawn(get_parent(), at, "NOT YOURS YET", Color("e0e0e0"))


func _refresh() -> void:
	$Sprite2D.frame = item.frame_for(count) if item else 0
