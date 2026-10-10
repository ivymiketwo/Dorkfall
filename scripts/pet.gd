class_name Pet
extends CharacterBody2D
## A follower. Trots after the player. Right-click it to pick it back up.

## The item this pet turns back into when picked up.
@export var item: Item
@export var speed := 110.0
@export var follow_distance := 22.0
## Grab pets run to monster loot and pick it up for you.
@export var grabs_loot := false
## Seconds a drop has to sit on the ground before the pet goes for it.
@export var loot_delay := 1.0
## Seconds the pet rests after each pile.
@export var loot_cooldown := 0.25
@export var loot_range := 260.0   ## (unused: loot must be on screen now)
@export var leash_range := 150.0   ## a grab pet never runs further than this from its owner

## How close the owner must be to put the pet back in the bag.
const RECALL_RANGE := 200.0

var _t := 0.0
var _row := 0            ## sprite row: 0 = facing the camera (south), 1 = away (north), 2 = left, 3 = right
var _rest := 0.0
var _target: Pickup
var _skip := {}     ## pickups it gave up on (inventory full) -> ignore until
## Instance id of the player it belongs to (0 = the local player, for older saves).
var owner_id := 0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("pets")
	_save_all.call_deferred(get_tree())


## Remembers which pets are out (so they are still there next time you play).
static func _save_all(tree: SceneTree) -> void:
	if tree == null:
		return
	var out: Array = []
	for n in tree.get_nodes_in_group("pets"):
		var pet := n as Pet
		if pet != null and pet.item != null and not pet.is_queued_for_deletion():
			if pet.item.chase_item:
				pet.item.mark_account()   # (covers pets from before this rule existed)
			var path := SaveGame.item_to_path(pet.item)
			if path != "":
				out.append(path)
	SaveGame.put("pets", out)


## The rules of letting a pet out of the bag (no visuals). The pet record is written and the
## bag slot cleared in ONE save, so the pet is never both in the bag and out. Returns the pet or null.
static func summon(player: Node2D, slot: int) -> Pet:
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or inv.prepare_drop(slot) != "pet":
		return null
	var item := inv.items[slot]
	return SaveGame.batch(func() -> Pet:
		var pet := item.pet_scene.instantiate() as Pet
		if pet == null:
			return null
		pet.item = item
		pet.owner_id = player.get_instance_id()
		pet.position = player.position + Vector2(10, 2)
		player.get_parent().add_child(pet)
		Pet._save_all(player.get_tree())
		inv.clear_slot(slot)
		return pet)


## Why `player` can't put this pet back in their bag; "" if they can.
func recall_refusal(player: Node2D) -> String:
	var inv: Inventory = player.get_node_or_null("Inventory") as Inventory if player else null
	if inv == null or item == null or is_queued_for_deletion():
		return "gone"
	if _owner() != player:
		return "not_yours"
	if global_position.distance_to(player.global_position) > RECALL_RANGE:
		return "too_far"
	if not inv.has_room_for(item):
		return "full"
	return ""


## The rules of putting the pet back in the bag (no visuals). The pet leaves the saved pet
## list and enters the bag in ONE save. Returns "" on success, or why not.
func recall(player: Node2D) -> String:
	var why := recall_refusal(player)
	if why != "":
		return why
	SaveGame.batch(func() -> void:
		var inv := player.get_node("Inventory") as Inventory
		queue_free()
		Pet._save_all(get_tree())   # already skips this pet (queued for deletion)
		inv.add(item, 1))
	return ""


## The player this pet follows.
func _owner() -> Node2D:
	var o := instance_from_id(owner_id) as Node2D if owner_id != 0 else null
	return o if o != null and is_instance_valid(o) else Players.local(get_tree())


## Brings saved pets back next to the player when the game starts.
static func restore(player: Node2D) -> void:
	var saved = SaveGame.get_value("pets", [])
	if not (saved is Array):
		return
	var n := 0
	for path in saved:
		var it := SaveGame.item_from_path(str(path))
		if it == null or it.pet_scene == null:
			continue
		var pet: Node2D = it.pet_scene.instantiate()
		pet.item = it
		pet.owner_id = player.get_instance_id()
		pet.position = player.position + Vector2(10 + n * 8, 2 + n * 3)
		player.get_parent().add_child(pet)
		n += 1


