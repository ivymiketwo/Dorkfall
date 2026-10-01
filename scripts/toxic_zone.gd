class_name ToxicZone
extends Node2D
## Boss ground attack: a rising-sun pattern (disc + rays) is painted on the ground.
## It starts yellow and slowly turns red; when it's fully red the ground splits
## open along the rays and jets of compressed toxic gas blast out of the cracks,
## hurting anything standing in the red area.

@export var damage := 250.0
@export var warn_time := 1.0
@export var disc_radius := 55.0
@export var ray_radius := 130.0
@export var ray_count := 16          # number of red rays (with a gap between each)
@export var smoke_time := 1.8

const YELLOW := Color(1.0, 0.88, 0.15, 0.40)
const RED := Color(0.95, 0.08, 0.08, 0.60)

var _t := 0.0
var _burst := false
var _cracks: Array = []     # [{pts: PackedVector2Array}]
var _vents: Array = []      # [{p, d, str}]   d = delay, str = strength
var _gas: Array = []        # thrown gas puffs
var _smoke: Node2D


func _ready() -> void:
	# Gas lives on its own node so it draws above characters.
	_smoke = Node2D.new()
	_smoke.z_index = 5
	_smoke.draw.connect(_draw_smoke)
	add_child(_smoke)


func _process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	_t += delta
	if not _burst and _t >= warn_time:
		_detonate()
	if _burst and _t >= warn_time + smoke_time:
		queue_free()
		return
	queue_redraw()
	_smoke.queue_redraw()


func covers(p: Vector2) -> bool:
	## p is in this node's local space.
	return AttackRules.toxic_covers(p, disc_radius, ray_radius, ray_count)


func _detonate() -> void:
	_burst = true
	# Damage everyone standing in the red area.
	for player in Players.all(get_tree()):
		if covers(to_local(player.global_position)):
			AttackRules.deal(player, damage)
	_make_cracks()
	_make_gas()


## Jagged fissures: one down the middle of every ray, plus a few across the disc.
func _make_cracks() -> void:
	var seg := TAU / float(ray_count * 2)
	for i in ray_count + 5:
		var on_disc := i >= ray_count
		var ang := float(i * 2) * seg if not on_disc else float(i - ray_count) * TAU / 5.0 + randf_range(-0.3, 0.3)
		var dir := Vector2.from_angle(ang)
		var perp := dir.orthogonal()
		var r := 4.0 if on_disc else disc_radius * 0.7
		var end := disc_radius * 0.95 if on_disc else ray_radius * randf_range(0.85, 0.99)
		var off := 0.0
		var pts := PackedVector2Array()
		while r < end:
			var lim := 3.0 if on_disc else maxf(r * 0.07, 1.0)
			off = clampf(off + randf_range(-3.5, 3.5), -lim, lim)
			pts.append(dir * r + perp * off)
			r += randf_range(6.0, 12.0)
		if pts.size() < 2:
			continue
		_cracks.append({"pts": pts})
		for j in 3 if not on_disc else 1:
			_vents.append({"p": pts[randi() % pts.size()], "d": randf_range(0.0, 0.35),
					"str": randf_range(0.6, 1.0)})


## Each vent throws jets of gas up and a low fog out along the ground.
func _make_gas() -> void:
	for v in _vents:
		for k in 7:
			_gas.append({"p": v["p"], "d": v["d"] + randf_range(0.0, 0.14),
					"v": Vector2.from_angle(-PI * 0.5 + randf_range(-0.85, 0.85)) * randf_range(70.0, 150.0) * v["str"],
					"drag": randf_range(2.6, 4.0), "r": randf_range(3.0, 6.0),
					"grow": randf_range(9.0, 16.0), "life": randf_range(0.7, 1.3)})
		for k in 3:
			_gas.append({"p": v["p"], "d": v["d"] + randf_range(0.05, 0.3),
					"v": Vector2.from_angle(randf() * TAU) * Vector2(1.0, 0.55) * randf_range(25.0, 55.0),
					"drag": randf_range(1.8, 2.6), "r": randf_range(5.0, 8.0),
					"grow": randf_range(8.0, 12.0), "life": randf_range(1.0, 1.6)})


