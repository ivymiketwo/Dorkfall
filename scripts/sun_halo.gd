class_name SunHalo
extends Node2D
## The Sun Staff's attack, in four stages:
##   1. charge: a bright orb on the staff's tip pulses `pulses` times as it grows,
##   2. it turns into a shining halo standing upright that floats off toward the mouse, slowing
##      down and wobbling like a smoke ring,
##   3. right away it divides into three halos in a row, which drift to a stop and hover,
##   4. then a huge pulsing sun beam bursts from the staff through the three halos and lingers.
## Stages 1-3 are a cast: the cast bar fills and the caster can't move until the beam fires.
## Only the beam hurts: everything inside it takes `damage` once, when it fires.
##
## Made by BasicAttack from the Sun Staff's ability (abilities/sun_halo.tres, which points at
## scenes/spells/sun_halo.tscn). Tweak the numbers below in that scene's Inspector; the ability
## holds the damage, mana and cooldown (keep the cooldown about as long as the whole show).
## The rules (when it launches, where the halos are, when the beam fires and who it hits) run on
## the game tick through AttackTimeline, and the halos' path depends only on time, so a server can
## run the same thing. Everything else is only drawing.

@export_group("Charge")
## Seconds the orb grows on the staff before the halo leaves.
@export var charge_time := 0.75
## How many times the orb throbs while growing.
@export var pulses := 3
## The orb's radius at the start and at the end of the charge (world px).
@export var orb_start_radius := 1.0
@export var orb_end_radius := 3.5

@export_group("Halo")
## Seconds the halo floats out before it stops.
@export var drift_time := 0.7
## How far it floats (world px). It starts fast and keeps slowing down, like a smoke ring.
@export var drift_distance := 36.0
## Seconds the three halos hover in place (bobbing a little) before they flare up.
@export var hover_time := 0.45
## Half the halo's height (world px).
@export var halo_radius := 7.5
## How far it sways from side to side while drifting (world px).
@export var wobble := 1.5
## Seconds after it leaves the staff that it starts dividing.
@export var split_after := 0.1
## Seconds the division takes, and how far apart the three halos end up (world px).
@export var split_time := 0.45
@export var split_gap := 13.0
## Seconds the halos flare up before the beam.
@export var gather_time := 0.15

@export_group("Beam")
## How wide the beam is (world px; 1 world px = 2 art px).
@export var beam_width := 15.0
## Seconds it lingers at full strength (it then fades over `beam_fade`).
@export var beam_time := 0.25
@export var beam_fade := 0.12
## How far it reaches from the staff (world px), and at least how far past the farthest halo.
@export var beam_reach := 140.0
@export var beam_past_halos := 25.0
## How many times it throbs while it lingers.
@export var beam_pulses := 3

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 150.0

# the sun staff's orb colours
const WHITE := Color(1.0, 0.99, 0.92)
const PALE := Color8(251, 233, 151)
const GOLD := Color8(246, 203, 80)
const DEEP := Color8(223, 158, 48)
const EMBER := Color8(183, 112, 32)

const CHARGE_SOUND := preload("res://audio/fireball_cast.wav")
const BEAM_SOUND := preload("res://audio/ray_swoosh.wav")
const BOOM_SOUND := preload("res://audio/fireball_hit.wav")
const HALO_POINTS := 32

var _timeline: AttackTimeline
var _orb: Node2D                    # the charging orb, a child of the caster so it can sit on the staff
var _launched := false
var _from := Vector2.ZERO           # where the halo left (global)
var _dir := Vector2.RIGHT
var _fired := false
var _fizzled := false
var _cast_over := false
var _beam_from := Vector2.ZERO
var _beam_dir := Vector2.RIGHT
var _beam_len := 0.0
var _fringe: Array = []             # the beam's ragged end, re-rolled a few times a second
var _fringe_at := -1


