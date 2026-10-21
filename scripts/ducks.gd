extends Node2D
## Ducks paddling on the two ponds. They pick a spot of open water, swim there and float
## about: resting (blinking now and then), dabbling (tail up), preening, quacking, stretching
## their wings or napping, and leave a little ripple behind. They read the pond's water map so
## they never leave the water. Only drawing: nothing here touches game rules.

const PONDS := [
	{"tex": "res://art/water_info_1.png", "pos": Vector2(625, 79.5), "ducks": 3},
	{"tex": "res://art/water_info_2.png", "pos": Vector2(879.5, 671), "ducks": 4},
]
const MIN_DEPTH := 7            ## water-map value needed (distance from the bank)
const SPEED := 9.0

## Rex's duck pictures, packed by tools/pack_ducks.py from art/duck_src/ (32x32 art px each,
## drawn at half size like all art: 1 art px = 0.5 world px). Frame order as in that tool.
const SHEET := preload("res://art/ducks.png")
const F := {"float": 0, "blink": 1, "quack": 2, "preen_back": 3, "preen_breast": 4, "sleep": 5,
		"dip": 6, "dip_deep": 7, "tail_up": 8, "flap_half": 9, "flap_up": 10}
const FRAME := 32
## The duck's position is the middle of its waterline, which is this row of the picture.
const WATERLINE := 27
## What a resting duck may get up to: [name, chance weight, min seconds, max seconds].
const ACTS := [["rest", 5.0, 1.5, 5.0], ["dabble", 2.5, 2.2, 3.4], ["preen", 1.5, 2.0, 4.0],
		["quack", 1.2, 0.9, 1.3], ["flap", 0.8, 0.9, 1.1], ["sleep", 0.8, 5.0, 10.0]]

var _imgs: Array = []
var _ducks: Array = []
var _t := 0.0


func _ready() -> void:
	z_index = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in PONDS.size():
		var tex: Texture2D = load(PONDS[i]["tex"])
		_imgs.append(tex.get_image())
		for n in PONDS[i]["ducks"]:
			var p := _random_water(i, rng)
			if p == Vector2.INF:
				continue
			_ducks.append({
				"pond": i, "pos": p, "target": p, "dir": 1.0 if rng.randf() < 0.5 else -1.0,
				"state": "idle", "wait": rng.randf_range(0.5, 4.0), "phase": rng.randf() * 6.0,
				"ripples": [], "rip_t": 0.0, "act": "rest", "act_t": 0.0,
			})


func _water_at(pond: int, p: Vector2) -> int:
	var img: Image = _imgs[pond]
	var q: Vector2 = ((p - PONDS[pond]["pos"]) * 2.0).floor()
	if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
		return 0
	return int(img.get_pixel(int(q.x), int(q.y)).r * 255.0)


func _random_water(pond: int, rng: RandomNumberGenerator) -> Vector2:
	var img: Image = _imgs[pond]
	var size := Vector2(img.get_width(), img.get_height()) / 2.0
	for i in 60:
		var p: Vector2 = PONDS[pond]["pos"] + Vector2(rng.randf() * size.x, rng.randf() * size.y)
		if _water_at(pond, p) >= MIN_DEPTH + 3:
			return p
	return Vector2.INF


func _process(delta: float) -> void:
	_t += delta
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for d in _ducks:
		d["act_t"] += delta
		match d["state"]:
			"idle":
				d["wait"] -= delta
				if d["wait"] <= 0.0:
					var tgt: Vector2 = _random_water(d["pond"], rng)
					# stay on this duck's side: only go to spots not too far
					if rng.randf() < 0.6 and tgt != Vector2.INF and tgt.distance_to(d["pos"]) < 90.0 and _clear_path(d["pond"], d["pos"], tgt):
						d["target"] = tgt
						d["state"] = "swim"
						d["act"] = "rest"
					else:
						_pick_act(d, rng)
			"swim":
				var to: Vector2 = d["target"] - d["pos"]
				if to.length() < 1.5:
					d["state"] = "idle"
					_pick_act(d, rng)
				else:
					var step: Vector2 = to.normalized() * SPEED * delta
					var np: Vector2 = d["pos"] + step
					if _water_at(d["pond"], np) >= MIN_DEPTH:
						d["pos"] = np
						if absf(to.x) > 1.0:
							d["dir"] = signf(to.x)
					else:
						d["state"] = "idle"
						d["wait"] = 0.5
					d["rip_t"] -= delta
					if d["rip_t"] <= 0.0:
						d["rip_t"] = 0.45
						d["ripples"].append({"p": d["pos"] + Vector2(-6.0 * d["dir"], 0), "age": 0.0})
		for r in d["ripples"]:
			r["age"] += delta
		d["ripples"] = d["ripples"].filter(func(r): return r["age"] < 1.4)
	queue_redraw()


