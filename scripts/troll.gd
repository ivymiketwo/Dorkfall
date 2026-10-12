extends "res://scripts/skeleton_wizard.gd"
## Troll: a big grey brute in the grey valley with a stone club. It walks up to you and swings
## the club overhead into the ground:
##   - up close, a red circle appears where the club will land; it hurts anyone in it.
##   - further away, the same smash knocks a chunk of rock flying at you; a red circle appears
##     under you and the rock lands on it.
## Same brain as the skeleton wizard (wander, chase, leash home, loot, respawn); only the
## attacks and the chase are different (it never backs away). Everything you see is in
## troll_look.gd; the club is drawn into the sprite by tools/gen_troll_club.py.

@export_group("Club")
@export var smash_damage := 120.0
@export var smash_radius := 14.0
## It swings at you when you are this close (world px).
@export var smash_range := 16.0
@export var smash_cooldown := 1.6

@export_group("Rock")
@export var rock_damage := 100.0
@export var rock_radius := 22.0
## Seconds the knocked rock flies before landing.
@export var rock_flight := 0.4
@export var rock_cooldown := 2.4

const ROCK := preload("res://scripts/troll_rock.gd")
## Seconds from the start of a swing to the club hitting the ground.
const IMPACT := 0.65
## Frames after the hit play at this many seconds each.
const RECOVER_FRAME := 0.12
const SWING_FRAMES := 7
## Per facing (down, up, left, right): the swing frame where the club hits the ground, and
## where it lands (world px from the troll's feet; the smash circle goes there and the rock
## flies from there). The club head's centre in that frame (see tools/gen_troll_club.py).
const SMASH := [
	{"frame": 4, "at": Vector2(-5.5, 6.5)},
	{"frame": 4, "at": Vector2(-11.0, -12.5)},
	{"frame": 3, "at": Vector2(-16.0, -7.5)},
	{"frame": 3, "at": Vector2(19.5, -4.0)},
]
## Death: 7 frames at this speed, then it lies there and fades.
const DEATH_FPS := 9.0

var _smash_timer := 0.0


func _physics_process(delta: float) -> void:
	_smash_timer -= delta
	super(delta)


func _cast_length() -> float:
	var f: int = SMASH[face]["frame"]
	return IMPACT + RECOVER_FRAME * float(SWING_FRAMES - f)


## Which swing frame shows `t` seconds into a swing (the look reads this). The wind-up frames
## slow down towards the top of the swing, so the raised club hangs there for a moment.
func swing_frame(t: float) -> int:
	var f: int = SMASH[face]["frame"]
	if t < IMPACT:
		return mini(int(float(f) * pow(t / IMPACT, 1.0 / 1.4)), f - 1)
	return mini(f + int((t - IMPACT) / RECOVER_FRAME), SWING_FRAMES - 1)


func _chase(player: Node2D, to_player: Vector2, dist: float) -> Vector2:
	if dist <= smash_range and _smash_timer <= 0.0:
		_swing(player, false)
		return Vector2.ZERO
	if dist > smash_range * 1.6 and dist <= cast_range and _cast_timer <= 0.0:
		_swing(player, true)
		return Vector2.ZERO
	if dist > smash_range * 0.7:
		return to_player / dist
	face = _face_of(to_player)          # waiting for the club: keep facing you
	return Vector2.ZERO


func _swing(target: Node2D, knock_rock: bool) -> void:
	face = _face_of(target.global_position - global_position)
	cast_t = 0.0
	var lands: Vector2 = global_position + SMASH[face]["at"]
	var mult := 1.0 + 0.1 * float(maxi(level - 20, 0))
	var a: TrollRock = ROCK.new()
	if knock_rock:
		_cast_timer = rock_cooldown
		_smash_timer = maxf(_smash_timer, 0.6)
		a.damage = rock_damage * mult
		a.radius = rock_radius
		a.warn_time = IMPACT + rock_flight
		a.launch_at = IMPACT
		a.launch_from = lands
		a.global_position = AttackRules.predict(target, a.warn_time, aim_lead)
	else:
		_smash_timer = smash_cooldown
		_cast_timer = maxf(_cast_timer, 0.6)
		a.thrown = false
		a.damage = smash_damage * mult
		a.radius = smash_radius
		a.warn_time = IMPACT
		a.global_position = lands
	AttackGuard.bind(a, self)
	_add_ground_attack(a)