func _ready() -> void:
	z_index = 4
	global_position = Vector2.ZERO          # drawing is done in world coordinates
	var fire_at := _fire_time()
	_timeline = AttackTimeline.new() \
		.at(charge_time, _launch) \
		.at(fire_at, _fire) \
		.lasts(fire_at + beam_time + beam_fade)
	if caster != null:
		_face(caster.aim_world - caster.global_position)
		# stages 1-3 are a cast: rooted, with the cast bar filling, until the beam fires
		if "rooted_until" in caster:
			caster.rooted_until = GameClock.now + fire_at
		var hb := caster.get_node_or_null("Hotbar")
		if hb != null and hb.has_method("start_channel"):
			hb.start_channel(fire_at)
		_orb = Node2D.new()
		_orb.name = "SunChargeOrb"
		_orb.draw.connect(_draw_orb)
		caster.add_child(_orb)
		_place_orb()
	_sound(CHARGE_SOUND, HeldWeapon.beam_origin(caster) if caster else Vector2.ZERO, 1.15, -4.0)


func _exit_tree() -> void:
	if _orb != null and is_instance_valid(_orb):
		_orb.queue_free()
	_end_cast()


## Lets the caster move again and empties the cast bar (when the beam fires, or if it never does).
func _end_cast() -> void:
	if _cast_over:
		return
	_cast_over = true
	if caster == null or not is_instance_valid(caster):
		return
	if "rooted_until" in caster:
		caster.rooted_until = minf(caster.rooted_until, GameClock.now)
	var hb := caster.get_node_or_null("Hotbar")
	if hb != null and hb.has_method("end_channel"):
		hb.end_channel()


## When the beam fires (and the cast ends), in seconds from the start.
func _fire_time() -> float:
	return charge_time + _hover_end() + gather_time


## Seconds after the halo leaves the staff that the hovering ends and the flare starts.
func _hover_end() -> float:
	return drift_time + hover_time


# --- rules (game tick) ---

func _physics_process(delta: float) -> void:
	if not _launched and not _caster_ok():
		queue_free()           # the caster died or left before the halo was out
		return
	if _timeline.tick(delta):
		queue_free()


func _caster_ok() -> bool:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return false
	var st := caster.get_node_or_null("Stats")
	return st == null or st.health > 0.0


func _launch() -> void:
	_launched = true
	_face(caster.aim_world - caster.global_position)
	_from = HeldWeapon.beam_origin(caster)
	var aim: Vector2 = caster.aim_world - _from
	_dir = aim.normalized() if aim.length() > 1.0 else _facing_dir()


## Turns the caster toward `v` (so the staff's orb is on that side).
func _face(v: Vector2) -> void:
	if "facing" in caster and v.length() > 1.0:
		caster.facing = (3 if v.x > 0 else 2) if absf(v.x) > absf(v.y) else (0 if v.y > 0 else 1)


func _facing_dir() -> Vector2:
	var f: int = caster.facing if "facing" in caster else 0
	return [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT][f]


## The middle halo's centre (global), `s` seconds after it left the staff. Only depends on time.
func halo_spot(s: float) -> Vector2:
	var sc := clampf(s, 0.0, _hover_end())
	var x := clampf(sc / drift_time, 0.0, 1.0)
	var along := drift_distance * (1.0 - pow(1.0 - x, 3.0))
	var side := sin(sc * 4.2) * wobble * x
	var bob := sin(sc * 6.0) * 0.6 * x          # a gentle float up and down while hovering
	return _from + _dir * along + _dir.orthogonal() * side + Vector2(0.0, bob)


## How far the halo has divided (0 = one halo, 1 = three, `split_gap` apart).
func split_amount(s: float) -> float:
	return smoothstep(0.0, 1.0, (s - split_after) / maxf(split_time, 0.01))


