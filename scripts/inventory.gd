class_name Inventory
extends Node
## 28 slots, RuneScape style. Stackable items (coins) merge into one slot.
## Lives as a child of the player.

signal changed

const SLOT_COUNT := 28

var items: Array[Item] = []
var counts: Array[int] = []
## Per-item use cooldowns (Item -> seconds left).
var item_cd := {}


func _ready() -> void:
	items.resize(SLOT_COUNT)
	counts.resize(SLOT_COUNT)
	_load_saved()
	changed.connect(_save)


func _process(delta: float) -> void:
	for it in item_cd.keys():
		item_cd[it] -= delta
		if item_cd[it] <= 0.0:
			item_cd.erase(it)


func cooldown_of(item: Item) -> float:
	return item_cd.get(item, 0.0)


func _save() -> void:
	SaveGame.put("inventory", snapshot())


## The whole bag as plain data (what gets saved, and what a server would store).
func snapshot() -> Array:
	var out := []
	for i in SLOT_COUNT:
		if items[i] == null or SaveGame.item_to_path(items[i]) == "":
			out.append(null)
		else:
			out.append({"item": SaveGame.item_to_path(items[i]), "count": counts[i]})
	return out


func load_snapshot(saved: Array) -> void:
	for i in SLOT_COUNT:
		items[i] = null
		counts[i] = 0
	for i in mini(saved.size(), SLOT_COUNT):
		var e = saved[i]
		if not e is Dictionary:
			continue
		var it := SaveGame.item_from_path(str(e.get("item", "")))
		if it:
			items[i] = it
			counts[i] = maxi(int(e.get("count", 1)), 1)
	changed.emit()


func _load_saved() -> void:
	var saved = SaveGame.get_value("inventory")
	if saved is Array:
		load_snapshot(saved)


## Adds `amount` of `item`. Returns how many did NOT fit (0 = all added).
func add(item: Item, amount: int = 1) -> int:
	if item.chase_item:
		item.mark_account()
	var left := amount
	if item.stackable:
		var i := items.find(item)
		if i != -1:
			var room := item.max_stack - counts[i]
			var put := mini(left, room)
			counts[i] += put
			left -= put
		while left > 0:
			var free := _first_free()
			if free == -1:
				break
			var put := mini(left, item.max_stack)
			items[free] = item
			counts[free] = put
			left -= put
	else:
		while left > 0:
			var free := _first_free()
			if free == -1:
				break
			items[free] = item
			counts[free] = 1
			left -= 1
	if left != amount:
		changed.emit()
	return left


## Removes up to `amount`, from the last matching slots first. Returns true
## only if the full amount was available (and removed).
func remove(item: Item, amount: int = 1) -> bool:
	if count_of(item) < amount:
		return false
	var left := amount
	for i in range(SLOT_COUNT - 1, -1, -1):
		if left == 0:
			break
		if items[i] == item:
			var take := mini(left, counts[i])
			counts[i] -= take
			left -= take
			if counts[i] == 0:
				items[i] = null
	changed.emit()
	return true


func count_of(item: Item) -> int:
	var total := 0
	for i in SLOT_COUNT:
		if items[i] == item:
			total += counts[i]
	return total


func swap(a: int, b: int) -> void:
	if a == b:
		return
	var ti := items[a]
	var tc := counts[a]
	items[a] = items[b]
	counts[a] = counts[b]
	items[b] = ti
	counts[b] = tc
	changed.emit()


func has_room_for(item: Item) -> bool:
	return _first_free() != -1 or (item.stackable and items.has(item))


## All-or-nothing: runs `changes` (a Callable that edits the bag and returns true to keep
## the result). If it returns false the bag goes back exactly as it was.
func transact(changes: Callable) -> bool:
	var before := snapshot()
	var cd := item_cd.duplicate()
	if changes.call():
		return true
	load_snapshot(before)
	item_cd = cd
	return false


## How many of `amount` would fit right now (nothing is changed).
func room_for(item: Item, amount: int = 1) -> int:
	var room := 0
	if item.stackable:
		var i := items.find(item)
		if i != -1:
			room += item.max_stack - counts[i]
	for slot in items:
		if slot == null:
			room += item.max_stack if item.stackable else 1
	return mini(room, amount)


## Puts `item` straight into slot `i` (used by Equipment when swapping gear).
func replace_slot(i: int, item: Item, count: int = 1) -> void:
	items[i] = item
	counts[i] = count if item != null else 0
	changed.emit()


