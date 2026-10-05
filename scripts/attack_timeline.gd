class_name AttackTimeline
extends RefCounted
## WHEN things happen in a telegraphed attack, with no drawing in it. An attack lists its
## moments once ("at 0.7 s the lunge lands", "from 0.9 s to 1.06 s the knife is flying")
## and then ticks the timeline from _physics_process, the fixed game tick a server runs too.
## The hit tests themselves are in AttackRules. Drawing only reads `t`.
##
##   _timeline = AttackTimeline.new().at(warn_time, _strike).lasts(warn_time + 0.2)
##   func _physics_process(delta):  if _timeline.tick(delta): queue_free()

## Seconds since the attack started.
var t := 0.0
## When the attack is over (it frees itself then).
var end_time := 0.0
var _events: Array[Dictionary] = []


## Runs `action` once, on the first tick at or after `time`.
func at(time: float, action: Callable) -> AttackTimeline:
	_events.append({"from": time, "to": time, "fn": action, "done": false})
	end_time = maxf(end_time, time)
	return self


## Runs `action` every tick from `from` until `to` (for things that sweep or fly).
## `action` gets how far through the window it is (0..1).
func during(from: float, to: float, action: Callable) -> AttackTimeline:
	_events.append({"from": from, "to": to, "fn": action, "done": false})
	end_time = maxf(end_time, to)
	return self


## Keeps the attack around until at least `time` (for the fade-out after the last hit).
func lasts(time: float) -> AttackTimeline:
	end_time = maxf(end_time, time)
	return self


## Advances the clock and fires what is due. Returns true once the attack is over.
func tick(delta: float) -> bool:
	t += delta
	for e in _events:
		if e["done"] or t < e["from"]:
			continue
		if e["to"] <= e["from"]:
			e["done"] = true
			e["fn"].call()
		elif t < e["to"]:
			e["fn"].call((t - e["from"]) / (e["to"] - e["from"]))
		else:
			e["done"] = true
			e["fn"].call(1.0)       # last call at the very end of the window
	return t >= end_time
