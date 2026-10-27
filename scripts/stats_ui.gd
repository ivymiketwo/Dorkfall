class_name StatsUI
extends Control
## Character stats window (press C): Intelligence and Vitality, with a
## [+] button per stat to spend level-up points. Shows what each stat is doing, and under that
## what your worn gear adds (this used to be in the old Equipment window).

const ROW_H := 24
const TOP := 27
const BTN := Vector2(11, 11)
const INFO := {
	"int": ["Mana", "Magic"],
	"vit": ["Health"],
}
const COLORS := {"int": Color("6fb4ff"), "vit": Color("e8695a")}
## The gear bonuses section under the stats.
const GEAR_H := 40

var attrs: Attributes
var equipment: Equipment
var _hover := ""


func _ready() -> void:
	CloseButton.attach(self)
	size = Vector2(122, TOP + Attributes.NAMES.size() * ROW_H + 6 + GEAR_H)
	position = Vector2(94, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group("stats_ui")


func _bind() -> void:
	if attrs != null:
		return
	var p := get_tree().get_first_node_in_group("player")
	attrs = p.get_node_or_null("Attributes") if p else null
	if attrs:
		attrs.changed.connect(queue_redraw)
	equipment = p.get_node_or_null("Equipment") if p else null
	if equipment:
		equipment.changed.connect(queue_redraw)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("stats"):
		_bind()
		visible = not visible
		queue_redraw()
		get_viewport().set_input_as_handled()


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


func _btn_rect(i: int) -> Rect2:
	return Rect2(Vector2(size.x - 6 - BTN.x, TOP + i * ROW_H + 1), BTN)


func _stat_at(p: Vector2) -> String:
	for i in Attributes.NAMES.size():
		if _btn_rect(i).has_point(p):
			return Attributes.NAMES[i]
	return ""


func _gui_input(event: InputEvent) -> void:
	if attrs == null:
		return
	if event is InputEventMouseMotion:
		_hover = _stat_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var s := _stat_at(event.position)
		if s != "":
			attrs.spend(s)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""
		queue_redraw()


func _draw() -> void:
	var px := _px()
	UiStyle.window(self, Rect2(Vector2.ZERO, size), "Stats", px)
	if attrs == null:
		return
	var un := attrs.unspent()
	var pts := "Points  %d" % un
	HiFont.draw(self, Vector2(size.x - 6 - HiFont.text_width(pts, px), 14), pts,
			Color("ffe066") if un > 0 else UiStyle.TEXT_DIM, px)
	HiFont.draw(self, Vector2(6, 14), "Level %d" % attrs.xp.level, UiStyle.TEXT_DIM, px)
	UiStyle.divider(self, Vector2(5, 23), size.x - 10, px)
	for i in Attributes.NAMES.size():
		var n: String = Attributes.NAMES[i]
		var y := TOP + i * ROW_H
		HiFont.draw(self, Vector2(6, y), Attributes.LABELS[n], COLORS[n], px)
		var bonus := attrs.bonus_of(n)
		var val := str(attrs.base_of(n))
		HiFont.draw(self, Vector2(6, y + 9), val, UiStyle.TEXT, px)
		if bonus > 0:
			HiFont.draw(self, Vector2(6 + HiFont.text_width(val, px) + 3, y + 9), "+%d" % bonus, Color("8fd0ff"), px)
		# what it does
		var pool := "%s %d" % [INFO[n][0], int(attrs.pool_for(n))]
		HiFont.draw(self, Vector2(38, y + 9), pool, UiStyle.TEXT_DIM, px)
		if INFO[n].size() > 1:   # only Intelligence also raises damage
			var dmg := "%s +%d%%" % [INFO[n][1], int(round(attrs.damage_percent(n)))]
			HiFont.draw(self, Vector2(38, y + 17), dmg, UiStyle.TEXT_DIM, px)
		var r := _btn_rect(i)
		var can := attrs.can_spend(n)
		UiStyle.button(self, r, "", (1 if n == _hover else 0) if can else 2, px)
		var c := Color("ffe066") if can else UiStyle.STEEL_DARK
		var m := r.get_center()
		draw_rect(Rect2(m.x - 3, m.y - 0.5, 6, 1), c)
		draw_rect(Rect2(m.x - 0.5, m.y - 3, 1, 6), c)
	# what the worn gear adds
	if equipment:
		var ty := TOP + Attributes.NAMES.size() * ROW_H + 2.0
		UiStyle.divider(self, Vector2(5, ty), size.x - 10, px)
		HiFont.draw(self, Vector2(6, ty + 4), "Gear bonuses", UiStyle.GOLD, px)
		var rows := [
			["Defense", "%s%%" % _fmt(equipment.total("defense"))],
			["Mana regen", "+%s/s" % _fmt(equipment.total("mana_regen_bonus"))],
			["Magic dmg", "+%s%%" % _fmt(equipment.total("magic_damage_bonus"))],
		]
		for k in rows.size():
			var y := ty + 13 + k * 8
			HiFont.draw(self, Vector2(6, y), rows[k][0], UiStyle.TEXT_DIM, px)
			HiFont.draw(self, Vector2(size.x - 6 - HiFont.text_width(rows[k][1], px), y), rows[k][1], Color("8fd0ff"), px)


func _fmt(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


func close_ui() -> void:
	visible = false
