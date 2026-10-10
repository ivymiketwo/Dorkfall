class_name Equipment
extends Node
## What the player is wearing: weapon, helmet, chest, legs. Draws the worn
## gear as sprite layers over the player.

signal changed

const SLOTS := ["helmet", "weapon", "chest", "legs"]
const SLOT_NAMES := {"helmet": "Helmet", "weapon": "Weapon", "chest": "Chest", "legs": "Legs"}
## Draw order (bottom to top).
const LAYER_ORDER := ["legs", "chest", "helmet", "weapon"]
## Worn layers are made for this body; a hand-drawn body sheet (the robe) has its own poses.
const NAKED := preload("res://art/player_new.png")

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
		if slot != "weapon":
			s.visible = _shows_layer(get_item(slot))
		if s.visible:
			s.frame = base.frame
		if s.material != base.material:
			s.material = base.material      # shares the idle-bob shader
		s.position = base.position


## Gear drawn as a layer over the body: its worn art is a full player-layout sheet (made with
## tools/new_gear.py) and the body is the normal one (not a hand-drawn sheet like the robe).
func _shows_layer(it: Item) -> bool:
	return it != null and it.body_sheet == null and it.worn_texture != null \
			and it.worn_texture.get_size() == NAKED.get_size() and base.texture == NAKED


func get_item(slot: String) -> Item:
	return items.get(slot)


func _refresh() -> void:
	for slot in _layers:
		var s: Sprite2D = _layers[slot]
		var it := get_item(slot)
		s.texture = it.worn_texture if it else null
		if slot == "weapon":
			s.style = HoldStyle.for_item(it)
			s.item_scale = it.hold_scale if it != null else 1.0
			s.grip_extra = it.hold_grip_offset if it != null else 0.0
			s._crop = null                # re-crop with this style's grip
		if slot == "weapon":
			s.visible = it != null and it.worn_texture != null
		else:
			# worn gear shows when its art is a full frame-by-frame sheet laid out like the
			# player's (made with tools/gen_worn_layer.py); older single pictures stay hidden
			s.visible = _shows_layer(it)
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
	var old := get_item(slot)
	inv.remove_at(i, 1)
	if old:
		inv.replace_slot(i, old)
	items[slot] = item
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