func _physics_process(delta: float) -> void:
	var player := _owner()
	if player == null:
		return
	var to := player.global_position - global_position
	var dist := to.length()
	if dist > 300.0:      # got stuck or left far behind
		global_position = player.global_position + Vector2(14, 4)
		reset_physics_interpolation()
		return
	if grabs_loot:
		_rest = maxf(_rest - delta, 0.0)
		if _fetch_loot(player, delta):
			return
	if dist > follow_distance:
		velocity = to.normalized() * clampf((dist - follow_distance) * 4.0 + 30.0, 30.0, speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
	move_and_slide()
	if velocity.length() > 8.0:
		_t += delta
		_face(velocity)
		sprite.frame = _row * 7 + int(_t * 10.0) % 6     # 6-frame walk cycle
	else:
		sprite.frame = _row * 7 + 6                      # standing


## Returns true while the pet is busy running to a pile.
func _fetch_loot(player: Node2D, delta: float) -> bool:
	if _rest > 0.0:
		_target = null
		return false
	if _target != null and (not is_instance_valid(_target) or _target.is_queued_for_deletion()):
		_target = null
	if _target != null and (not _on_screen(_target.global_position, player) or global_position.distance_to(player.global_position) > leash_range):
		_target = null          # off screen or past the leash: give up and come home
		_rest = loot_cooldown
		return false
	if _target == null:
		var best := INF
		for n in get_tree().get_nodes_in_group("pickups"):
			var pk := n as Pickup
			if pk == null or not pk.monster_loot or pk.age() < loot_delay:
				continue
			if LootClaim.refusal(pk, player, pk.global_position) != "":
				continue   # someone else's pile (or already gone)
			if _skip.get(pk, 0.0) > GameClock.now:
				continue
			if not _on_screen(pk.global_position, player):
				continue
			if pk.global_position.distance_to(player.global_position) > leash_range:
				continue
			var d := global_position.distance_to(pk.global_position)
			if d < best:
				best = d
				_target = pk
	if _target == null:
		return false
	var to := _target.global_position - global_position
	if to.length() < 8.0:
		var pk := _target
		_target = null
		var gone := pk.grab_for(player, global_position)
		if not gone:
			_skip[pk] = GameClock.now + 8.0   # bag full: leave it
		_rest = loot_cooldown
		return false
	velocity = to.normalized() * speed * 1.5
	move_and_slide()
	_t += delta
	_face(velocity)
	sprite.frame = _row * 7 + int(_t * 14.0) % 6     # runs the same cycle, faster
	return true


## True if a world point is inside what the player's camera can see right now.
func _on_screen(p: Vector2, player: Node2D) -> bool:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	var zoom := cam.zoom if cam != null else Vector2(2, 2)
	var half := get_viewport().get_visible_rect().size / zoom * 0.5 - Vector2(10, 10)
	var c := cam.get_screen_center_position() if cam != null else player.global_position
	return absf(p.x - c.x) <= half.x and absf(p.y - c.y) <= half.y


## Picks the sprite row from the direction of travel.
func _face(v: Vector2) -> void:
	if absf(v.y) > absf(v.x) * 1.2:
		_row = 0 if v.y > 0.0 else 1
	elif absf(v.x) > 4.0:
		_row = 2 if v.x < 0.0 else 3


## Jumps to the player's side (used after the player respawns).
func join_player(player: Node2D, n := 0) -> void:
	global_position = player.global_position + Vector2(12 + n * 8, 4 + n * 3)
	reset_physics_interpolation()
	velocity = Vector2.ZERO
	_target = null
	_rest = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if get_global_mouse_position().distance_to(global_position + Vector2(0, -6)) < 10.0:
			var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
			if menu:
				var label := "PICK UP " + (item.display_name.to_upper() if item else "PET")
				menu.open_at_screen(get_viewport().get_mouse_position(),
						[{"label": label, "callback": _pick_up}])
				get_viewport().set_input_as_handled()


func _pick_up() -> void:
	var player := _owner()
	if player == null:
		return
	var why := recall(player)
	if why == "full":
		FloatingText.spawn(get_parent(), player.position + Vector2(0, -26), "INVENTORY FULL", Color("e03c3c"))
	elif why == "too_far":
		FloatingText.spawn(get_parent(), player.position + Vector2(0, -26), "TOO FAR AWAY", Color("e0e0e0"))
