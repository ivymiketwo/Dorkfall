class_name Guard
extends Node2D
## Blocking and parrying (hold right mouse button, or Q). Lives on the player.
##
## - Needs a shield (hold to block) or a sword (parry only).
## - Only attacks that come from where you're aiming are stopped (a 120 degree arc in
##   front of you). Ground effects (slam, blob, toxic clouds, boulders) can't be blocked.
## - Parry: a hit landing in the first PARRY_WINDOW seconds of a guard is almost fully
##   negated and half of it is thrown back at whoever attacked. Mashing doesn't work:
##   a new parry window only opens PARRY_LOCKOUT seconds after the last one started.
## - Block (shield only): mitigates the shield's block %, costs stamina per hit, and
##   holding costs stamina too. Run out and the guard breaks: full damage and a short stun.

const PARRY_WINDOW := 0.25
const PARRY_LOCKOUT := 0.8
const HALF_ARC := deg_to_rad(60.0)
const HOLD_DRAIN := 15.0          # stamina per second while holding a shield up
const STAMINA_PER_DAMAGE := 0.3   # stamina spent per point of damage blocked
const PARRY_NEGATE := 0.95
const PARRY_REFLECT := 0.5
const STUN_TIME := 1.0
const RADIUS := 17.0

var guarding := false
var _t := 0.0
var _last_parry_start := -10.0
var _parry_armed := false
var _clock := 0.0
var _stun := 0.0
var _aim := Vector2.DOWN
var _flash := 0.0
var _flash_col := Color.WHITE

@onready var player: Node2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")
@onready var equipment: Equipment = get_parent().get_node("Equipment")


func _ready() -> void:
	stats.guard_filter = _filter
	z_index = 6
	position = Vector2(0, -10)


func _shield() -> Item:
	return equipment.get_item("shield")


func _has_sword() -> bool:
	var w := equipment.get_item("weapon")
	return w != null and w.weapon_kind == "sword"


func can_guard() -> bool:
	return stats.health > 0.0 and _stun <= 0.0 and (_shield() != null or _has_sword())


func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		pressed = true
	if pressed and not guarding and can_guard():
		_start()
		get_viewport().set_input_as_handled()


func _held() -> bool:
	return player.input_guard


func _start() -> void:
	guarding = true
	_t = 0.0
	_parry_armed = _clock - _last_parry_start >= PARRY_LOCKOUT
	if _parry_armed:
		_last_parry_start = _clock


func _stop() -> void:
	guarding = false
	queue_redraw()


func in_parry_window() -> bool:
	return guarding and _parry_armed and _t < PARRY_WINDOW


## Parry window, stun and stamina drain run on the fixed game tick (a server runs the same).
func _physics_process(delta: float) -> void:
	_clock += delta
	_stun = maxf(_stun - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	if guarding:
		_t += delta
		var aim: Vector2 = player.aim_world - player.global_position - position
		if aim.length() > 1.0:
			_aim = aim.normalized()
		if not can_guard():
			_stop()
		elif _shield() != null:
			if not _held():
				_stop()
			elif not stats.spend_stamina(HOLD_DRAIN * delta):
				_break()
		elif _t >= PARRY_WINDOW:   # sword only: just the parry
			_stop()
	if guarding or _flash > 0.0:
		queue_redraw()


func _break() -> void:
	stats.stamina = 0.0
	_stun = STUN_TIME
	_flash = 0.3
	_flash_col = Color("e03c3c")
	_say("GUARD BROKEN", Color("e03c3c"))
	_stop()


func _say(text: String, col: Color) -> void:
	if player.get_parent():
		FloatingText.spawn(player.get_parent(), player.position + Vector2(0, -34), text, col)


## Called by Stats.take_damage for attacks that have a direction. Returns the damage to take.
func _filter(amount: float, source: Node, origin: Vector2) -> float:
	if not guarding:
		return amount
	var to := origin - (player.global_position + position)
	if to.length() > 1.0 and absf(angle_difference(to.angle(), _aim.angle())) > HALF_ARC:
		return amount   # hit from the side or behind
	_flash = 0.25
	if in_parry_window():
		_flash_col = Color("ffe066")
		_say("PARRY!", Color("ffe066"))
		if source != null and is_instance_valid(source):
			var st := source.get_node_or_null("Stats") as Stats
			if st and st != stats:
				st.take_damage(amount * PARRY_REFLECT, player)
		return amount * (1.0 - PARRY_NEGATE)
	var shield := _shield()
	if shield == null:
		return amount
	var cost := amount * STAMINA_PER_DAMAGE
	if not stats.spend_stamina(cost):
		_break()
		return amount
	_flash_col = Color("bcd0e8")
	_say("BLOCKED", Color("bcd0e8"))
	return amount * (1.0 - clampf(shield.block_percent, 0.0, 100.0) / 100.0)


func _draw() -> void:
	var a := _aim.angle()
	if guarding:
		var col := Color("ffe066") if in_parry_window() else Color("bcd0e8")
		col.a = 0.9
		draw_arc(Vector2.ZERO, RADIUS, a - HALF_ARC, a + HALF_ARC, 20, col, 2.0)
		draw_arc(Vector2.ZERO, RADIUS - 2.0, a - HALF_ARC, a + HALF_ARC, 20, Color(col.r, col.g, col.b, 0.35), 1.0)
	if _flash > 0.0:
		var k := _flash / 0.25
		draw_arc(Vector2.ZERO, RADIUS + (1.0 - k) * 8.0, a - HALF_ARC, a + HALF_ARC, 20,
				Color(_flash_col.r, _flash_col.g, _flash_col.b, clampf(k, 0.0, 1.0)), 2.0)
