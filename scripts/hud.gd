extends Control
## Health / stamina / mana bars drawn at native pixel resolution
## with the tiny PixelFont, so they stay crisp at any scale.

const BAR_W := 60
const ROW_H := 6       # same as the bar height, so the bars sit flush with no gap
const BAR_H := 6
const ORIGIN := Vector2(4, 4)

const HEALTH_COLOR := Color("d04848")
const STAMINA_COLOR := Color("d8b440")
const MANA_COLOR := Color("4a82e0")

var xp: Experience:
	set(value):
		xp = value
		if xp:
			xp.changed.connect(queue_redraw)
		queue_redraw()

const XP_COLOR := Color("9a6cf0")

var stats: Stats:
	set(value):
		if stats:
			stats.changed.disconnect(queue_redraw)
		stats = value
		if stats:
			stats.changed.connect(queue_redraw)
		queue_redraw()


func _draw() -> void:
	if stats == null:
		return
	_draw_row(0, "HP", stats.health, stats.max_health, HEALTH_COLOR)
	_draw_row(1, "ST", stats.stamina, stats.max_stamina, STAMINA_COLOR)
	_draw_row(2, "MP", stats.mana, stats.max_mana, MANA_COLOR)
	if xp:
		var y := ORIGIN.y + 3 * ROW_H
		HiFont.draw(self, Vector2(ORIGIN.x, y + 1.25), "LV", UiStyle.TEXT, 0.5)
		var need := Experience.xp_to_next(xp.level)
		var frac := 1.0 if need == 0 else float(xp.xp) / need
		var bar := Rect2(ORIGIN.x + 12, y, BAR_W + 2, BAR_H)
		UiStyle.bar(self, bar, frac, XP_COLOR)
		var text := "%d  MAX" % xp.level if need == 0 else "%d  %d/%d" % [xp.level, xp.xp, need]
		if HiFont.text_width(text, 0.5) > bar.size.x - 4:
			text = "MAX" if need == 0 else "%d/%d" % [xp.xp, need]
		_text_in_bar(bar, text)


func _text_in_bar(bar: Rect2, text: String) -> void:
	var w := HiFont.text_width(text, 0.5)
	var pos := Vector2(bar.position.x + floorf((bar.size.x - w) / 2.0), bar.position.y + 1.25)
	HiFont.draw(self, pos + Vector2(0.5, 0.5), text, Color(0, 0, 0, 0.75), 0.5)   # shadow so it reads on any fill
	HiFont.draw(self, pos, text, UiStyle.TEXT, 0.5)


func _draw_row(row: int, label: String, value: float, max_value: float, color: Color) -> void:
	var y := ORIGIN.y + row * ROW_H
	HiFont.draw(self, Vector2(ORIGIN.x, y + 1.25), label, UiStyle.TEXT, 0.5)
	var bar := Rect2(ORIGIN.x + 12, y, BAR_W + 2, BAR_H)
	UiStyle.bar(self, bar, value / max_value, color)
	_text_in_bar(bar, "%d/%d" % [floori(value), floori(max_value)])
