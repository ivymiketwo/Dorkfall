class_name StoneWalls
extends Node2D
## Stripes of spiky stone walls. Every stripe is marked on the ground first; then
## the walls burst out of the floor in a fast wave sweeping from right to left.
## Each stretch of marker vanishes the instant its spikes erupt and hurts anyone
## standing in it. The spikes stay a moment, then crumble away.

@export var warn_time := 1.3
@export var wave_speed := 650.0      ## units per second, right to left
@export var damage := 100.0
@export var hold_time := 0.9         ## how long the spikes stand
const RISE := 0.14
const SINK := 0.35

var cells: Array[Rect2] = []          ## global rectangles, one per stretch of stripe
## When each stretch erupts (seconds). Worked out by the caster through Rng (the rules); if
## left empty they are worked out here.
var trigger_times: Array[float] = []
var caster: Node
var _t := 0.0
var _trigger: Array[float] = []
var _spikes: Array = []               ## per cell: Array of [x_off, height, half_width]
var _done: Array[bool] = []
var _x_max := -INF
var _end := 0.0
var _fx: Node2D
var _timeline: AttackTimeline   ## when each stretch erupts (rules); drawing reads _t


func _ready() -> void:
	_fx = Node2D.new()
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	var rng := RandomNumberGenerator.new()   # only for the spike shapes (looks)
	rng.randomize()
	for c in cells:
		_x_max = maxf(_x_max, c.end.x)
	_timeline = AttackTimeline.new()
	for c in cells:
		var i := _trigger.size()
		_trigger.append(trigger_times[i] if i < trigger_times.size() else warn_time + (_x_max - c.get_center().x) / wave_speed + Rng.randf() * 0.04)
		_timeline.at(_trigger[i], _erupt.bind(i))
		_done.append(false)
		var sp := []
		var w := c.size.x
		var n := maxi(3, int(round(w / 6.0)))          # a chunk is a few cells wide: spikes are spread across it
		for k in n:
			var mid := 1.0 - absf(float(k) - float(n - 1) * 0.5) / (float(n) * 0.5)   # taller in the middle
			sp.append([w * (float(k) + 0.5) / float(n) + rng.randf_range(-1.0, 1.0), rng.randf_range(12.0, 20.0) + 10.0 * mid, rng.randf_range(2.8, 4.0)])
		_spikes.append(sp)
		_end = maxf(_end, _trigger[-1] + hold_time + SINK)
	_timeline.lasts(_end)


func _physics_process(delta: float) -> void:
	if AttackGuard.owner_dead(self):
		_cancel()
		return
	var over := _timeline.tick(delta)
	_t = _timeline.t
	if over:
		queue_free()


func _process(_delta: float) -> void:
	queue_redraw()
	_fx.queue_redraw()


func _erupt(i: int) -> void:
	_done[i] = true
	_hit(cells[i])


func _hit(c: Rect2) -> void:
	for player in Players.all(get_tree()):
		if AttackRules.rect_hits(c, player.global_position + AttackRules.CHEST, 2.0):
			AttackRules.deal(player, damage)


func _draw() -> void:
	var k := clampf(_t / warn_time, 0.0, 1.0)
	for i in cells.size():
		if _done[i]:
			continue
		var r := Rect2(to_local(cells[i].position), cells[i].size)
		draw_rect(r, Color(1.0, 0.85, 0.2, 0.14 + 0.12 * k))
		draw_rect(r, Color(0.95, 0.12, 0.1, 0.20 + 0.30 * k))
	# thin outline along the top and bottom edge of each stripe run
	for i in cells.size():
		if _done[i]:
			continue
		var r := Rect2(to_local(cells[i].position), cells[i].size)
		draw_line(r.position, r.position + Vector2(r.size.x, 0), Color(0.95, 0.2, 0.15, 0.7), 1.0)
		draw_line(r.position + Vector2(0, r.size.y), r.end, Color(0.95, 0.2, 0.15, 0.7), 1.0)


func _draw_fx() -> void:
	for i in cells.size():
		if not _done[i]:
			continue
		var age := _t - _trigger[i]
		var grow := 1.0
		if age < RISE:
			grow = 1.0 - pow(1.0 - age / RISE, 2.0)
		var sink := 0.0
		if age > hold_time:
			sink = clampf((age - hold_time) / SINK, 0.0, 1.0)
		var f := grow * (1.0 - sink)
		if f <= 0.01:
			continue
		var c := cells[i]
		var base_y := c.end.y - 2.0
		var dust_a := clampf(1.0 - age / 0.4, 0.0, 1.0)
		if dust_a > 0.0:
			_fx.draw_rect(Rect2(to_local(Vector2(c.position.x, base_y - 2.0)), Vector2(c.size.x, 3.0)), Color(0.72, 0.68, 0.6, dust_a * 0.6))
		for sp in _spikes[i]:
			var bx: float = c.position.x + sp[0]
			var h: float = float(sp[1]) * f
			var hw: float = float(sp[2])
			var b := to_local(Vector2(bx, base_y))
			var tip := b + Vector2(0, -h)
			_tri(Vector2(b.x - hw, b.y), tip, b, Color(0.62, 0.6, 0.68))
			_tri(b, tip, Vector2(b.x + hw, b.y), Color(0.36, 0.34, 0.42))


## One flat triangle without the polygon triangulation work.
func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_fx.draw_primitive(PackedVector2Array([a, b, c]), PackedColorArray([col, col, col]), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))


## Called if the caster dies: everything vanishes, no damage.
func _cancel() -> void:
	set_process(false)
	set_physics_process(false)
	hide()
	queue_free()
