class_name ClockworkSpider
extends Node2D
## The Clockwork Staff's attack:
##   1. a brown and orange ray shoots from the staff's orb to the mouse (up to `max_range`),
##   2. an orange summoning circle opens on the ground there, with a glowing orange half-dome in
##      its middle,
##   3. the dome sinks away and Rex's little clockwork spider is standing behind it,
##   4. the spider locks onto the nearest monster and skitters at it, blinking red faster and
##      faster the closer it gets, and explodes when it reaches it: everything within
##      `blast_radius` takes `damage`. With no monster about it waits by the circle, ticking,
##      and goes off by itself after `fuse_time`.
##
## Made by BasicAttack from the Clockwork Staff's ability (abilities/clockwork_spider.tres, which
## points at scenes/spells/clockwork_spider.tscn). Timings and sizes are in that scene's Inspector;
## the ability holds the damage, mana and cooldown. The rules (where it lands, where the spider
## runs, when and where it blows up and who it hits) run on the game tick through AttackTimeline
## and _physics_process; the rest is only drawing. Sizes are world px (1 world px = 2 art px).
## Art: art/clockwork_spider.png (tools/pack_spider.py), art/explosion.png (tools/pack_explosion.py).

@export_group("Ray and circle")
## How far the ray reaches at most (world px), and how long it shows.
@export var max_range := 140.0
@export var ray_time := 0.25
## The summoning circle's radius.
@export var circle_radius := 13.0

@export_group("Dome")
## The half-dome's radius, when it has finished rising, when it starts to sink and how long that takes.
@export var dome_radius := 12.0
@export var dome_up_at := 0.55
@export var dome_down_at := 0.85
@export var dome_down_time := 0.3

@export_group("Spider")
## World px per second, walk frames per second (high = skittering legs).
@export var speed := 85.0
@export var walk_fps := 26.0
## Only goes for monsters this close to it (world px).
@export var seek_range := 220.0
## Blows up when it gets this close to its target.
@export var reach := 9.0
## Goes off by itself this long after it appears, whatever happens.
@export var fuse_time := 7.0
## Red blinks per second: when it first locks on, and right next to its target.
@export var blink_far := 2.5
@export var blink_near := 16.0

@export_group("Explosion")
@export var blast_radius := 24.0
## The explosion picture's size: 0.5 = normal art pixels (64 art px = 32 world px across).
@export var blast_scale := 0.5
@export var blast_fps := 18.0

## Set by whoever casts it, before adding it to the world.
var caster: Node2D
var damage := 70.0

const SPIDER_TEX := preload("res://art/clockwork_spider.png")
const BLAST_TEX := preload("res://art/explosion.png")
const SFW := 56
const SFH := 52
const SFEET := 48
const BLAST_FRAMES := 9
const RAY_EDGE := Color8(112, 62, 28)
const RAY_CORE := Color8(244, 150, 56)
const DOME_DARK := Color8(196, 96, 30)
const DOME := Color8(240, 146, 52)
const DOME_LIGHT := Color8(255, 210, 130)
const ORANGE_CIRCLE := [Color(0.85, 0.42, 0.1), Color(1.0, 0.7, 0.35), Color(0.95, 0.55, 0.2),
		Color(1.0, 0.8, 0.5), Color(1.0, 0.86, 0.62), Color(1.0, 0.75, 0.4)]
const CAST_SOUND := preload("res://audio/ray_swoosh.wav")
const BOOM_SOUND := preload("res://audio/fireball_hit.wav")

var _timeline: AttackTimeline
var _from := Vector2.ZERO          # the staff's orb (global)
var _at := Vector2.ZERO            # where the circle opens (global); this node stays there
var _circle: Node2D                # drawn on the ground, under everyone
var _ray: Node2D                   # drawn above everyone (the ray, then the explosion)
var _dome_node: Node2D             # the dome, sorted with everyone at the circle's middle
var _spider: Node2D                # the spider (its own node so it sorts with everyone as it runs)
var _sprite: Sprite2D
var _spider_at := 0.0              # timeline time it appeared (0 = not yet)
var _target: Node2D
var _lock_dist := 0.0              # how far the target was when it locked on
var _facing := 0
var _anim := 0.0
var _blast_t := -1.0               # seconds since it blew up (-1 = not yet)
var _blast_pos := Vector2.ZERO