func _fire() -> void:
	_fired = true
	_end_cast()
	if not _caster_ok():
		_fizzled = true        # no caster to fire it: the halos just fade away
		return
	var mid := halo_spot(_hover_end())
	_face(mid - caster.global_position)
	_beam_from = HeldWeapon.beam_origin(caster)
	var to := mid - _beam_from
	_beam_dir = to.normalized() if to.length() > 4.0 else _dir     # from the staff, through the halos
	var far := mid + _dir * split_gap
	_beam_len = maxf((far - _beam_from).dot(_beam_dir) + beam_past_halos, beam_reach)
	var stats := caster.get_node_or_null("Stats") as Stats
	var amount := damage * (stats.magic_mult() if stats else 1.0)
	for body in _bodies_in_beam():
		var t := body.get_node_or_null("Stats") as Stats
		if t:
			t.take_damage(amount, caster)
	_sound(BEAM_SOUND, _beam_from, 0.6, 2.0)
	_sound(BOOM_SOUND, _beam_from + _beam_dir * _beam_len * 0.5, 0.75, -2.0)


## Every physics body inside the beam's rectangle (once each, the caster excluded).
func _bodies_in_beam() -> Array:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(_beam_len, beam_width)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(_beam_dir.angle(), _beam_from + _beam_dir * _beam_len * 0.5)
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var out: Array = []
	var seen := {}
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 64):
		var b := hit["collider"] as Node
		if b != null and not seen.has(b):
			seen[b] = true
			out.append(b)
	return out


