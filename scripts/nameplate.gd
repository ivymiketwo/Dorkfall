extends Node2D
## Name + health bar floating above an enemy. Reads `display_name` and the
## Stats child from its parent.

@export var bar_width := 30
@export var name_color := Color("ffe08a")

var _stats: Stats


func _ready() -> void:
	_stats = get_parent().get_node("Stats")
	_stats.changed.connect(queue_redraw)
	var e := get_parent().get_node_or_null("Experience") as Experience
	if e:
		e.changed.connect(queue_redraw)


func _draw() -> void:
	var label: String = get_parent().display_name
	var lv = null
	var exp_node := get_parent().get_node_or_null("Experience") as Experience
	if exp_node:
		lv = exp_node.level
	elif "level" in get_parent():
		lv = get_parent().level
	if lv != null:
		label = "Lv%d %s" % [lv, label]
	# centred on a whole screen pixel (0.5 world px): a text width is often an odd number of
	# screen pixels, and half of that would put the text between pixels, so while moving it
	# would round differently from the character and flicker 1 px back and forth.
	var tx := floorf(-HiFont.text_width(label, 0.5)) / 2.0
	HiFont.draw(self, Vector2(tx, -9), label, name_color, 0.5)
	var x := -floori(bar_width / 2.0)
	draw_rect(Rect2(x - 1, -1, bar_width + 2, 4), Color("1a1a22"))
	draw_rect(Rect2(x, 0, bar_width, 2), Color("d04848").darkened(0.7))
	var fill := int(bar_width * clampf(_stats.health / _stats.max_health, 0.0, 1.0))
	if fill > 0:
		draw_rect(Rect2(x, 0, fill, 2), Color("d04848"))
