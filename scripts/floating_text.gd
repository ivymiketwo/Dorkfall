class_name FloatingText
extends Node2D
## Chunky floating text: "+25 COINS", "EQUIPPED ...", and damage numbers. Drawn with the
## HiFont pixel font at a big size, with a thick dark outline and drop shadow, and it
## pops in, drifts up and fades.

var text := ""
var color := Color.WHITE
## Optional second part drawn right after `text` in its own colour (the Ward's "(-X)").
var suffix := ""
var suffix_color := Color("8fd0ff")
var px := 1.0          ## size of one font pixel in world units (1.0 = 2 screen pixels)
var rise := 20.0
var life := 1.0


static func spawn(parent: Node, pos: Vector2, msg: String, col: Color = Color.WHITE, size := -1.0) -> void:
	var t := FloatingText.new()
	t.text = msg
	t.color = col
	t.px = size if size > 0.0 else 0.5   # 1 font pixel = 1 screen pixel
	t.position = pos + Vector2(randf_range(-4.0, 4.0), 0.0)
	t.z_index = 50
	parent.add_child(t)


## A damage number over `pos`. Big hits are bigger and orange; hits on the player are red.
## `warded` = damage the Ward stopped, shown after the number as a blue "(-X)".
static func damage(parent: Node, pos: Vector2, amount: float, on_player: bool, warded := 0.0) -> void:
	if amount < 0.5 or parent == null:
		return
	var col := Color("fff0a8")
	var size := 0.5
	if on_player:
		col = Color("ff5a4a")
	if amount >= 100.0:
		size = 1.0
		col = Color("ff5a4a") if on_player else Color("ffb030")
	var t := FloatingText.new()
	t.text = str(int(round(amount)))
	t.color = col
	if warded >= 0.5:
		t.suffix = " (-%d)" % int(round(warded))
	t.px = size
	t.rise = 22.0 if size > 0.5 else 16.0
	t.position = pos + Vector2(randf_range(-7.0, 7.0), randf_range(-3.0, 3.0))
	t.z_index = 50
	parent.add_child(t)


func _ready() -> void:
	scale = Vector2(1.7, 1.7)            # pops in big, settles
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", position.y - rise, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(life - 0.3)
	tw.chain().tween_callback(queue_free)


func _draw() -> void:
	var w := HiFont.text_width(text + suffix, px)
	var p := Vector2(-w / 2.0, -HiFont.H * px / 2.0).snapped(Vector2(0.5, 0.5))
	# drop shadow, then outlined text on top
	HiFont.draw(self, p + Vector2(0.0, px * 1.5), text + suffix, Color(0, 0, 0, 0.55), px)
	HiFont.draw(self, p, text, color, px)
	if suffix != "":
		HiFont.draw(self, p + Vector2(HiFont.text_width(text, px) + px, 0.0), suffix, suffix_color, px)
