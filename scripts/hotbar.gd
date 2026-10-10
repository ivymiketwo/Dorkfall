class_name Hotbar
extends Node
## Hotbar: pressing 1-6 casts that slot immediately (aimed at the mouse).
## Lives as a child of the player, next to its Stats node.

signal changed

## Four bars of seven slots. Slot indexes are global: bar * PER_BAR + slot.
const PER_BAR := 7
const BARS := 4
const SLOT_COUNT := PER_BAR * BARS

@export var slots: Array[Ability] = []

## Parallel to `slots`: a slot holds either an ability or a consumable item.
var item_slots: Array[Item] = []
## Every ability the player has learned (shown in the spellbook).
@export var known: Array[Ability] = []

var selected := 0
var active_bar := 0
var casting_slot := -1
var cast_elapsed := 0.0
## Per slot: GameClock time the slot can be cast again (see cooldown_left).
var ready_at: Array[float] = []
var fail_flash: Array[float] = []

@onready var caster: Node2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")
@onready var inventory: Inventory = get_parent().get_node_or_null("Inventory")
var _cast_snd: AudioStreamPlayer2D
@onready var cast_orb: Sprite2D = get_parent().get_node_or_null("CastOrb")


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	item_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		ready_at.append(0.0)
		fail_flash.append(0.0)
	for ab in slots:
		if ab != null and not known.has(ab):
			known.append(ab)
	var home := load("res://abilities/home_teleport.tres") as Ability
	if not known.has(home):
		known.append(home)
	_load_layout()
	active_bar = clampi(int(SaveGame.get_value("hotbar_bar", 0)), 0, BARS - 1)
	if inventory:
		inventory.changed.connect(func(): changed.emit())


## --- assigning things to slots (drag and drop) ---
func assign_ability(i: int, ab: Ability) -> void:
	_cancel_cast()
	slots[i] = ab
	item_slots[i] = null
	ready_at[i] = 0.0
	_layout_changed()


func assign_item(i: int, item: Item) -> void:
	_cancel_cast()
	slots[i] = null
	item_slots[i] = item
	ready_at[i] = 0.0
	_layout_changed()


func clear_slot(i: int) -> void:
	_cancel_cast()
	slots[i] = null
	item_slots[i] = null
	ready_at[i] = 0.0
	_layout_changed()


func swap_slots(a: int, b: int) -> void:
	if a == b:
		return
	_cancel_cast()
	var t_ab := slots[a]; slots[a] = slots[b]; slots[b] = t_ab
	var t_it := item_slots[a]; item_slots[a] = item_slots[b]; item_slots[b] = t_it
	var t_cd := ready_at[a]; ready_at[a] = ready_at[b]; ready_at[b] = t_cd
	_layout_changed()


func has_content(i: int) -> bool:
	return slots[i] != null or item_slots[i] != null


func item_stock(i: int) -> int:
	if item_slots[i] == null or inventory == null:
		return 0
	return inventory.count_of(item_slots[i])


func _layout_changed() -> void:
	var out: Array = []
	for i in SLOT_COUNT:
		if slots[i] != null:
			out.append({"ability": slots[i].resource_path})
		elif item_slots[i] != null:
			out.append({"item": SaveGame.item_to_path(item_slots[i])})
		else:
			out.append({})
	SaveGame.put("hotbar", out)
	changed.emit()


func _load_layout() -> void:
	var saved = SaveGame.get_value("hotbar")
	# older saves only had one bar of 6 or 7 slots: they become bar 1
	if not (saved is Array) or saved.size() == 0 or saved.size() > SLOT_COUNT:
		return
	for i in SLOT_COUNT:
		slots[i] = null
		item_slots[i] = null
		var d = saved[i] if i < saved.size() else null
		if d is Dictionary:
			if d.has("ability") and ResourceLoader.exists(d["ability"]):
				slots[i] = load(d["ability"]) as Ability
			elif d.has("item"):
				item_slots[i] = SaveGame.item_from_path(d["item"])


