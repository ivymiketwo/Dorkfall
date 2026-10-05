class_name UniqueDrop
extends RefCounted
## Chase-item drops (pets and other one-per-account rewards) from bosses.
## Rolled once per kill for whoever landed the last hit. An account can only ever
## receive each chase item once: after that, hitting the drop table again only
## gets a "special feeling" message in chat.

const FEELING := "You have a feeling you would've got something special..."


static func roll(killer: Node, item: Item, chance: float) -> void:
	if item == null or killer == null or not killer.is_in_group("player"):
		return
	if not Rng.chance(chance):
		return
	var tree := killer.get_tree()
	if item.chase_item and item.account_has():
		ChatLog.say(tree, FEELING, Color("c9a0ff"))
		return
	var inv := killer.get_node_or_null("Inventory") as Inventory
	var world := killer.get_parent()
	if item.pet_scene and (inv == null or not inv.has_room_for(item)):
		# Bag full: the pet just comes out and follows you, so it can never be lost.
		SaveGame.batch(func() -> void:
			item.mark_account()
			var pet: Node2D = item.pet_scene.instantiate()
			pet.item = item
			pet.set("owner_id", killer.get_instance_id())
			pet.position = killer.position + Vector2(10, 2)
			world.add_child(pet)
			Pet._save_all(tree))
	elif inv != null and inv.has_room_for(item):
		inv.add(item, 1)
	else:
		# Not a pet and the bag is full: leave it at their feet.
		var pk: Node2D = load("res://scenes/pickup.tscn").instantiate()
		pk.item = item
		pk.position = killer.position + Vector2(0, 6)
		world.add_child(pk)
	FloatingText.spawn(world, killer.position + Vector2(0, -34), "SPECIAL DROP!", Color("c9a0ff"))
	ChatLog.say(tree, "You received a special drop: %s!" % item.display_name, Color("c9a0ff"))
