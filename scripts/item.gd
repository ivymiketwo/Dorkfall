class_name Item
extends Resource
## Definition of one kind of item (coins, a sword, a potion...). Create new
## ones as .tres files in the items/ folder. Icons come from art/items.png,
## 16x16 per frame.

@export var id: StringName = &""
@export var display_name := "Item"
@export_multiline var description := ""
## Stackable items share one slot (coins). Others take a slot each.
@export var stackable := false
@export var max_stack := 2147483647
## Frame in art/items.png used for the icon.
@export var icon_frame := 0
## Optional 48x48 front-facing picture of this item worn, shown on the paperdoll (replaces the body).
@export var paperdoll_texture: Texture2D
## Shop price in coins.
@export var value := 1
## What a vendor pays you for one, in coins. 0 = a quarter of the shop price (min 1). Coins and account-bound items can never be sold.
@export var sell_price := 0
## If set, "Drop" puts this scene in the world (a follower pet) instead of an item on the ground.
@export var pet_scene: PackedScene
## Food / consumables: eating one restores this much health. This is the
## template for all food: make a new .tres, set heal_amount and an icon.
@export var heal_amount := 0.0
## Potions: drinking one restores this much mana.
@export var mana_amount := 0.0
## Seconds before this same item can be eaten / drunk again.
@export var use_cooldown := 0.0
## Where this goes on the paperdoll (right-click > EQUIP in the inventory).
@export_enum("none", "weapon", "helmet", "chest", "legs", "shield") var equip_slot := "none"
## Two-handed weapons block the shield slot.
@export var two_handed := false
## Sprite sheet drawn over the character while worn (same layout as art/player.png).
@export var worn_texture: Texture2D
## Chest gear: the whole player sheet with this worn (made with tools/gen_body_sheet.py, or drawn
## by hand like the robe). Replaces the body texture while equipped, same layout as player_new.png.
@export var body_sheet: Texture2D
## Jump frames per facing (down, up, left, right) in body_sheet, if it differs from the usual 9.
@export var body_jump_frames := PackedInt32Array()
## Held weapons: how it sits in the hand (angle, size, grip, jump poses...). Empty = the standard style for its weapon type (res://hold_styles/<type>.tres).
@export var hold_style: HoldStyle
## One-handed weapons already get this automatically. Tick it to force it on a two-handed item gripped at the bottom of its picture (a spear, say): it is then held with
## the shared melee (1-hand) hand placement (res://hold_styles/melee_hand.tres) in every direction, with no per-item tuning.
## An item's own Hold Style, if set, still wins.
@export var handle_at_bottom := false
## Scales this item's held picture on top of its style (1 = the style's own size).
@export var hold_scale := 1.0
## Melee (1hand) module: art pixels of the item left showing below the hand (+3 / +4 = a bit more handle past the hand,
## negative = hand nearer the very bottom). 0 = the module's automatic grip.
@export var hold_grip_offset := 0.0
## Weapons: decides the left-click melee animation.
@export_enum("none", "fist", "staff", "sword") var weapon_kind := "none"
## Locked to the account: it stays with you when you die (never left on a gravestone),
## can't be sold, and can't be traded.
@export var soulbound := false
## A "chase" item (like a pet): each account can only ever get one. Once it has come
## into your bag the account is flagged, and later drops / purchases are refused.
@export var chase_item := false
@export_group("Gear stats")
## Percent of incoming damage this piece blocks (2 = 2%).
@export var defense := 0.0
## Extra mana regenerated per second while worn.
@export var mana_regen_bonus := 0.0
## Percent bonus to spell / staff-beam damage while worn (3 = +3%).
@export var magic_damage_bonus := 0.0
## Extra Intelligence / Strength / Dexterity points while worn.
@export var int_bonus := 0
## Shields: percent of a blocked hit that is absorbed (70 = 70%).
@export var block_percent := 0.0
@export var str_bonus := 0
@export var dex_bonus := 0
@export_group("Fishing")
## Fishing rods are equipped in the weapon slot. Left-click casts (see fishing.gd).
@export var fishing_rod := false
## 1-3: bigger = a wider catch zone, a calmer fish and better fish.
@export_range(1, 3) var fishing_power := 1
@export_group("Melee")
@export var melee_damage := 15.0
## How far the swing reaches (pixels) and how wide it is (degrees).
@export var melee_range := 24.0
@export var melee_arc := 90.0
@export var melee_cooldown := 0.6
@export var melee_stamina := 4.0
## Optional: a ranged basic attack (an Ability, e.g. a beam) used for left-click
## instead of the melee swing. Falls back to the swing when out of mana.
@export var basic_attack: Ability
@export_group("")
## Optional: icon changes as the stack grows (RuneScape coins). Each threshold
## that the count reaches moves the icon one frame further along.
@export var stack_thresholds := PackedInt32Array()


func frame_for(count: int) -> int:
	var f := icon_frame
	for i in stack_thresholds.size():
		if count >= stack_thresholds[i]:
			f = icon_frame + i
	return f


## Lines describing this item's gear stats (empty if it has none).
func stat_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if defense != 0.0:
		out.append("DEFENSE +%s%%" % _num(defense))
	if mana_regen_bonus != 0.0:
		out.append("MANA REGEN +%s/S" % _num(mana_regen_bonus))
	if magic_damage_bonus != 0.0:
		out.append("MAGIC DAMAGE +%s%%" % _num(magic_damage_bonus))
	if block_percent != 0.0:
		out.append("BLOCK %s%%" % _num(block_percent))
	if int_bonus != 0:
		out.append("INTELLIGENCE +%d" % int_bonus)
	if str_bonus != 0:
		out.append("STRENGTH +%d" % str_bonus)
	if dex_bonus != 0:
		out.append("DEXTERITY +%d" % dex_bonus)
	if fishing_rod:
		out.append("FISHING POWER %d" % fishing_power)
	if soulbound:
		out.append("ACCOUNT BOUND")
	return out


func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


func is_tradable() -> bool:
	return not soulbound


func can_sell() -> bool:
	return not soulbound


## Has this account ever received this chase item?
func account_has() -> bool:
	var owned = SaveGame.get_value("chase_owned", {})
	return owned is Dictionary and owned.has(str(id))


func mark_account() -> void:
	var owned = SaveGame.get_value("chase_owned", {})
	if not (owned is Dictionary):
		owned = {}
	owned[str(id)] = true
	SaveGame.put("chase_owned", owned)


func is_food() -> bool:
	return heal_amount > 0.0


## Anything that can be eaten / drunk (food and potions).
func is_consumable() -> bool:
	return heal_amount > 0.0 or mana_amount > 0.0


func is_equippable() -> bool:
	return equip_slot != "none"


func is_weapon() -> bool:
	return weapon_kind != "none"
