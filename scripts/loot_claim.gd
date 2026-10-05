class_name LootClaim
extends RefCounted
## The rules for taking items off the ground, with no scenes or visuals in them.
## Everything that moves a ground pile into a bag (walking over it, a grab pet fetching it)
## goes through `claim`, so a server can run it as it is and check every request:
##   - the pile still exists and still has items in it (a pile can only be emptied once),
##   - whoever is taking it is close enough,
##   - the pile is theirs, or its owner lock has run out.
## Items only leave the pile as they go into the bag, so nothing is ever in both places.

## How close (world px) the taker must be. A bit more than the pickup's own radius so
## walking over a pile never gets refused.
const REACH := 20.0
## Monster loot belongs to the top damage dealer for this long, then anyone can take it.
const OWNER_LOCK := 60.0


## Why `player` can't take pile `pk` right now, from position `from`; "" if they can.
static func refusal(pk: Pickup, player: Node, from: Vector2) -> String:
	if pk == null or not is_instance_valid(pk) or pk.is_queued_for_deletion() or pk.item == null or pk.count <= 0:
		return "gone"
	if player == null or player.get_node_or_null("Inventory") == null:
		return "no_bag"
	if from.distance_to(pk.global_position) > REACH:
		return "too_far"
	if pk.owner_id != 0 and pk.owner_id != player.get_instance_id() and not GameClock.passed(pk.public_at):
		return "not_yours"
	return ""


## Moves as much of the pile as fits into `player`'s bag. `from` is where the taker stands
## (the player, or their grab pet). Returns {"taken": int, "left": int, "reason": String}.
static func claim(pk: Pickup, player: Node, from: Vector2) -> Dictionary:
	var why := refusal(pk, player, from)
	if why != "":
		return {"taken": 0, "left": pk.count if why != "gone" else 0, "reason": why}
	var inv := player.get_node("Inventory") as Inventory
	var left := inv.add(pk.item, pk.count)
	var taken := pk.count - left
	pk.count = left
	return {"taken": taken, "left": left, "reason": "" if left == 0 else "full"}


## Who a monster's loot pile belongs to: the top damage dealer, or nobody (0).
static func owner_for(stats: Stats) -> int:
	if stats == null:
		return 0
	var who := KillCredit.eligible(stats)
	return who[0].get_instance_id() if not who.is_empty() else 0
