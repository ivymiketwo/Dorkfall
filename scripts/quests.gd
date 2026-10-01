class_name Quests
extends RefCounted
## Kill quests from the notice board. Rules and saved progress only, no visuals,
## so a server can own this later. Quests can be taken again after you hand one in.
## State per quest: 0 = available, 1 = active, 2 = done (ready to hand in), 3 = handed in for good.

const COINS := preload("res://items/coins.tres")

## Reward = kills x rate: 10 coins and 10 XP per Mangyang, 12 of each per Skeleton.
const RATES := {"mangyang": 10, "skeleton": 12}

const LIST := [
	{"id": "mang10", "title": "Pest Control", "kind": "mangyang", "name": "Mangyangs", "count": 10},
	{"id": "skel12", "title": "Bone Collector", "kind": "skeleton", "name": "Skeletons", "count": 12},
	{"id": "mang15", "title": "Mangyang Menace", "kind": "mangyang", "name": "Mangyangs", "count": 15},
	{"id": "skel20", "title": "The Restless Dead", "kind": "skeleton", "name": "Skeletons", "count": 20},
	# Luck's quest (not on the notice board): one dragon, one time, a handsome reward
	{"id": "vorly", "title": "Slay Vorly", "kind": "vordy", "name": "Vorly", "count": 1, "npc": true, "once": true, "reward": 1000},
]


## The quests that hang on the notice board.
static func board_list() -> Array:
	return LIST.filter(func(q): return not q.get("npc", false))


## Coins and XP (the same amount) for finishing a quest.
static func reward_of(q: Dictionary) -> int:
	if q.has("reward"):
		return int(q["reward"])
	return int(q["count"]) * int(RATES[q["kind"]])

static var _state := {}
static var _loaded := false
static var _tracked := ""


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var saved = SaveGame.get_value("quests", {})
	if saved is Dictionary:
		_state = saved
	_tracked = str(SaveGame.get_value("quest_tracked", ""))


static func _save() -> void:
	SaveGame.put("quests", _state)


static func state_of(id: String) -> int:
	_load()
	return int((_state.get(id, {}) as Dictionary).get("s", 0))


static func progress_of(id: String) -> int:
	_load()
	return int((_state.get(id, {}) as Dictionary).get("n", 0))


static func reset_all() -> void:
	_load()
	_state = {}
	_tracked = ""
	SaveGame.put("quest_tracked", "")
	_save()


static func accept(id: String) -> void:
	_load()
	if state_of(id) == 0:
		_state[id] = {"s": 1, "n": 0}
		_save()
		set_tracked(id)      # the quest you just took is the one the map leads you to


static func abandon(id: String) -> void:
	_load()
	if state_of(id) == 1:
		_state.erase(id)
		_save()


## The quest the map markers lead you to ("" if none).
static func tracked_id() -> String:
	_load()
	var st := state_of(_tracked)
	if _tracked != "" and (st == 1 or st == 2):
		return _tracked
	for q in LIST:
		var s2 := state_of(q["id"])
		if s2 == 1 or s2 == 2:
			return q["id"]
	return ""


static func set_tracked(id: String) -> void:
	_load()
	_tracked = id
	SaveGame.put("quest_tracked", id)


static func find(id: String) -> Dictionary:
	for q in LIST:
		if q["id"] == id:
			return q
	return {}


static func kind_of(mob: Node) -> String:
	var path: String = mob.get_script().resource_path if mob.get_script() else ""
	if path.ends_with("mangyang.gd"):
		return "mangyang"
	if path.ends_with("skeleton.gd"):
		return "skeleton"
	if path.ends_with("vordy.gd"):
		return "vordy"
	return ""


## World positions the tracked quest points to: the quest giver once it is done, otherwise
## the nearest living monsters of its kind (up to 3; Vorly is one dragon).
static func targets(tree: SceneTree, player: Node2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var q := find(tracked_id())
	if q.is_empty() or player == null:
		return out
	if state_of(q["id"]) == 2:
		var grp := "quest_giver_npc" if q.get("npc", false) else "quest_giver_board"
		for n in tree.get_nodes_in_group(grp):
			out.append((n as Node2D).global_position)
		return out
	var rows: Array = []
	for n in tree.get_nodes_in_group("monsters"):
		if kind_of(n) != q["kind"]:
			continue
		var st = n.get("stats")
		if st != null and st.health <= 0.0:
			continue
		rows.append([(n as Node2D).global_position.distance_to(player.global_position), (n as Node2D).global_position])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(rows.size(), 3):
		out.append(rows[i][1])
	return out


static func active() -> Array:
	var out: Array = []
	for q in LIST:
		var st := state_of(q["id"])
		if st == 1 or st == 2:
			out.append(q)
	return out


## Called when a monster dies, with the players who earned the credit.
static func on_kill(who: Array, mob: Node) -> void:
	_load()
	var kind := kind_of(mob)
	if kind == "":
		return
	var local := Players.local(mob.get_tree())
	if local == null or not who.has(local):
		return
	for q in LIST:
		if q["kind"] != kind or state_of(q["id"]) != 1:
			continue
		var n := progress_of(q["id"]) + 1
		var done: bool = n >= int(q["count"])
		_state[q["id"]] = {"s": 2 if done else 1, "n": mini(n, int(q["count"]))}
		_save()
		if mob.get_parent():
			FloatingText.spawn(mob.get_parent(), mob.position + Vector2(0, -44),
					"QUEST COMPLETE!" if done else "%s  %d/%d" % [q["name"], n, q["count"]],
					Color("ffe066") if done else Color("9ad0ff"))


## Hands in a finished quest: coins and XP. Returns {"ok", "message"}.
static func turn_in(id: String, player: Node2D) -> Dictionary:
	_load()
	var q := {}
	for e in LIST:
		if e["id"] == id:
			q = e
	if q.is_empty() or state_of(id) != 2:
		return {"ok": false, "message": "Not finished yet"}
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null or inv.room_for(COINS, reward_of(q)) < reward_of(q):
		return {"ok": false, "message": "INVENTORY FULL"}
	inv.add(COINS, reward_of(q))
	var e := player.get_node_or_null("Experience") as Experience
	if e:
		e.add_xp(reward_of(q))
	if q.get("once", false):
		_state[id] = {"s": 3, "n": int(q["count"])}
	else:
		_state.erase(id)
	_save()
	return {"ok": true, "message": "Reward: %d coins and %d XP" % [reward_of(q), reward_of(q)]}
