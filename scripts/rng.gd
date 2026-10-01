class_name Rng
extends RefCounted
## The random numbers that decide game rules (drops, which spell a monster casts).
## Everything that matters goes through here so a server can own it (and tests can seed it).
## Purely visual randomness (particles, wobble) keeps using plain randf().

static var _rng := _make()


static func _make() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func seed_with(value: int) -> void:
	_rng.seed = value


static func randf() -> float:
	return _rng.randf()


static func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


static func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


## True with probability `p`.
static func chance(p: float) -> bool:
	return _rng.randf() < p
