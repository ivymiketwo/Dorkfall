class_name Experience
extends Node
## Level and XP for a character. Add as a child of the player.
##
## Curve: XP needed to go from level L to L+1 is
##     BASE_XP * GROWTH^(L-1)
## BASE_XP is 90 kills of an equal-level Mangyang (10 XP) for level 1 -> 2.

signal changed
signal leveled_up(new_level: int)

const MAX_LEVEL := 50
const BASE_XP := 900.0     # 90 Mangyangs x 10 XP (3x the original 300)
const GROWTH := 1.15       # each level needs 15% more than the last

## Kills this many levels (or fewer) below you give full XP.
const FULL_XP_GAP := 5
## Kills MORE than this many levels below you give exactly 1 XP.
const MIN_XP_GAP := 8

var level := 1
var xp := 0   # progress into the current level


static func xp_to_next(lvl: int) -> int:
	if lvl >= MAX_LEVEL:
		return 0
	return int(round(BASE_XP * pow(GROWTH, lvl - 1)))


## XP a kill is worth to someone at `player_level`. Monsters far below you
## are worth less; past MIN_XP_GAP they are worth 1.
static func kill_xp(base: int, player_level: int, mob_level: int) -> int:
	var gap := player_level - mob_level
	if gap <= FULL_XP_GAP:
		return base
	if gap > MIN_XP_GAP:
		return 1
	# gap 6, 7, 8 -> 80%, 60%, 40%
	var frac := 1.0 - 0.2 * (gap - FULL_XP_GAP)
	return maxi(1, int(round(base * frac)))


## Credit a kill to whoever last hurt the monster (if it was a player).
static func grant_kill(killer: Node, mob_level: int, base: int, at: Node2D) -> void:
	if killer == null:
		return
	var e := killer.get_node_or_null("Experience") as Experience
	if e == null:
		return
	var amount := kill_xp(base, e.level, mob_level)
	e.add_xp(amount)
	if at and at.get_parent():
		FloatingText.spawn(at.get_parent(), at.position + Vector2(0, -34),
				"+%d XP" % amount, Color("b58cff"))


func _ready() -> void:
	var saved = SaveGame.get_value("experience")
	if saved is Dictionary:
		level = clampi(int(saved.get("level", 1)), 1, MAX_LEVEL)
		xp = maxi(int(saved.get("xp", 0)), 0)
		if level >= MAX_LEVEL:
			xp = 0
		else:
			xp = mini(xp, xp_to_next(level) - 1)
	changed.emit()
	changed.connect(_save)


func _save() -> void:
	SaveGame.put("experience", {"level": level, "xp": xp})


func add_xp(amount: int) -> void:
	if level >= MAX_LEVEL or amount <= 0:
		return
	xp += amount
	var gained := false
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		gained = true
		leveled_up.emit(level)
	if level >= MAX_LEVEL:
		xp = 0
	changed.emit()
	if gained:
		_celebrate()


func _celebrate() -> void:
	var host := get_parent() as Node2D
	if host == null or host.get_parent() == null:
		return
	FloatingText.spawn(host.get_parent(), host.position + Vector2(0, -34),
			"LEVEL UP!  %d" % level, Color("ffe066"), 1.0)
	var stats := host.get_node_or_null("Stats") as Stats
	if stats:
		stats.refill()
