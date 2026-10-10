class_name AttackRules
extends RefCounted
## The hit rules of the boss / monster attacks, with no scenes or drawing in them.
## Each test takes a point in the attack's own local space (the caller converts) and
## the attack's numbers, and says whether it hits. `deal` is the one place an attack
## turns a hit into damage. A server can call all of this as it is.

## Where an attacker's shape is tested on a character (the chest, not the feet).
const CHEST := Vector2(0, -6)


## Flying knife: a lane `width` wide; the blade is at `reach` along it and hits a
## thin slice around the tip.
static func knife_hits(p: Vector2, length: float, width: float, progress: float) -> bool:
	var reach := length * clampf(progress, 0.0, 1.0)
	return absf(p.y) <= width * 0.5 + 2.0 and p.x >= reach - 10.0 and p.x <= reach + 4.0 and p.x >= -4.0


## Lunge slash: a short lane straight ahead.
static func lunge_hits(p: Vector2, length: float, width: float) -> bool:
	return p.x >= -4.0 and p.x <= length + 4.0 and absf(p.y) <= width * 0.5 + 2.0


## Gust cone: inside the cone's angle and no farther than the leading edge.
static func cone_hits(p: Vector2, front: float, length: float, angle: float, half_angle: float) -> bool:
	if p.length() > length or p.length() > front:
		return false
	return absf(angle_difference(angle, p.angle())) <= half_angle


## Bite wedge: within `length` and inside the wedge's opening angle (degrees).
static func wedge_hits(p: Vector2, length: float, spread_deg: float) -> bool:
	return p.length() <= length and absf(rad_to_deg(p.angle())) <= spread_deg * 0.5


## Splash damage (the fireball): full damage at the centre, down to `edge_mult` at the rim
## (and beyond it, for big bodies that only overlap the edge). `d` = distance from the centre.
static func blast_damage(d: float, radius: float, damage: float, edge_mult := 0.5) -> float:
	return damage * lerpf(1.0, edge_mult, clampf(d / radius, 0.0, 1.0))


## Whether an attack from `source` may hurt `target`: players hurt anything, monsters only players.
static func can_hurt(source: Node, target: Node) -> bool:
	if target == null or target == source:
		return false
	var from_player := source != null and is_instance_valid(source) and source.is_in_group("player")
	return from_player or target.is_in_group("player")


## Player damage against a higher-level monster. Up to 3 levels above you: full damage;
## then 5% less per extra level, never below 60% (so fighting up is still worth it).
static func level_gap_mult(player_level: int, monster_level: int) -> float:
	var gap := monster_level - player_level
	if gap <= 3:
		return 1.0
	return maxf(0.6, 1.0 - 0.05 * float(gap - 3))


## Where a target will be after `seconds` if it keeps moving the same way (aim prediction).
## `lead` 1 = all the way, 0 = where it stands now.
static func predict(target: Node2D, seconds: float, lead := 1.0) -> Vector2:
	var v: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	return target.global_position + v * seconds * lead


static func circle_hits(p: Vector2, radius: float) -> bool:
	return p.length() <= radius


## Toxic zone: a disc plus alternating red rays reaching farther out.
static func toxic_covers(p: Vector2, disc_radius: float, ray_radius: float, ray_count: int) -> bool:
	var d := p.length()
	if d <= disc_radius:
		return true
	if d > ray_radius:
		return false
	var seg := TAU / float(ray_count * 2)
	var a := fposmod(p.angle() + seg * 0.5, TAU)
	return int(a / seg) % 2 == 0


static func rect_hits(rect: Rect2, p: Vector2, margin: float) -> bool:
	return rect.grow(margin).has_point(p)


## Applies an attack's damage to a character. `origin` (where the attack came from) makes
## it blockable / parryable; leave it out for ground effects.
static func deal(target: Node, amount: float, source: Node = null, origin := Vector2.INF) -> void:
	var s := target.get_node_or_null("Stats") as Stats
	if s:
		s.take_damage(amount, source, false, origin)
