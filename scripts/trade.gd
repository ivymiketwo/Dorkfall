class_name Trade
extends RefCounted
## Shop buying rules with no UI in them, so a server can run the same checks.
## Returns {"ok": bool, "message": String}. The shop window only shows the message.

const COINS := preload("res://items/coins.tres")


static func buy(inv: Inventory, item: Item) -> Dictionary:
	if item.chase_item and (item.account_has() or inv.count_of(item) > 0):
		return {"ok": false, "message": "You already have one"}
	if inv.count_of(COINS) < item.value:
		return {"ok": false, "message": "Not enough coins"}
	if not inv.has_room_for(item):
		return {"ok": false, "message": "Inventory full"}
	# coins out and item in happen together or not at all
	var done := inv.transact(func() -> bool:
		if not inv.remove(COINS, item.value):
			return false
		return inv.add(item, 1) == 0)
	if not done:
		return {"ok": false, "message": "Could not complete the purchase"}
	return {"ok": true, "message": "Bought " + item.display_name}