func _ready() -> void:
	y_sort_enabled = true
	_from = HeldWeapon.beam_origin(caster) if caster else global_position
	var aim: Vector2 = caster.aim_world - _from if caster else Vector2.RIGHT * max_range
	if aim.length() > max_range:
		aim = aim.normalized() * max_range
	_at = _from + aim
	_face_caster(aim)
	global_position = _at
	_ray = Node2D.new()
	_ray.z_index = 4
	_ray.draw.connect(_draw_ray)
	add_child(_ray)
	_dome_node = Node2D.new()
	_dome_node.draw.connect(_draw_dome)
	add_child(_dome_node)
	_circle = Node2D.new()
	_circle.draw.connect(_draw_circle)
	var root := get_parent().get_parent() if get_parent() else null
	var ground := root.get_node_or_null("GroundArt") if root else null
	if ground:
		root.add_child(_circle)
		root.move_child(_circle, ground.get_index() + 1)      # on the ground, under everyone
	else:
		add_child(_circle)
	_circle.global_position = _at
	_timeline = AttackTimeline.new().lasts(1.0e9)            # ends when the explosion is over
	_timeline.at(dome_down_at, _spawn_spider)
	_sound(CAST_SOUND, _from, 0.8, -2.0)


func _exit_tree() -> void:
	if _circle != null and is_instance_valid(_circle) and _circle.get_parent() != self:
		_circle.queue_free()


func _face_caster(v: Vector2) -> void:
	if caster != null and "facing" in caster and v.length() > 1.0:
		caster.facing = (3 if v.x > 0 else 2) if absf(v.x) > absf(v.y) else (0 if v.y > 0 else 1)


# --- rules (game tick) ---

func _physics_process(delta: float) -> void:
	_timeline.tick(delta)
	if _blast_t >= 0.0:
		_blast_t += delta
		if _blast_t > BLAST_FRAMES / blast_fps + 0.1:
			queue_free()
		return
	if _spider == null:
		return
	var age := _timeline.t - _spider_at
	if age >= fuse_time:
		_explode()
		return
	if age < dome_down_time:
		return                                     # still waiting behind the sinking dome
	if _target == null or not _alive(_target):
		_target = _nearest_monster()
		if _target:
			_lock_dist = maxf(_spider.global_position.distance_to(_target.global_position), reach + 1.0)
	if _target == null:
		_anim = 0.0
		return
	var to := _target.global_position - _spider.global_position
	if to.length() <= reach:
		_explode()
		return
	var step := to.normalized() * minf(speed * delta, to.length())
	_spider.global_position += step
	_facing = (3 if to.x > 0 else 2) if absf(to.x) > absf(to.y) else (0 if to.y > 0 else 1)
	_anim += delta


func _spawn_spider() -> void:
	_spider = Node2D.new()
	_spider.name = "Spider"
	_sprite = Sprite2D.new()
	_sprite.texture = SPIDER_TEX
	_sprite.hframes = 8
	_sprite.vframes = 5
	_sprite.centered = false
	_sprite.offset = Vector2(-SFW / 2.0, -SFEET)
	_sprite.scale = Vector2(0.5, 0.5)
	_spider.add_child(_sprite)
	_spider.draw.connect(_draw_spider_shadow)
	add_child(_spider)
	_spider.global_position = _at + Vector2(0, -2)    # just behind the dome's middle
	_spider_at = _timeline.t
	_facing = 0
	_show_spider()


func _alive(n: Node2D) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var st := n.get_node_or_null("Stats") as Stats
	return st != null and st.health > 0.0


func _nearest_monster() -> Node2D:
	var best: Node2D = null
	var best_d := seek_range
	for m in get_tree().get_nodes_in_group("monsters"):
		var n := m as Node2D
		if n == null or not _alive(n):
			continue
		var d := n.global_position.distance_to(_spider.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _explode() -> void:
	_blast_pos = _spider.global_position
	_blast_t = 0.0
	_spider.queue_free()
	_spider = null
	_sound(BOOM_SOUND, _blast_pos, 1.0, 0.0)
	if caster == null or not is_instance_valid(caster):
		return
	var stats := caster.get_node_or_null("Stats") as Stats
	var amount := damage * (stats.magic_mult() if stats else 1.0)
	var shape := CircleShape2D.new()
	shape.radius = blast_radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, _blast_pos)
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var seen := {}
	for hit in get_world_2d().direct_space_state.intersect_shape(q, 64):
		var b := hit["collider"] as Node
		if b == null or seen.has(b):
			continue
		seen[b] = true
		var t := b.get_node_or_null("Stats") as Stats
		if t:
			t.take_damage(amount, caster)


func _sound(stream: AudioStream, at: Vector2, pitch: float, db: float) -> void:
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = at
	p.play()


# --- drawing only ---