## Removes and returns everything that isn't soulbound: [{item, count}] (for a gravestone).
func take_unbound() -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		if items[i] != null and not items[i].soulbound:
			out.append({"item": items[i], "count": counts[i]})
			items[i] = null
			counts[i] = 0
	changed.emit()
	return out


func _first_free() -> int:
	return items.find(null)


## Empties one slot without dropping anything.
func clear_slot(i: int) -> void:
	items[i] = null
	counts[i] = 0
	changed.emit()


## What "Drop" would do with slot `i`: "none", "bound" (soulbound, can't be dropped),
## "pet" (set loose to follow you) or "item" (lands on the ground). Changes nothing.
func prepare_drop(i: int) -> String:
	var item := items[i]
	if item == null:
		return "none"
	if item.soulbound and not item.pet_scene:
		return "bound"
	return "pet" if item.pet_scene else "item"


## Drops a slot's contents next to the player. Pets are set loose to follow you;
## everything else lands on the ground as a pickup. (This wrapper does the visible part.)
func drop_slot(i: int) -> void:
	var kind := prepare_drop(i)
	var item := items[i]
	var count := counts[i]
	var player: Node2D = get_parent()
	var world: Node = player.get_parent()
	match kind:
		"bound":
			FloatingText.spawn(world, player.position + Vector2(0, -26), "ACCOUNT BOUND", Color("e03c3c"))
		"pet":
			# Pets are precious: bring the pet out and write it to the save FIRST, and only
			# then take it out of the bag. If anything fails, the pet stays in the bag.
			var pet: Node2D = item.pet_scene.instantiate()
			if pet == null:
				return
			pet.item = item
			pet.position = player.position + Vector2(10, 2)
			world.add_child(pet)
			Pet._save_all(get_tree())
			clear_slot(i)
		"item":
			clear_slot(i)
			var pickup: Node2D = load("res://scenes/pickup.tscn").instantiate()
			pickup.item = item
			pickup.count = count
			pickup.position = player.position + Vector2(0, 4)
			pickup.set("_check", 2.0)   # don't instantly re-collect it
			world.add_child(pickup)


## Uses one item from a slot: food heals, potions restore health or mana. Nothing is
## wasted at full health / mana. Returns true if it was used up. (Shows the floating text.)
func use_slot(i: int) -> bool:
	var r := try_use(i)
	var player: Node2D = get_parent()
	for m: Dictionary in r["messages"]:
		FloatingText.spawn(player.get_parent(), player.position + Vector2(0, -26), m["text"], m["color"])
	return r["ok"]


## The rules of using slot `i`, with no visuals: {"ok": bool, "messages": [{text, color}]}.
func try_use(i: int) -> Dictionary:
	var msgs: Array = []
	var item := items[i]
	if item == null or not item.is_consumable():
		return {"ok": false, "messages": msgs}
	var stats := get_parent().get_node_or_null("Stats") as Stats
	if stats == null or stats.health <= 0.0:
		return {"ok": false, "messages": msgs}
	if cooldown_of(item) > 0.0:
		msgs.append({"text": "NOT READY", "color": Color("e0e0e0")})
		return {"ok": false, "messages": msgs}
	var used := false
	if item.heal_amount > 0.0:
		if stats.health >= stats.max_health:
			msgs.append({"text": "HEALTH FULL", "color": Color("e0e0e0")})
		else:
			var before := stats.health
			stats.heal(item.heal_amount)
			msgs.append({"text": "+%d HP" % int(round(stats.health - before)), "color": Color("5fe05f")})
			used = true
	if item.mana_amount > 0.0:
		if stats.mana >= stats.max_mana:
			msgs.append({"text": "MANA FULL", "color": Color("e0e0e0")})
		else:
			var before_m := stats.mana
			stats.mana = minf(stats.mana + item.mana_amount, stats.max_mana)
			msgs.append({"text": "+%d MP" % int(round(stats.mana - before_m)), "color": Color("5fa8ff")})
			used = true
	if used:
		if item.use_cooldown > 0.0:
			item_cd[item] = item.use_cooldown
		remove(item, 1)
	return {"ok": used, "messages": msgs}


## Uses one of `item` from wherever it is in the bag (for the hotbar).
func use_item(item: Item) -> bool:
	var i := items.find(item)
	if i == -1:
		return false
	return use_slot(i)


## Removes `amount` from one specific slot (no drop).
func remove_at(i: int, amount: int = 1) -> void:
	counts[i] -= amount
	if counts[i] <= 0:
		items[i] = null
		counts[i] = 0
	changed.emit()