func _sound(stream: AudioStream, at: Vector2, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = at
	p.play()


# --- drawing only ---

func _process(_delta: float) -> void:
	_place_orb()
	queue_redraw()


func _place_orb() -> void:
	if _orb == null or not is_instance_valid(_orb):
		return
	var t := _timeline.t
	_orb.visible = t < charge_time + 0.15 and _caster_ok()
	if _orb.visible:
		_orb.global_position = HeldWeapon.beam_origin(caster)
		HeldWeapon.layer_above_staff(caster, _orb)
		_orb.queue_redraw()


## The charging orb, drawn on its own node on the staff's tip.
func _draw_orb() -> void:
	var t := _timeline.t
	var x := clampf(t / charge_time, 0.0, 1.0)
	var pulse := pow(absf(sin(PI * pulses * x)), 2.0)
	var r := lerpf(orb_start_radius, orb_end_radius, x) * (1.0 + 0.4 * pulse)
	if t > charge_time:
		r *= clampf(1.0 - (t - charge_time) / 0.15, 0.0, 1.0)     # pours itself into the halo
	if r <= 0.05:
		return
	_orb.draw_circle(Vector2.ZERO, r * 2.1, _a(EMBER, 0.16))
	_orb.draw_circle(Vector2.ZERO, r * 1.5, _a(GOLD, 0.35))
	_orb.draw_circle(Vector2.ZERO, r, GOLD)
	_orb.draw_circle(Vector2.ZERO, r * 0.72, PALE)
	_orb.draw_circle(Vector2.ZERO, r * 0.4, WHITE)
	if pulse > 0.3:     # a sparkle at the top of each throb
		var s := r * 2.8 * pulse
		var c := _a(WHITE, pulse)
		_orb.draw_rect(Rect2(-s, -0.25, s * 2.0, 0.5), c)
		_orb.draw_rect(Rect2(-0.25, -s, 0.5, s * 2.0), c)


func _draw() -> void:
	if not _launched:
		return
	var t := _timeline.t
	var s := t - charge_time
	var fire_at := _fire_time()
	# the halos: until a moment after the beam fires (or a slower fade if it fizzled)
	var halo_end := fire_at + (0.6 if _fizzled else 0.12)
	if t < halo_end:
		var a := 1.0
		var grow := 1.0
		if t > fire_at:
			var f := (t - fire_at) / (halo_end - fire_at)
			a = 1.0 - f
			grow = 1.0 + 0.5 * f
		var r := halo_radius * (0.35 + 0.65 * _ease_out(clampf(s / 0.3, 0.0, 1.0))) * grow
		var flare := clampf((s - _hover_end()) / maxf(gather_time, 0.01), 0.0, 1.0) if t <= fire_at else 1.0
		r *= 1.0 - 0.12 * flare
		var mid := halo_spot(s)
		var k := split_amount(s)
		var shine := 0.85 + 0.15 * sin(t * 14.0) + 0.4 * flare
		if k <= 0.0:
			_draw_halo(mid, r, a, shine, t)
		else:
			for i in [-1, 1]:
				# the two new halos peel off the middle one, dim at first
				_draw_halo(mid + _dir * split_gap * k * i, r, a * (0.4 + 0.6 * k), shine, t + i * 0.7)
			_draw_halo(mid, r, a, shine + 0.5 * (1.0 - k) * k * 4.0, t)
	if _fired and not _fizzled:
		_draw_beam(t - fire_at)


## One halo: a ring standing upright across its path. Seen from the side when it flies left or
## right (a tall thin oval), more from the front when it flies up or down the screen.
func _draw_halo(center: Vector2, r: float, a: float, shine: float, t: float) -> void:
	if a <= 0.0:
		return
	var across := _dir.orthogonal()
	var thin := lerpf(0.3, 0.75, _dir.y * _dir.y)
	var pts := PackedVector2Array()
	for i in HALO_POINTS + 1:
		var th := TAU * i / HALO_POINTS
		pts.append(center + across * (r * cos(th)) + _dir * (r * thin * sin(th)))
	var b := clampf(shine, 0.0, 1.6)
	draw_colored_polygon(pts, _a(PALE, 0.12 * a * b))           # a faint shine inside
	draw_polyline(pts, _a(EMBER, 0.3 * a), 3.0)
	draw_polyline(pts, _a(GOLD, a), 1.5)
	draw_polyline(pts, _a(WHITE.lerp(PALE, 0.5 if b < 1.0 else 0.0), a * minf(b, 1.0)), 0.5)
	# a glint running round the ring
	var th := t * 7.0
	var glint := center + across * (r * cos(th)) + _dir * (r * thin * sin(th))
	draw_circle(glint, 1.0, _a(WHITE, a))


func _draw_beam(bt: float) -> void:
	var total := beam_time + beam_fade
	if bt >= total:
		return
	var env := _ease_out(clampf(bt / 0.04, 0.0, 1.0))                # bursts out
	var a := 1.0
	if bt > beam_time:
		var f := (bt - beam_time) / beam_fade
		env *= 1.0 - f * 0.7
		a = 1.0 - f
	var throb := 0.88 + 0.12 * cos(TAU * beam_pulses * clampf(bt / beam_time, 0.0, 1.0))
	var w := beam_width * env * throb
	var tick := int(bt / 0.04)
	if tick != _fringe_at:
		_fringe_at = tick
		_fringe.clear()
		for i in 7:
			_fringe.append(Vector2(randf_range(-0.45, 0.45), randf_range(0.0, 0.45)))
	draw_set_transform(_beam_from, _beam_dir.angle())
	var layers := [[1.35, _a(EMBER, 0.28 * a)], [1.0, _a(GOLD, 0.92 * a)], [0.62, _a(PALE, a)], [0.28, _a(WHITE, a)]]
	for layer: Array in layers:
		var lw: float = w * layer[0]
		var col: Color = layer[1]
		draw_rect(Rect2(0.0, -lw * 0.5, _beam_len, lw), col)
		draw_circle(Vector2.ZERO, lw * 0.5, col)           # round where it leaves the staff
		for f: Vector2 in _fringe:                          # ragged, flaring end
			var fh := lw * 0.3
			var fy := f.x * lw - fh * 0.5
			draw_rect(Rect2(_beam_len, fy, f.y * w, fh), col)
	draw_set_transform(Vector2.ZERO)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(alpha, 0.0, 1.0))
