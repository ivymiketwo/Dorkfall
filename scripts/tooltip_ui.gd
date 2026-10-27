class_name TooltipUI
extends Control
## The one item tooltip, drawn in front of every window (it sits in the HUD with a high z_index,
## above windows, the right-click menu and the Esc menu). A window asks for a tooltip with
## TooltipUI.show_tip(self, at, title, lines) while something is hovered, and TooltipUI.hide_tip(self)
## when nothing is; `at` is in that window's own coordinates, and the tooltip goes to the left of it
## (or to the right if there's no room), kept on screen.

const GROUP := "tooltip_ui"
const STAT_TEXT := Color("8fd0ff")

var _owner_id := 0
var _at := Vector2.ZERO
var _title := ""
var _lines := PackedStringArray()
var _title_color := UiStyle.GOLD
var _line_colors: Array = []      ## optional colour per line (else STAT_TEXT)
## An item being dragged (follows the mouse in front of everything).
var _icon_owner := 0
var _icon_tex: Texture2D
var _icon_region := Rect2()
var _icon_rect := Rect2()


static func _find(tree: SceneTree) -> TooltipUI:
	return tree.get_first_node_in_group(GROUP) as TooltipUI if tree else null


static func show_tip(from: CanvasItem, at: Vector2, title: String, lines := PackedStringArray(),
		title_color := UiStyle.GOLD, line_colors: Array = []) -> void:
	var t := _find(from.get_tree())
	if t == null:
		return
	var p := from.get_global_transform() * at
	if t._owner_id == from.get_instance_id() and t._at == p and t._title == title and t._lines == lines \
			and t._line_colors == line_colors:
		return
	t._owner_id = from.get_instance_id()
	t._at = p
	t._title = title
	t._lines = lines
	t._title_color = title_color
	t._line_colors = line_colors
	t.queue_redraw()


static func hide_tip(from: CanvasItem) -> void:
	var t := _find(from.get_tree())
	if t and t._owner_id == from.get_instance_id():
		t._owner_id = 0
		t.queue_redraw()


## Draws `tex` (`region` of it) at `rect` (in `from`'s coordinates), in front of every window.
static func show_icon(from: CanvasItem, tex: Texture2D, region: Rect2, rect: Rect2) -> void:
	var t := _find(from.get_tree())
	if t == null:
		return
	var xf := from.get_global_transform()
	t._icon_owner = from.get_instance_id()
	t._icon_tex = tex
	t._icon_region = region
	t._icon_rect = Rect2(xf * rect.position, xf.basis_xform(rect.size))
	t.queue_redraw()


static func hide_icon(from: CanvasItem) -> void:
	var t := _find(from.get_tree())
	if t and t._icon_owner == from.get_instance_id():
		t._icon_owner = 0
		t.queue_redraw()


func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100


func _process(_delta: float) -> void:
	# the window that asked went away (closed / hidden): drop its tooltip
	for key in ["_owner_id", "_icon_owner"]:
		var id: int = get(key)
		if id != 0:
			var o := instance_from_id(id) as CanvasItem
			if o == null or not o.is_visible_in_tree():
				set(key, 0)
				queue_redraw()


func _draw() -> void:
	if _icon_owner != 0 and _icon_tex:
		draw_texture_rect_region(_icon_tex, _icon_rect, _icon_region, Color(1, 1, 1, 0.9))
	if _owner_id == 0 or _title == "":
		return
	var px := 1.0 / maxf(get_canvas_transform().get_scale().x, 0.001)
	var w := HiFont.text_width(_title, px)
	for l in _lines:
		w = maxf(w, HiFont.text_width(l, px))
	w += 14 * px
	var lh := (HiFont.H + 3) * px
	var h := HiFont.H * px + 14 * px + _lines.size() * lh
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	var x := _at.x - w - 4.0
	if x < 0.0:
		x = _at.x + 8.0
	var tp := Vector2(x, _at.y - h / 2.0).clamp(Vector2.ZERO, (screen - Vector2(w, h)).max(Vector2.ZERO)).snapped(Vector2(px, px))
	UiStyle.panel(self, Rect2(tp, Vector2(w, h)), px)
	HiFont.draw(self, tp + Vector2(7, 7) * px, _title, _title_color, px)
	for k in _lines.size():
		var c: Color = _line_colors[k] if k < _line_colors.size() and _line_colors[k] is Color else STAT_TEXT
		HiFont.draw(self, tp + Vector2(7 * px, 7 * px + (k + 1) * lh), _lines[k], c, px)
