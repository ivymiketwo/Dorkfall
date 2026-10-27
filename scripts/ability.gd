class_name Ability
extends Resource
## One hotbar ability. Each lives in res://abilities/*.tres — open one in
## the Inspector to tweak costs, cast times and amounts.

enum Kind { PROJECTILE, TRANSFER, BEAM, HOP, HOME_TELEPORT, SWARM, SPELL }

@export var display_name := ""
@export var kind := Kind.PROJECTILE
## Which 16x16 icon in art/icons.png (0 = leftmost).
@export var icon_index := 0

@export_group("Costs")
@export var mana_cost := 0.0

@export_group("Timing")
## Seconds spent casting before it goes off (0 = instant).
@export var cast_time := 0.0
## Seconds before this slot can be used again.
@export var cooldown := 0.0
## A summoning circle under the caster while the cast bar fills.
@export_enum("none", "blue", "red") var cast_circle := "none"

@export_group("Projectile")
@export var projectile_scene: PackedScene
## Pixels per second. 215 is roughly 30 mph if one tile is one meter.
@export var projectile_speed := 215.0
@export var damage := 40.0
## Cast from a staff: each hit does this share of the staff's damage range instead of `damage`
## (1 = 100%, 2.4 = 240%). 0 = always the fixed `damage` above.
@export var weapon_percent := 0.0

@export_group("Beam")
## Instant thin beam toward the mouse. Uses `damage` above. Hits everything in
## its path (it pierces) and stops at walls and trees.
@export var beam_length := 150.0
## Beam colour, and whether a thin swirl of lightning crackles around it.
@export var beam_color := Color(0.35, 0.85, 1.0)
@export var beam_lightning := false
## Poison left on everything the beam hits: damage per second, for this many seconds (0 = none).
@export var poison_dps := 0.0
@export var poison_time := 0.0

@export_group("Spell")
## A staff's own special attack that runs itself (kind SPELL), e.g. the Sun Staff's halo beam
## (scenes/spells/sun_halo.tscn). Its root script gets `caster` and `damage` (the one above) set
## before it is added to the world. Its own timings are in that scene's Inspector.
@export var spell_scene: PackedScene

@export_group("Swarm")
## Crimson Swarm: this many beams land on non-overlapping circles around the mouse.
## Each circle deals `damage` above to everything in it.
@export var swarm_count := 10
@export var swarm_spot_radius := 6.0
## How far from the caster the cluster can be centred (world px).
@export var swarm_range := 170.0
## Crimson Barrage: the knot hovers and shoots one missile every `swarm_interval` seconds
## (`swarm_count` in all), each at wherever the caster is aiming when it leaves.
@export var swarm_stream := false
@export var swarm_interval := 0.5

@export_group("Transfer")
@export_enum("health", "mana") var transfer_from: String = "health"
@export_enum("health", "mana") var transfer_to: String = "mana"
@export var transfer_amount := 50.0

@export_group("Hop")
## Gust hop: a ballistic leap. Landing opens a short window to press Space and hop again.
@export var hop_speed := 150.0
@export var hop_time := 0.5
@export var hop_height := 13.0
@export var hop_window := 0.15
## Health the first hop costs (it can kill you).
@export var hop_health_cost := 50.0
## Health each chained hop costs.
@export var hop_chain_health_cost := 35.0

## Plays from the moment the cast starts (a projectile takes it over once it launches).
@export var cast_start_sound: AudioStream


## One hit's damage before Intelligence: a roll of the staff's range times `weapon_percent`, or the
## fixed `damage` when this spell doesn't use the staff (or there's no staff).
func hit_damage(weapon: Item) -> float:
	if weapon_percent > 0.0 and weapon != null and weapon.has_damage():
		return weapon.roll_damage() * weapon_percent
	return damage
