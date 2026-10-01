class_name Equipment
extends Node
## What the player is wearing: weapon, helmet, chest, shield. Draws the worn
## gear as sprite layers over the player. Two-handed weapons block the shield slot.

signal changed

const SLOTS := ["helmet", "weapon", "chest", "shield"]
const SLOT_NAMES := {"helmet": "Helmet", "weapon": "Weapon", "chest": "Chest", "shield": "Shield"}
## Draw order (bottom to top).
const LAYER_ORDER := ["chest", "helmet", "shield", "weapon"]

@export var starting: Array[Item] = []

var items := {}          # slot name -> Item
var _layers := {}        # slot name -> Sprite2D

@onready var player: Node2D = get_parent()
@onready var base: Sprite2D = get_parent().get_node("Sprite2D")


func _ready() -> void:
	for slot in LAYER_ORDER:
		var s: Sprite2D = HeldWeapon.new() if slot == "weapon" else Sprite2D.new()
		if slot == "weapon":
			s.body = base
			s.player = player
		s.name = slot.capitalize() + "Layer"
		s.offset = base.offset
		s.scale = base.scale
		s.hframes = base.hframes
		s.vframes = base.vframes
		s.visible = false
		player.add_child.call_deferred(s)
		_layers[slot] = s
	var saved = SaveGame.get_value("equipment")
	if saved is Dictionary:
		for slot in saved:
			var it := SaveGame.item_from_path(str(saved[slot]))
			if it and it.is_equippable() and it.equip_slot == slot:
				items[slot] = it
	else:
		for it in starting:
			if it and it.is_equippable() and not items.has(it.equip_slot):
				items[it.equip_slot] = it
	_refresh()
	changed.connect(_save)
	_save()


func _save() -> void:
	var out := {}
	for slot in items:
		if items[slot] != null and SaveGame.item_to_path(items[slot]) != "":
			out[slot] = SaveGame.item_to_path(items[slot])
	SaveGame.put("equipment", out)


func _process(_delta: float) -> void:
	for slot in _layers:
		var s: Sprite2D = _layers[slot]
		if slot == "weapon":
			continue                      # HeldWeapon places itself at the hand
		if s.visible:
			s.frame = base.frame
		if s.material != base.material:
			s.material = base.material      # shares the idle-bob shader
		s.position = base.position


func get_item(slot: String) -> Item:
	return items.get(slot)


## Shield slot is unusable while a two-handed weapon is held.
func shield_blocked() -> bool:
	var w := get_item("weapon")
	return w != null and w.two_handed


func _refresh() -> void:
	for slot in _layers:
		var s: Sprite2D = _layers[slot]
		var it := get_item(slot)
		s.texture = it.worn_texture if it else null
		if slot == "weapon":
			s.style = (it.hold_style if it.hold_style != null else HoldStyle.for_kind(it.weapon_kind)) if it != null else HoldStyle.new()
			s._crop = null                # re-crop with this style's grip
		s.visible = slot == "weapon" and it != null and it.worn_texture != null   # only held weapons for now; armour needs 48x48 art
	_apply_stats()
	changed.emit()


func total(stat: String) -> float:
	var sum := 0.0
	for slot in items:
		var it: Item = items[slot]
		if it != null:
			sum += float(it.get(stat))
	return sum


func _apply_stats() -> void:
	var st := player.get_node_or_null("Stats") as Stats
	if st == null:
		return
	st.defense_percent = total("defense")
	st.mana_regen_bonus = total("mana_regen_bonus")
	st.magic_damage_percent = total("magic_damage_bonus")


func _say(msg: String, col := Color("f0d040")) -> void:
	FloatingText.spawn(player.get_parent(), player.position + Vector2(0, -26), msg, col)


## Wears the item in inventory slot `i`; whatever was in that equipment slot goes back to the inventory.
func equip_from(inv: Inventory, i: int) -> void:
	var item := inv.items[i]
	if item == null or not item.is_equippable():
		return
	var slot := item.equip_slot
	if slot == "shield" and shield_blocked():
		_say("TWO-HANDED WEAPON", Color("e03c3c"))
		return
	var old := get_item(slot)
	var kick_shield := slot == "weapon" and item.two_handed and get_item("shield") != null
	# need one free slot for the shield if the old weapon is also taking our slot
	if kick_shield and old != null and inv._first_free() == -1:
		_say("INVENTORY FULL", Color("e03c3c"))
		return
	inv.remove_at(i, 1)
	if old:
		inv.replace_slot(i, old)
	items[slot] = item
	if kick_shield:
		inv.add(get_item("shield"), 1)
		items.erase("shield")
	_refresh()
	_say("EQUIPPED " + item.display_name.to_upper())


func unequip(slot: String) -> void:
	var it := get_item(slot)
	if it == null:
		return
	var inv := player.get_node("Inventory") as Inventory
	if not inv.has_room_for(it):
		_say("INVENTORY FULL", Color("e03c3c"))
		return
	inv.add(it, 1)
	items.erase(slot)
	_refresh()
