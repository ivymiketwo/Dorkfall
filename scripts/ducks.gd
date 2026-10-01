extends Node2D
## Ducks paddling on the two ponds. They pick a spot of open water, swim there,
## rest, sometimes dabble (tail up), and leave a little ripple behind. They
## read the pond's water map so they never leave the water.

const PONDS := [
	{"tex": "res://art/water_info_1.png", "pos": Vector2(449, 79.5), "ducks": 3},
	{"tex": "res://art/water_info_2.png", "pos": Vector2(879.5, 671), "ducks": 4},
]
const MIN_DEPTH := 7            ## water-map value needed (distance from the bank)
const SPEED := 9.0

const SWIM := [
	".....GG...",
	"....GEGG..",
	"....GGGGOO",
	".BBBBWWW..",
	"TBBBBBBB..",
	".BBBBBBB..",
	"..LLLLLL..",
]
const DABBLE := [
	".T........",
	"TBBB......",
	".BBBBBWW..",
	".BBBBBBB..",
	"..LLLLLL..",
]
const COL := {
	"G": Color("2e7d57"), "E": Color("14121c"), "O": Color("f0b030"), "W": Color("f4efe4"),
	"B": Color("8a6a4a"), "T": Color("3a3a48"), "L": Color("b8a080"),
}

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
				"ripples": [], "rip_t": 0.0,
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
		match d["state"]:
			"idle", "dabble":
				d["wait"] -= delta
				if d["wait"] <= 0.0:
					var tgt: Vector2 = _random_water(d["pond"], rng)
					# stay on this duck's side: only go to spots not too far
					if tgt != Vector2.INF and tgt.distance_to(d["pos"]) < 90.0 and _clear_path(d["pond"], d["pos"], tgt):
						d["target"] = tgt
						d["state"] = "swim"
					else:
						d["wait"] = rng.randf_range(0.5, 2.0)
			"swim":
				var to: Vector2 = d["target"] - d["pos"]
				if to.length() < 1.5:
					d["state"] = "dabble" if rng.randf() < 0.35 else "idle"
					d["wait"] = rng.randf_range(1.5, 5.0)
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
						d["ripples"].append({"p": d["pos"] + Vector2(-5.0 * d["dir"], 3), "age": 0.0})
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


func _draw() -> void:
	var order := _ducks.duplicate()
	order.sort_custom(func(a, b): return a["pos"].y < b["pos"].y)
	for d in order:
		for r in d["ripples"]:
			var k: float = r["age"] / 1.4
			var rw := 3.0 + k * 7.0
			var col := Color(1, 1, 1, 0.45 * (1.0 - k))
			var c: Vector2 = r["p"]
			draw_rect(Rect2(c.x - rw, c.y, rw * 2.0, 1), col)
		var pat: Array = DABBLE if d["state"] == "dabble" else SWIM
		var bob: float = roundf(sin(_t * 2.2 + d["phase"]) * 0.6)
		var dir: float = d["dir"]
		var base: Vector2 = (d["pos"] + Vector2(0, bob)).round() - Vector2(5, 5)
		# a dark water shadow and the waterline ripple under the body
		draw_rect(Rect2(base.x + (1 if dir > 0 else 0), base.y + pat.size(), 9, 1), Color(0.1, 0.25, 0.4, 0.35))
		for j in pat.size():
			var row: String = pat[j]
			for i in row.length():
				var ch: String = row[i]
				if ch == ".":
					continue
				var x: int = i if dir > 0 else row.length() - 1 - i
				draw_rect(Rect2(base.x + x, base.y + j, 1, 1), COL[ch])