## True if the straight line between two points stays in deep-enough water.
func _clear_path(pond: int, a: Vector2, b: Vector2) -> bool:
	for i in range(1, 9):
		if _water_at(pond, a.lerp(b, i / 8.0)) < MIN_DEPTH:
			return false
	return true


## Starts something to do while floating in place (see ACTS), for a random while.
func _pick_act(d: Dictionary, rng: RandomNumberGenerator) -> void:
	var total := 0.0
	for a: Array in ACTS:
		total += a[1]
	var r := rng.randf() * total
	for a: Array in ACTS:
		r -= a[1]
		if r <= 0.0:
			d["act"] = a[0]
			d["wait"] = rng.randf_range(a[2], a[3])
			break
	d["act_t"] = 0.0
	if d["act"] == "flap" or d["act"] == "dabble":       # a little splash
		for k in 2:
			d["ripples"].append({"p": d["pos"] + Vector2((k * 2 - 1) * 4.0, 0), "age": -0.1 * k})


## Which picture a duck shows right now.
func _frame(d: Dictionary) -> int:
	var t: float = d["act_t"]
	var total: float = t + maxf(d["wait"], 0.0)        # how long this act lasts in all
	match d["act"]:
		"dabble":
			# dip in, tail up for a while (with a wiggle), and back up
			var out := total - t
			if t < 0.15 or out < 0.15:
				return F["dip"]
			if t < 0.3 or out < 0.3:
				return F["dip_deep"]
			return F["tail_up"] if fmod(t, 0.9) < 0.75 else F["dip_deep"]
		"preen":
			return F["preen_back"] if fmod(t, 1.6) < 1.0 else F["preen_breast"]
		"quack":
			# two quacks
			return F["quack"] if (t < 0.25 or (t > 0.45 and t < 0.7)) else F["float"]
		"flap":
			if t < 0.08 or total - t < 0.1:
				return F["flap_half"]
			return F["flap_up"] if fmod(t, 0.24) < 0.12 else F["flap_half"]
		"sleep":
			return F["sleep"]
	# floating or swimming: blink now and then
	return F["blink"] if fmod(_t + d["phase"] * 3.0, 3.7) < 0.14 else F["float"]


func _draw() -> void:
	var order := _ducks.duplicate()
	order.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	for d in order:
		for r in d["ripples"]:
			if r["age"] < 0.0:
				continue
			var k: float = r["age"] / 1.4
			var rw := 3.0 + k * 7.0
			var col := Color(1, 1, 1, 0.45 * (1.0 - k))
			var c: Vector2 = r["p"]
			draw_rect(Rect2(c.x - rw, c.y, rw * 2.0, 0.5), col)
		var asleep: bool = d["act"] == "sleep"
		var bob: float = sin(_t * (1.2 if asleep else 2.2) + d["phase"]) * 0.5
		var dir: float = d["dir"]
		var at: Vector2 = ((d["pos"] + Vector2(0, bob)) * 2.0).round() / 2.0     # on whole art pixels
		# a dark water shadow just under the waterline
		draw_rect(Rect2(at.x - 6.0, at.y, 12.0, 1.0), Color(0.1, 0.25, 0.4, 0.3))
		var src := Rect2(_frame(d) * FRAME, 0, FRAME, FRAME)
		draw_set_transform(at, 0.0, Vector2(0.5 * dir, 0.5))
		draw_texture_rect_region(SHEET, Rect2(-FRAME / 2.0, -WATERLINE, FRAME, FRAME), src)
		draw_set_transform(Vector2.ZERO)
		# a thin bright line where the body meets the water
		draw_rect(Rect2(at.x - 6.5, at.y, 13.0, 0.5), Color(1, 1, 1, 0.28))