func set_bar(b: int) -> void:
	b = posmod(b, BARS)
	if b == active_bar:
		return
	active_bar = b
	SaveGame.put("hotbar_bar", b)
	changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo or not event.pressed:
		return
	# Find every hotbar action this key press matches and take the most specific
	# one (so Shift+1 beats plain 1, while plain 1 still works when Shift is held for sprinting).
	var best := ""
	var best_mods := -1
	var names: Array[String] = ["bar_up", "bar_down"]
	for s in PER_BAR:
		names.append("hotbar_%d" % (s + 1))
	for b in BARS:
		for s in PER_BAR:
			names.append("bar%d_slot%d" % [b + 1, s + 1])
	for a in names:
		if not event.is_action_pressed(a):
			continue
		var spec := Keybinds.current(a)
		var mods := int(spec[1]) + int(spec[2]) + int(spec[3]) if not spec.is_empty() else 0
		if mods > best_mods:
			best = a
			best_mods = mods
	if best == "":
		return
	get_viewport().set_input_as_handled()
	if best == "bar_up":
		set_bar(active_bar - 1)
		return
	if best == "bar_down":
		set_bar(active_bar + 1)
		return
	var target: int
	if best.begins_with("hotbar_"):
		target = active_bar * PER_BAR + int(best.substr(7)) - 1   # number keys fire the visible bar
	else:   # "bar2_slot5"
		var parts := best.substr(3).split("_slot")
		target = (int(parts[0]) - 1) * PER_BAR + int(parts[1]) - 1
	if casting_slot != -1:
		return   # busy casting something else
	selected = target   # highlights the last slot used
	changed.emit()
	try_cast(target)


func select(i: int) -> void:
	if i == selected:
		return
	selected = i
	_cancel_cast()
	changed.emit()


func try_cast(i: int) -> void:
	if item_slots[i] != null:
		_use_item_slot(i)
		return
	var ab := slots[i]
	if ab == null or casting_slot != -1:
		return
	if caster.has_method("is_warding") and caster.is_warding():   # no casting behind the Ward
		_fail(i)
		return
	if cooldown_left(i) > 0.0 or not _can_afford(ab):
		if cooldown_left(i) <= 0.0 and stats.mana < ab.mana_cost:
			stats.warn_out_of_mana()
		_fail(i)
		return
	if ab.cast_time > 0.0:
		casting_slot = i
		cast_elapsed = 0.0
		_start_cast_sound(ab)
		changed.emit()
	else:
		_finish(i)


func _use_item_slot(i: int) -> void:
	if casting_slot != -1:
		return
	if inventory == null or inventory.cooldown_of(item_slots[i]) > 0.0 or not inventory.use_item(item_slots[i]):
		_fail(i)
		return
	changed.emit()


func cast_progress() -> float:
	if casting_slot == -1:
		return 0.0
	return clampf(cast_elapsed / slots[casting_slot].cast_time, 0.0, 1.0)


## Seconds until slot `i` can be cast again (0 = ready).
func cooldown_left(i: int) -> float:
	return GameClock.left(ready_at[i])


## The cast itself runs on the fixed game tick (a server would run the same).
func _physics_process(delta: float) -> void:
	if casting_slot != -1:
		cast_elapsed += delta
		if cast_elapsed >= slots[casting_slot].cast_time:
			var i := casting_slot
			casting_slot = -1
			_finish(i)


## Only visuals here: the cast orb, the red "can't" flash, and redrawing the bar.
func _process(delta: float) -> void:
	var dirty := casting_slot != -1
	if inventory and not inventory.item_cd.is_empty():
		dirty = true
	for i in SLOT_COUNT:
		if ready_at[i] > GameClock.now:
			dirty = true
		if fail_flash[i] > 0.0:
			fail_flash[i] = maxf(fail_flash[i] - delta, 0.0)
			dirty = true
	_update_cast_orb()
	if dirty:
		changed.emit()


func _start_cast_sound(ab: Ability) -> void:
	_stop_cast_sound()
	if ab.cast_start_sound == null:
		return
	_cast_snd = AudioStreamPlayer2D.new()
	_cast_snd.stream = ab.cast_start_sound
	_cast_snd.volume_db = -3.1     # 30% quieter
	_cast_snd.finished.connect(_cast_snd.queue_free)
	caster.get_parent().add_child(_cast_snd)
	_cast_snd.global_position = HeldWeapon.beam_origin(caster)
	_cast_snd.play()


