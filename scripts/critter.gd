class_name Critter
extends Sprite2D
## Plays a looping sequence of sprite-sheet frames: `frames[i]` is shown for
## `durations[i]` seconds. Used for the caged dragons, the wobbling egg and the
## sleeping dragon in the pet shop. Set the sheet's hframes in the Inspector.

@export var frames := PackedInt32Array([0, 1])
@export var durations := PackedFloat32Array([1.0, 0.3])
@export var random_start := true       # so neighbouring critters don't move in lockstep
@export var speed_jitter := 0.2        # +/- this much random speed difference per critter

var _i := 0
var _t := 0.0
var _speed := 1.0


func _ready() -> void:
	_speed = 1.0 + randf_range(-speed_jitter, speed_jitter)
	if frames.is_empty() or durations.size() < frames.size():
		set_process(false)
		return
	if random_start:
		_i = randi() % frames.size()
		_t = randf() * durations[_i]
	frame = frames[_i]


func _process(delta: float) -> void:
	_t += delta * _speed
	while _t >= durations[_i]:
		_t -= durations[_i]
		_i = (_i + 1) % frames.size()
		frame = frames[_i]
