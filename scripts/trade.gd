class_name Trade
extends RefCounted
## Shop buying and selling rules with no UI in them, so a server can run the same checks.
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


## Most one sale can move, so a bad request can never ask for a silly amount.
const MAX_SELL := 9999


## Why an item can't be sold ("" = it can).
static func unsellable_reason(item: Item) -> String:
	if item == null or item == COINS:
		return "Coins can't be sold"
	if item.soulbound or item.chase_item:
		return "Account bound: can't be sold"
	return ""


## What a vendor pays for one `item` (0 = it won't buy it): the item's own Sell Price, or a quarter
## of its shop price (at least 1) if none is set. The price only ever comes from the item's data:
## nothing the player sends is trusted.
static func sell_price(_shop: Shop, item: Item) -> int:
	if unsellable_reason(item) != "":
		return 0
	if item.sell_price > 0:
		return item.sell_price
	return maxi(item.value / 4, 1)


## Sells up to `amount` of `item` from the bag to `shop`.
## Returns {"ok", "message", "sold", "earned"}. Dupe-safe by construction:
##  - the amount is clamped to what is really in the bag (never trusts the request),
##  - the items leave and the coins arrive in ONE all-or-nothing transaction,
##  - coins are counted before and after, so the total can only go up by exactly sold x price.
## On a server this is the function the "sell" request runs; the client only shows the result.
static func sell(inv: Inventory, shop: Shop, item: Item, amount: int = 1) -> Dictionary:
	var price := sell_price(shop, item)
	if price <= 0:
		return {"ok": false, "message": unsellable_reason(item), "sold": 0, "earned": 0}
	var n := mini(mini(amount, MAX_SELL), inv.count_of(item))
	if n <= 0:
		return {"ok": false, "message": "You don't have any", "sold": 0, "earned": 0}
	var earned := n * price
	var coins_before := inv.count_of(COINS)
	if coins_before > COINS.max_stack - earned:
		return {"ok": false, "message": "You can't carry that many coins", "sold": 0, "earned": 0}
	var items_before := inv.count_of(item)
	var done := inv.transact(func() -> bool:
		if not inv.remove(item, n):
			return false
		if inv.add(COINS, earned) != 0:
			return false
		# final ledger check: exactly n items gone, exactly `earned` coins gained
		return inv.count_of(item) == items_before - n and inv.count_of(COINS) == coins_before + earned)
	if not done:
		return {"ok": false, "message": "No room for the coins", "sold": 0, "earned": 0}
	return {"ok": true, "message": "Sold %d %s for %d coins" % [n, item.display_name, earned], "sold": n, "earned": earned}