func _process(_delta: float) -> void:
	_show_spider()
	_ray.queue_redraw()
	_dome_node.queue_redraw()
	if is_instance_valid(_circle):
		_circle.queue_redraw()


func _show_spider() -> void:
	if _spider == null or _sprite == null:
		return
	var moving := _target != null and _anim > 0.0
	_sprite.frame = (1 + _facing) * 8 + int(_anim * walk_fps) % 8 if moving else _facing
	# blinks red, faster the closer it is to its target (slow ticking while it waits)
	var rate := blink_far * 0.6
	if _target != null and is_instance_valid(_target):
		var d := _spider.global_position.distance_to(_target.global_position)
		var near := clampf(1.0 - (d - reach) / maxf(_lock_dist - reach, 1.0), 0.0, 1.0)
		rate = lerpf(blink_far, blink_near, near * near)
	var age := _timeline.t - _spider_at
	var on := age > dome_down_time and fmod(age * rate, 1.0) < 0.35
	_sprite.modulate = Color(1.0, 0.3, 0.25) if on else Color.WHITE
	# fades in behind the dome while it sinks
	_sprite.modulate.a = clampf(age / maxf(dome_down_time * 0.7, 0.01), 0.0, 1.0)
	_spider.queue_redraw()


func _draw_spider_shadow() -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(Vector2(cos(a) * 7.0, sin(a) * 2.2 - 0.5))
	_spider.draw_colored_polygon(pts, Color(0, 0, 0, 0.22))


func _draw_ray() -> void:
	var t := _timeline.t
	if _blast_t >= 0.0:
		var f := int(_blast_t * blast_fps)
		if f < BLAST_FRAMES:
			var size := 64.0 * blast_scale
			var at := _blast_pos - global_position
			_ray.draw_texture_rect_region(BLAST_TEX, Rect2(at - Vector2(size, size) * 0.5 - Vector2(0, 4), Vector2(size, size)),
					Rect2(f * 64, 0, 64, 64))
	if t >= ray_time:
		return
	var a := 1.0 if t < ray_time * 0.6 else 1.0 - (t - ray_time * 0.6) / (ray_time * 0.4)
	var from := _from - _at
	_ray.draw_line(from, Vector2.ZERO, Color(RAY_EDGE, a), 2.0)
	_ray.draw_line(from, Vector2.ZERO, Color(RAY_CORE, a), 1.0)
	_ray.draw_circle(Vector2.ZERO, 1.5 * a, Color(DOME_LIGHT, a))


func _draw_circle() -> void:
	var t := _timeline.t
	var fade := 1.0
	var gone_at := dome_down_at + dome_down_time + 0.5
	if _blast_t >= 0.0 or t > gone_at:
		fade = 0.0 if _blast_t >= 0.0 else clampf(1.0 - (t - gone_at) / 0.4, 0.0, 1.0)
	if fade <= 0.0 or t < ray_time * 0.4:
		return
	SummonCircle.draw(_circle, circle_radius, t - ray_time * 0.4, fade, 6, ORANGE_CIRCLE)


func _draw_dome() -> void:
	var t := _timeline.t
	# the half-dome: rises out of the circle, glows, then sinks back into it
	var r := 0.0
	if t > ray_time * 0.5 and t < dome_up_at:
		var k := (t - ray_time * 0.5) / (dome_up_at - ray_time * 0.5)
		r = dome_radius * (1.0 - pow(1.0 - k, 3.0))
	elif t >= dome_up_at and t < dome_down_at:
		r = dome_radius * (1.0 + 0.05 * sin(t * 30.0))
	elif t >= dome_down_at and t < dome_down_at + dome_down_time:
		r = dome_radius * (1.0 - (t - dome_down_at) / dome_down_time)
	if r > 0.3:
		_dome(r)


## A glowing orange half-sphere sitting on the ground: the top half of a ball, and the flat oval
## where it meets the ground.
func _dome(r: float) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := PI + PI * i / 20.0                       # the arch over the top
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	for i in range(1, 20):
		var a := PI * i / 20.0                            # the front edge of its base, squashed
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.45))
	_dome_node.draw_colored_polygon(pts, Color(DOME_DARK, 0.9))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.8 + Vector2(0, -r * 0.08))
	_dome_node.draw_colored_polygon(inner, Color(DOME, 0.9))
	_dome_node.draw_circle(Vector2(-r * 0.32, -r * 0.55), r * 0.22, Color(DOME_LIGHT, 0.9))   # shine
	_dome_node.draw_polyline(pts, Color(DOME_LIGHT, 0.6), 0.5)
