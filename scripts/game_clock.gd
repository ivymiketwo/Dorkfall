extends Node
## The game's own clock (autoload "GameClock"). It only moves in fixed physics ticks, never
## with the frame rate, so a server and every client count time the same way.
##
## Cooldowns are stored as "ready at" times on this clock instead of numbers that count down
## every frame:   ready_at = GameClock.now + 3.0   ...   if GameClock.passed(ready_at): ...
## A "ready at" time is plain data, so it can be saved or sent over the network as it is.

## Physics ticks since the game started.
var tick := 0
## Seconds since the game started, in whole ticks.
var now := 0.0


func _physics_process(delta: float) -> void:
	tick += 1
	now += delta


## True once the clock has reached `ready_at`.
func passed(ready_at: float) -> bool:
	return now >= ready_at


## Seconds left until `ready_at` (0 when it has passed).
func left(ready_at: float) -> float:
	return maxf(ready_at - now, 0.0)
