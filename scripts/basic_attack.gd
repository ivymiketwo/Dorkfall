class_name BasicAttack
extends Node
## Left-click attack: fires the equipped staff's basic spell (its `basic_attack`): a beam, or a
## staff's own special attack (an ability of kind SPELL, e.g. the Sun Staff's halo beam).
## Does nothing without a staff, and only warns when out of mana. Lives as a child of the player.

## GameClock time the next attack is allowed (see game_clock.gd).
var _ready_at := 0.0

@onready var caster: Node2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")
@onready var equipment: Equipment = get_parent().get_node("Equipment")


var weapon: Item:
	get:
		return equipment.get_item("weapon")


func _process(_delta: float) -> void:
	# Holding left click keeps firing a staff's beam.
	if GameClock.passed(_ready_at) and caster.get("input_fire_held"):
		var w := weapon
		if w != null and not w.fishing_rod and w.basic_attack != null and _usable(w.basic_attack) and not _ui_blocking():
			attack()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _ui_blocking():
			return
		if weapon != null and weapon.fishing_rod:   # a fishing rod: left-click casts (fishing.gd)
			return
		attack()
		get_viewport().set_input_as_handled()


func _ui_blocking() -> bool:
	var menu := get_tree().get_first_node_in_group("context_menu") as ContextMenu
	if menu and menu.is_open():
		return true
	var shop := get_tree().get_first_node_in_group("shop_ui") as Control
	var quest := get_tree().get_first_node_in_group("quest_ui") as Control
	var talk := get_tree().get_first_node_in_group("dialogue_ui") as Control
	return (shop != null and shop.visible) or (quest != null and quest.visible) or (talk != null and talk.visible) or _quest_menu_open()


func attack() -> void:
	var w := weapon
	if w == null or not w.is_weapon() or not GameClock.passed(_ready_at) or stats.health <= 0.0:
		return
	if caster.has_method("is_warding") and caster.is_warding():   # no attacking behind the Ward
		return
	var ab := w.basic_attack
	if not _usable(ab):
		return
	if stats.mana < ab.mana_cost:
		stats.warn_out_of_mana()
		return
	if ab.kind == Ability.Kind.SPELL:
		var hb := caster.get_node_or_null("Hotbar") as Hotbar
		if hb != null and hb.is_busy():      # one cast at a time
			return
		_cast_spell(ab)
	else:
		_basic_beam(ab)


func _usable(ab: Ability) -> bool:
	return ab != null and (ab.kind == Ability.Kind.BEAM or (ab.kind == Ability.Kind.SPELL and ab.spell_scene != null))


## A staff's own special attack: the spell scene runs all of it (see e.g. sun_halo.gd).
func _cast_spell(ab: Ability) -> void:
	stats.spend_mana(ab.mana_cost)
	_ready_at = GameClock.now + ab.cooldown
	var s := ab.spell_scene.instantiate()
	s.caster = caster
	s.damage = ab.damage
	caster.get_parent().add_child(s)


## Left-click ranged attack: same beam as the ability, fired from the weapon.
func _basic_beam(ab: Ability) -> void:
	stats.spend_mana(ab.mana_cost)
	_ready_at = GameClock.now + ab.cooldown
	var start := caster.global_position + Vector2(0, -10)
	var aim: Vector2 = caster.aim_world - start
	var dir := aim.normalized() if aim.length() > 1.0 else Vector2.DOWN
	if "facing" in caster:
		caster.facing = (3 if dir.x > 0 else 2) if absf(dir.x) > absf(dir.y) else (0 if dir.y > 0 else 1)
	start = HeldWeapon.beam_origin(caster)               # the beam leaves from the staff's orb
	aim = caster.aim_world - start
	dir = aim.normalized() if aim.length() > 1.0 else dir
	# Hitbox: an inverted cone from the head, independent of the animation and of where the beam is drawn.
	var cone_dir := BeamCone.direction(caster, dir)
	for body in BeamCone.bodies(caster, cone_dir, ab.beam_length):
		var t := body.get_node_or_null("Stats") as Stats
		if t:
			t.take_damage(ab.damage * stats.magic_mult(), caster)
			if ab.poison_dps > 0.0:
				t.apply_poison(ab.poison_dps, ab.poison_time, caster)
	var fx := BeamFx.new()
	fx.global_position = start
	fx.direction = dir
	fx.length = ab.beam_length
	fx.tint = ab.beam_color
	fx.lightning = ab.beam_lightning
	fx.z_index = 4
	caster.get_parent().add_child(fx)


func _quest_menu_open() -> bool:
	var m := get_tree().get_first_node_in_group("quest_menu") as Control
	return m != null and m.visible
