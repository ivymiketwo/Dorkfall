class_name Ward
extends Node2D
## The wizard's block (hold right mouse button, or Q). Lives on the player.
##
## A summoning circle spins under your feet and a glass orb surrounds you. The orb is lit
## from the mouse's side: that is the side you are warding.
## - Aimed attacks from where you're aiming (a 120 degree arc in front of you): stops 50%
##   (FACING_PERCENT, raised by gear later) and costs 25% of the stopped damage in mana.
## - Everything else (ground effects like marked circles and boulders, and aimed hits from the
##   side or behind): stops 30% and costs 50% of the stopped damage in mana.
## - Holding it costs mana too, slows you to half speed and you can't attack, cast or hop.
##   Run out of mana and the ward breaks: you can't raise it again for STUN_TIME.
## - Parry: a hit landing in the first PARRY_WINDOW seconds is almost fully stopped and half
##   of it is thrown back at the attacker. A new parry window only opens PARRY_LOCKOUT
##   seconds after the last one started, so mashing doesn't work.
##
## The rules run on the fixed game tick and read only `player.input_ward` / `aim_world`;
## the circle and orb are only drawing.

const PARRY_WINDOW := 0.25
const PARRY_LOCKOUT := 0.8
const HALF_ARC := deg_to_rad(60.0)
## Hits from where you're aiming (an aimed attack, inside the 120 degree arc): stops this much
## (plus gear / skill bonuses, see Stats.ward_bonus_percent), paying this share of it in mana.
const FACING_PERCENT := 50.0
const FACING_MANA := 0.25
## Everything else (ground effects, and aimed hits from the side or behind): stops less and
## costs more mana per point stopped.
const OTHER_PERCENT := 30.0
const OTHER_MANA := 0.5
const MAX_PERCENT := 90.0
const HOLD_DRAIN := 10.0          # mana per second while warding
const PARRY_NEGATE := 0.95
const PARRY_REFLECT := 0.5
const STUN_TIME := 1.0
const SPEED_MULT := 0.5

## Look
const ORB_RADIUS := 15.0          # world px
const ORB_CENTER := Vector2(0, -10)
const CIRCLE_RADIUS := 15.0
const FADE_OUT := 0.15
const ORB_SHADER := preload("res://shaders/ward_orb.gdshader")
const BLUE := Color(0.3, 0.72, 1.0)
const GOLD := Color("ffe066")
const RED := Color("e03c3c")

var warding := false
var _t := 0.0
var _last_parry_start := -10.0
var _parry_armed := false
var _clock := 0.0
var _stun := 0.0
var _aim := Vector2.RIGHT
var _flash := 0.0
var _flash_col := BLUE
var _fade := 0.0                  # how visible the look is (fades out after letting go)
var _look_t := 0.0                # seconds since the ward went up (spins the circle)
var _look_aim := Vector2.RIGHT    # the orb's light: follows the mouse every frame (drawing only)

var _circle: Node2D
var _orb: Sprite2D
var _mat: ShaderMaterial

@onready var player: Node2D = get_parent()
@onready var stats: Stats = get_parent().get_node("Stats")


func _ready() -> void:
	stats.ward_filter = _filter
	stats.died.connect(_stop)
	# the circle goes under the character (first child), the orb over it
	_circle = Node2D.new()
	_circle.draw.connect(func() -> void: SummonCircle.draw(_circle, CIRCLE_RADIUS, _look_t, _fade, 8))
	_circle.hide()
	player.add_child.call_deferred(_circle)
	(func() -> void: player.move_child(_circle, 0)).call_deferred()
	var px := int(ORB_RADIUS * 4.0)                       # one texel per screen pixel
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_mat = ShaderMaterial.new()
	_mat.shader = ORB_SHADER
	_mat.set_shader_parameter("px", float(px))
	_orb = Sprite2D.new()
	_orb.texture = ImageTexture.create_from_image(img)
	_orb.scale = Vector2(0.5, 0.5)
	_orb.position = ORB_CENTER
	_orb.material = _mat
	_orb.z_index = 6
	_orb.hide()
	add_child(_orb)


func can_ward() -> bool:
	if stats.health <= 0.0 or _stun > 0.0 or stats.mana <= 0.0:
		return false
	if not player.is_physics_processing() or player.get("control_locked"):
		return false
	var hb := player.get_node_or_null("Hotbar") as Hotbar
	return hb == null or hb.casting_slot == -1