func _draw() -> void:
	var k := clampf(_t / warn_time, 0.0, 1.0)
	var col := YELLOW.lerp(RED, k)
	var b := _t - warn_time
	if not _burst:
		# The warning marker: rays + sun disc. It's gone the instant the attack goes off.
		var seg := TAU / float(ray_count * 2)
		for i in ray_count:
			var a0 := (float(i * 2) - 0.5) * seg
			var pts := PackedVector2Array([Vector2.ZERO])
			for s in 7:
				pts.append(Vector2.from_angle(a0 + seg * float(s) / 6.0) * ray_radius)
			draw_colored_polygon(pts, col)
		draw_circle(Vector2.ZERO, disc_radius, col)
		return
	# The ground splitting open: dark fissures with green light leaking out.
	var open := clampf(b / 0.14, 0.0, 1.0)
	var glow_fade := clampf(1.0 - (b - 0.5) / (smoke_time - 0.5), 0.0, 1.0)
	var dark_fade := clampf(1.0 - (b - 0.9) / (smoke_time - 0.9), 0.0, 1.0)
	for c in _cracks:
		var pts: PackedVector2Array = c["pts"]
		var n := maxi(int(ceil(pts.size() * open)), 2)
		var shown := pts.slice(0, mini(n, pts.size()))
		draw_polyline(shown, Color(0.06, 0.09, 0.04, 0.9 * dark_fade), 4.0)
		draw_polyline(shown, Color(0.35, 0.75, 0.15, 0.55 * glow_fade), 2.4)
		draw_polyline(shown, Color(0.85, 1.0, 0.5, (0.6 + 0.3 * sin(b * 30.0)) * glow_fade), 1.0)


func _draw_smoke() -> void:
	if not _burst:
		return
	var st := _t - warn_time
	# a bright pop and a hissing column at each vent as the pressure lets go
	for v in _vents:
		var t: float = st - v["d"]
		if t < 0.0 or t > 0.6:
			continue
		var s: float = v["str"]
		if t < 0.1:
			_smoke.draw_circle(v["p"], 6.0 * s * (1.0 - t / 0.1) + 2.0, Color(0.95, 1.0, 0.75, 0.85))
		var h: float = 38.0 * s * (1.0 - exp(-t * 11.0))
		var a := 1.0 - t / 0.6
		var base: Vector2 = v["p"]
		var w0 := 4.0 * s
		var poly := PackedVector2Array([base + Vector2(-w0, 0), base + Vector2(-w0 * 0.35, -h), base + Vector2(w0 * 0.35, -h), base + Vector2(w0, 0)])
		_smoke.draw_colored_polygon(poly, Color(0.35, 0.8, 0.2, 0.55 * a))
		var w1 := w0 * 0.5
		var poly2 := PackedVector2Array([base + Vector2(-w1, 0), base + Vector2(-w1 * 0.3, -h * 0.9), base + Vector2(w1 * 0.3, -h * 0.9), base + Vector2(w1, 0)])
		_smoke.draw_colored_polygon(poly2, Color(0.9, 1.0, 0.65, 0.85 * a))
	# gas puffs: shoot out fast, slow down as they billow and thin out
	for g in _gas:
		var t: float = st - g["d"]
		if t < 0.0 or t > g["life"]:
			continue
		var u: float = t / g["life"]
		var vel: Vector2 = g["v"]
		var drag: float = g["drag"]
		var pos: Vector2 = g["p"] + vel * ((1.0 - exp(-drag * t)) / drag)
		pos.y -= t * 6.0   # heat/pressure keeps lifting it a little
		var r: float = g["r"] + g["grow"] * (1.0 - exp(-2.2 * t))
		var a: float = pow(1.0 - u, 1.3) * 0.72
		var young := Color(0.62, 0.95, 0.32)
		var old := Color(0.18, 0.5, 0.14)
		var c := young.lerp(old, clampf(u * 1.4, 0.0, 1.0))
		_smoke.draw_circle(pos, r, Color(c.r * 0.6, c.g * 0.7, c.b * 0.6, a * 0.55))
		_smoke.draw_circle(pos, r * 0.78, Color(c.r, c.g, c.b, a))
		_smoke.draw_circle(pos + Vector2(-r * 0.2, -r * 0.25), r * 0.4, Color(0.85, 1.0, 0.6, a * 0.55 * (1.0 - u)))

## Called if whoever cast this dies: gone instantly, no damage.
func _cancel() -> void:
	set_process(false)
	hide()
	queue_free()
