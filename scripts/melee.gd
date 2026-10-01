class_name Melee
extends Node
## Universal left-click melee attack. What it looks like and how hard it hits
## depends on the equipped weapon (an Item with weapon_kind set): a staff bashes,
## a sword sweeps. Lives as a child of the player.

## Used when nothing is equipped in the weapon slot.
@export var unarmed: Item

var _cooldown := 0.0

@onready var caster: Node2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")
@onready var equipment: Equipment = get_parent().get_node("Equipment")


var weapon: Item:
	get:
		var w := equipment.get_item("weapon")
		return w if w else unarmed


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _ui_blocking():
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
	var guard := caster.get_node_or_null("Guard") as Guard
	if guard != null and guard.guarding:
		return
	if weapon == null or not weapon.is_weapon() or _cooldown > 0.0 or stats.health <= 0.0:
		return
	var ab := weapon.basic_attack
	if ab != null and ab.kind == Ability.Kind.BEAM and stats.mana >= ab.mana_cost:
		_basic_beam(ab)
		return
	if ab != null and ab.kind == Ability.Kind.BEAM:
		stats.warn_out_of_mana()   # the swing below still happens
	if stats.stamina < weapon.melee_stamina:
		return
	stats.spend_stamina(weapon.melee_stamina)
	_cooldown = weapon.melee_cooldown

	var origin := caster.global_position + Vector2(0, -8)
	var aim: Vector2 = caster.aim_world - origin
	var dir := aim.normalized() if aim.length() > 1.0 else Vector2.DOWN
	if "facing" in caster:   # turn to face the swing (0 down, 1 up, 2 left, 3 right)
		caster.facing = (3 if dir.x > 0 else 2) if absf(dir.x) > absf(dir.y) else (0 if dir.y > 0 else 1)

	# Hit test: a wedge in front of the player, tested against real collision shapes.
	var half := deg_to_rad(weapon.melee_arc) * 0.5
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 7:
		pts.append(Vector2.from_angle(lerpf(-half, half, i / 6.0)) * weapon.melee_range)
	var wedge := ConvexPolygonShape2D.new()
	wedge.points = pts
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = wedge
	q.transform = Transform2D(dir.angle(), origin)
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var seen := {}
	for hit in caster.get_world_2d().direct_space_state.intersect_shape(q, 32):
		var body := hit["collider"] as Node
		if body == null or seen.has(body) or body.is_in_group("player"):
			continue
		seen[body] = true
		var s := body.get_node_or_null("Stats") as Stats
		if s:
			s.take_damage(weapon.melee_damage * stats.melee_mult(), caster)

	var fx := MeleeFx.new()
	fx.kind = weapon.weapon_kind
	fx.direction = dir
	fx.reach = weapon.melee_range
	fx.arc = weapon.melee_arc
	fx.global_position = origin
	fx.z_index = 4
	caster.get_parent().add_child(fx)


## Left-click ranged attack: same beam as the ability, fired from the weapon.
func _basic_beam(ab: Ability) -> void:
	stats.spend_mana(ab.mana_cost)
	_cooldown = ab.cooldown
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
