class_name StatsUI
extends Control
## Character stats window (press C): Intelligence, Vitality and Dexterity, with a
## [+] button per stat to spend level-up points. Shows what each stat is doing.

const ROW_H := 24
const TOP := 27
const BTN := Vector2(11, 11)
const INFO := {
	"int": ["Mana", "Magic"],
	"vit": ["Health"],
	"dex": ["Stamina"],
}
const COLORS := {"int": Color("6fb4ff"), "vit": Color("e8695a"), "dex": Color("6fd06f")}

var attrs: Attributes
var _hover := ""


func _ready() -> void:
	CloseButton.attach(self)
	size = Vector2(122, TOP + 3 * ROW_H + 6)
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
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(6, 5), "Stats", UiStyle.GOLD, px)
	if attrs == null:
		return
	var un := attrs.unspent()
	var pts := "Points  %d" % un
	HiFont.draw(self, Vector2(size.x - 6 - HiFont.text_width(pts, px), 5), pts,
			Color("ffe066") if un > 0 else UiStyle.TEXT_DIM, px)
	draw_line(Vector2(6, 15), Vector2(size.x - 6, 15), Color(0.55, 0.42, 0.22, 0.6), 1.0)
	HiFont.draw(self, Vector2(6, 18), "Level %d" % attrs.xp.level, UiStyle.TEXT_DIM, px)
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
		UiStyle.slot(self, r, can and n == _hover)
		var c := Color("ffe066") if can else Color(0.35, 0.3, 0.25)
		var m := r.get_center()
		draw_rect(Rect2(m.x - 3, m.y - 0.5, 6, 1), c)
		draw_rect(Rect2(m.x - 0.5, m.y - 3, 1, 6), c)


func close_ui() -> void:
	visible = false