func _start() -> void:
	warding = true
	_t = 0.0
	_look_t = 0.0
	var aim: Vector2 = player.aim_world - (player.global_position + ORB_CENTER)
	if aim.length() > 1.0:
		_aim = aim.normalized()
	_look_aim = _aim
	_parry_armed = _clock - _last_parry_start >= PARRY_LOCKOUT
	if _parry_armed:
		_last_parry_start = _clock


func _stop() -> void:
	warding = false


func in_parry_window() -> bool:
	return warding and _parry_armed and _t < PARRY_WINDOW


## Parry window, stun and mana drain run on the fixed game tick (a server runs the same).
func _physics_process(delta: float) -> void:
	_clock += delta
	_stun = maxf(_stun - delta, 0.0)
	var held: bool = player.get("input_ward")
	if held and not warding and can_ward():
		_start()
	if warding:
		_t += delta
		var aim: Vector2 = player.aim_world - (player.global_position + ORB_CENTER)
		if aim.length() > 1.0:
			_aim = aim.normalized()
		if not held or stats.health <= 0.0:
			_stop()
		elif not stats.spend_mana(HOLD_DRAIN * delta):
			_break()


func _break() -> void:
	stats.mana = 0.0
	stats.changed.emit()
	_stun = STUN_TIME
	_flash = 1.0
	_flash_col = RED
	_say("WARD BROKEN", RED)
	_stop()


func _say(text: String, col: Color) -> void:
	if player.get_parent():
		FloatingText.spawn(player.get_parent(), player.position + Vector2(0, -34), text, col)


## How much of a hit the Ward stops (percent) when it comes from where you're aiming.
func facing_percent() -> float:
	return minf(FACING_PERCENT + stats.ward_bonus_percent, MAX_PERCENT)


## Called by Stats.take_damage for every hit except self-inflicted ones (poison ticks, hop
## costs). `origin` = where an aimed attack came from, Vector2.INF for ground effects.
## Returns the damage to take.
func _filter(amount: float, source: Node, origin: Vector2) -> float:
	if not warding or amount <= 0.0:
		return amount
	var facing := false
	if origin != Vector2.INF:
		var to := origin - (player.global_position + ORB_CENTER)
		facing = to.length() <= 1.0 or absf(angle_difference(to.angle(), _aim.angle())) <= HALF_ARC
	_flash = 1.0
	if facing and in_parry_window():
		_flash_col = GOLD
		_say("PARRY!", GOLD)
		if source != null and is_instance_valid(source):
			var st := source.get_node_or_null("Stats") as Stats
			if st and st != stats:
				st.take_damage(amount * PARRY_REFLECT, player)
		return amount * (1.0 - PARRY_NEGATE)
	var pct := facing_percent() if facing else OTHER_PERCENT
	var rate := FACING_MANA if facing else OTHER_MANA
	var stopped := amount * pct / 100.0
	if stats.mana < stopped * rate:
		# not enough mana for all of it: stop what the last of it pays for, then the ward breaks
		stopped = maxf(stats.mana, 0.0) / rate
		_break()
		return amount - stopped
	stats.spend_mana(stopped * rate)
	_flash_col = Color(0.85, 0.95, 1.0)
	_say("WARDED" if facing else "PARTLY WARDED", BLUE)
	return amount - stopped


## Only drawing from here on.
func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / 0.3, 0.0)
	_fade = 1.0 if warding else maxf(_fade - delta / FADE_OUT, 0.0)
	_look_t += delta
	var show := _fade > 0.0
	_circle.visible = show
	_orb.visible = show
	if not show:
		return
	if warding:   # follow the mouse every frame so the light never lags behind it
		var aim: Vector2 = player.get_global_mouse_position() - (player.global_position + ORB_CENTER)
		if aim.length() > 1.0:
			_look_aim = aim.normalized()
	var appear := clampf(_look_t / 0.12, 0.0, 1.0)
	_mat.set_shader_parameter("light_dir", _look_aim)
	_mat.set_shader_parameter("strength", _fade * appear)
	_mat.set_shader_parameter("time", _look_t)
	_mat.set_shader_parameter("flash", _flash)
	_mat.set_shader_parameter("flash_col", _flash_col)
	_mat.set_shader_parameter("tint", GOLD.lerp(BLUE, 0.6) if in_parry_window() else BLUE)
	_circle.queue_redraw()
