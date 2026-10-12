extends "res://scripts/skeleton_wizard.gd"
## Troll: a big grey brute in the grey valley that walks up to you and lobs rocks. Each throw
## puts a red warning circle on the ground under its target; the rock leaves the troll's fist
## partway through the throw, flies in a high arc and lands on the circle when the warning ends.
##
## Same brain as the skeleton wizard (wander, chase, throw, leash home, loot, respawn); only the
## throw is different. It does not back away from you like the wizards do (keep_away 0 in
## troll.tscn). Everything you see is in troll_look.gd.

@export_group("Rock")
@export var rock_damage := 100.0
@export var rock_radius := 22.0
## Seconds from the circle appearing to the rock landing.
@export var rock_warn := 1.0
@export var rock_cooldown := 2.4

const ROCK := preload("res://scripts/troll_rock.gd")
## Per facing (down, up, left, right): the last throw frame before the rock leaves, and where
## the fist is in that frame (world px from the troll's feet). Measured from art/troll.png.
const FIST := [
	{"frame": 3, "at": Vector2(-5.0, -23.0)},
	{"frame": 3, "at": Vector2(2.5, -26.0)},
	{"frame": 3, "at": Vector2(-17.0, -19.5)},
	{"frame": 3, "at": Vector2(18.0, -16.5)},
]
## Death: 7 frames at this speed, then it lies there and fades.
const DEATH_FPS := 9.0


func _start_cast(target: Node2D) -> void:
	face = _face_of(target.global_position - global_position)
	cast_t = 0.0
	_cast_timer = rock_cooldown
	var fist: Dictionary = FIST[face]
	var r: TrollRock = ROCK.new()
	r.damage = rock_damage * (1.0 + 0.1 * float(maxi(level - 20, 0)))
	r.radius = rock_radius
	r.warn_time = rock_warn
	r.launch_at = (float(fist["frame"]) + 1.0) / CAST_FPS
	r.launch_from = global_position + fist["at"]
	r.global_position = AttackRules.predict(target, rock_warn, aim_lead)
	AttackGuard.bind(r, self)
	_add_ground_attack(r)
