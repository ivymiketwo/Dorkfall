class_name Stats
extends Node
## Health / stamina / mana pools. Add as a child of anything that needs stats
## (player now, mobs and other players later).

signal changed
signal died
signal damaged(amount: float)
signal out_of_mana

## Draw damage numbers and warnings. A server turns this off.
@export var show_effects := true

@export var max_health := 400.0
@export var max_stamina := 400.0
@export var max_mana := 400.0

@export_group("Regeneration (per second)")
@export var health_regen := 3.0
@export var stamina_regen := 3.0
@export var mana_regen := 3.0
## Seconds after spending stamina before it starts refilling.
@export var stamina_regen_delay := 0.0

## Set by Equipment from worn gear.
var defense_percent := 0.0
var mana_regen_bonus := 0.0
var magic_damage_percent := 0.0
## From Intelligence / Strength / Dexterity (set by Attributes).
var attr_magic_percent := 0.0
var attr_melee_percent := 0.0
var attr_ranged_percent := 0.0

var health: float
var stamina: float
var mana: float
## Whoever last damaged this (used to credit XP for kills).
var last_source: Node = null

## Set by the player's Guard: takes (amount, source, origin), returns the damage to apply.
var guard_filter: Callable
## Damage dealt to this by each attacker: instance id -> total. Used for threat and kill credit.
var contributions := {}
var _stamina_cooldown := 0.0
var _poison_dps := 0.0
var _poison_left := 0.0
var _poison_tick := 0.0
var _poison_source: Node = null


func _ready() -> void:
	refill()
	if show_effects:
		StatsFx.attach(self)


func refill() -> void:
	last_source = null
	contributions.clear()
	health = max_health
	stamina = max_stamina
	mana = max_mana
	changed.emit()


## Regen and poison run on the fixed game tick (the same tick a server runs).
func _physics_process(delta: float) -> void:
	_poison_step(delta)
	var dirty := false
	if health > 0.0 and health < max_health:
		health = minf(health + health_regen * delta, max_health)
		dirty = true
	if _stamina_cooldown > 0.0:
		_stamina_cooldown -= delta
	elif stamina < max_stamina:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
		dirty = true
	if mana < max_mana:
		mana = minf(mana + (mana_regen + mana_regen_bonus) * delta, max_mana)
		dirty = true
	if dirty:
		changed.emit()


## Multiplier for spell damage dealt by whoever owns this.
func magic_mult() -> float:
	return 1.0 + (magic_damage_percent + attr_magic_percent) / 100.0


## Melee damage multiplier (Strength).
func melee_mult() -> float:
	return 1.0 + attr_melee_percent / 100.0


## Ranged (non-magic) damage multiplier (Dexterity). No player weapon uses it yet.
func ranged_mult() -> float:
	return 1.0 + attr_ranged_percent / 100.0


## `ignore_defense` is for self-inflicted costs (like chaining hops).
## `origin` is where a blockable attack came from (leave it out for ground effects,
## which can't be blocked or parried).
func take_damage(amount: float, source: Node = null, ignore_defense := false, origin := Vector2.INF) -> void:
	if health <= 0.0:
		return
	if origin != Vector2.INF and guard_filter.is_valid():
		amount = guard_filter.call(amount, source, origin)
		if amount <= 0.0:
			return
	# a player hitting a monster well above their level does less (AttackRules.level_gap_mult)
	if source != null and is_instance_valid(source) and source.is_in_group("player") and "level" in get_parent():
		var xp := source.get_node_or_null("Experience")
		if xp != null and "level" in xp:
			amount *= AttackRules.level_gap_mult(int(xp.level), int(get_parent().level))
	if not ignore_defense and defense_percent > 0.0:
		amount *= 1.0 - minf(defense_percent, 90.0) / 100.0
	if source != null:
		last_source = source
	if source != null:
		var id := source.get_instance_id()
		contributions[id] = float(contributions.get(id, 0.0)) + minf(amount, health)
	health = maxf(health - amount, 0.0)
	changed.emit()
	damaged.emit(amount)
	if health == 0.0:
		died.emit()


## Forget who has been hitting this (a monster that leashes home starts fresh).
func clear_contributions() -> void:
	contributions.clear()


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	changed.emit()


## Returns false (and spends nothing) if there isn't enough stamina.
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_cooldown = stamina_regen_delay
	changed.emit()
	return true


## Moves `amount` from one pool to another ("health", "stamina" or "mana").
## Fails (and changes nothing) if the target is already full or the source
## doesn't have enough. Transferring out of health can never kill you.
func transfer(from: String, to: String, amount: float) -> bool:
	var src: float = get(from)
	var dst: float = get(to)
	var dst_max: float = get("max_" + to)
	var floor_left := 1.0 if from == "health" else 0.0
	if dst >= dst_max or src - amount < floor_left:
		return false
	set(from, src - amount)
	set(to, minf(dst + amount, dst_max))
	if from == "stamina":
		_stamina_cooldown = stamina_regen_delay
	changed.emit()
	return true


## Returns false (and spends nothing) if there isn't enough mana.
func spend_mana(amount: float) -> bool:
	if mana < amount:
		return false
	mana -= amount
	changed.emit()
	return true


var _mana_warn_at := -10.0

## Says the owner just tried to spend mana it doesn't have (at most once a second).
## The red "OUT OF MANA" text is drawn by StatsFx listening to `out_of_mana`.
func warn_out_of_mana() -> void:
	var now := GameClock.now
	if now - _mana_warn_at < 1.0:
		return
	_mana_warn_at = now
	out_of_mana.emit()


## Poison: `dps` damage once a second for `seconds`. Hitting again refreshes the timer
## (it doesn't stack). Ticks ignore defense, and stop if the victim dies.
func apply_poison(dps: float, seconds: float, source: Node = null) -> void:
	if health <= 0.0:
		return
	if _poison_left <= 0.0:
		_poison_tick = 1.0
	_poison_dps = dps
	_poison_left = seconds
	_poison_source = source


func is_poisoned() -> bool:
	return _poison_left > 0.0


func _poison_step(delta: float) -> void:
	if _poison_left <= 0.0:
		return
	if health <= 0.0:
		_poison_left = 0.0
		return
	_poison_left -= delta
	_poison_tick -= delta
	while _poison_tick <= 0.0 and health > 0.0:
		_poison_tick += 1.0
		take_damage(_poison_dps, _poison_source if is_instance_valid(_poison_source) else null, true)
	if _poison_left <= 0.0 or health <= 0.0:
		_poison_left = 0.0