func _stop_cast_sound() -> void:
	if _cast_snd != null and is_instance_valid(_cast_snd):
		_cast_snd.queue_free()
	_cast_snd = null


func _finish(i: int) -> void:
	var ab := slots[i]
	if not _can_afford(ab):
		_stop_cast_sound()
		if stats.mana < ab.mana_cost:
			stats.warn_out_of_mana()
		_fail(i)
		return
	match ab.kind:
		Ability.Kind.PROJECTILE:
			_spawn_projectile(ab)
		Ability.Kind.BEAM:
			_fire_beam(ab)
		Ability.Kind.HOME_TELEPORT:
			var ht := caster.get_node_or_null("HomeTeleport") as HomeTeleport
			if ht == null or ht.is_active():
				_fail(i)
				return
			ht.start()
		Ability.Kind.TRANSFER:
			if not stats.transfer(ab.transfer_from, ab.transfer_to, ab.transfer_amount):
				_fail(i)
				return
	if ab.mana_cost > 0.0:
		stats.spend_mana(ab.mana_cost)
	if ab.stamina_cost > 0.0:
		stats.spend_stamina(ab.stamina_cost)
	ready_at[i] = GameClock.now + ab.cooldown
	changed.emit()


func _spawn_projectile(ab: Ability) -> void:
	if ab.projectile_scene == null:
		return
	var p := ab.projectile_scene.instantiate()
	var start := HeldWeapon.beam_origin(caster)   # leaves from the staff tip, like the beams
	var aim: Vector2 = caster.aim_world - start
	p.global_position = start
	p.direction = aim.normalized() if aim.length() > 1.0 else Vector2.DOWN
	p.speed = ab.projectile_speed
	p.damage = ab.damage * stats.magic_mult()
	p.caster = caster
	if _cast_snd != null and is_instance_valid(_cast_snd) and "cast_player" in p:
		p.cast_player = _cast_snd      # the projectile carries the sound it was cast with
		_cast_snd = null
	caster.get_parent().add_child(p)


func _fire_beam(ab: Ability) -> void:
	var start := HeldWeapon.beam_origin(caster)          # the beam leaves from the staff's orb
	var aim: Vector2 = caster.aim_world - start
	var dir := aim.normalized() if aim.length() > 1.0 else Vector2.DOWN
	var length := ab.beam_length
	# Hitbox: an inverted cone from the head, independent of the animation and of where the beam is drawn.
	var cone_dir := BeamCone.direction(caster, dir)
	for body in BeamCone.bodies(caster, cone_dir, length):
		var target_stats := body.get_node_or_null("Stats") as Stats
		if target_stats:
			target_stats.take_damage(ab.damage * stats.magic_mult(), caster)
			if ab.poison_dps > 0.0:
				target_stats.apply_poison(ab.poison_dps, ab.poison_time, caster)
	var fx := BeamFx.new()
	fx.global_position = start
	fx.direction = dir
	fx.length = length
	fx.tint = ab.beam_color
	fx.lightning = ab.beam_lightning
	fx.z_index = 4
	caster.get_parent().add_child(fx)


func _can_afford(ab: Ability) -> bool:
	return stats.mana >= ab.mana_cost and stats.stamina >= ab.stamina_cost


func _fail(i: int) -> void:
	fail_flash[i] = 0.25
	changed.emit()


func _cancel_cast() -> void:
	casting_slot = -1
	_stop_cast_sound()
	_update_cast_orb()


func _update_cast_orb() -> void:
	if cast_orb == null:
		return
	var showing := casting_slot != -1 and slots[casting_slot].kind == Ability.Kind.PROJECTILE
	cast_orb.visible = showing
	if showing:
		# sit on the tip of the staff, which moves sides as the player turns
		cast_orb.global_position = HeldWeapon.beam_origin(caster)
		if _cast_snd != null and is_instance_valid(_cast_snd):
			_cast_snd.global_position = cast_orb.global_position
		HeldWeapon.layer_above_staff(caster, cast_orb)
		cast_orb.scale = Vector2.ONE * lerpf(0.15, 0.5, cast_progress())   # art is 2x, so 0.5 = full size
