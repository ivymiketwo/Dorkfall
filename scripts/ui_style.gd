class_name UiStyle
## Shared look for every window, panel and slot (Rex's reference: a classic MMO inventory).
## Brushed-steel bevelled frame, dark charcoal-blue inside, a title bar across the top with the
## title in the middle, black slots with a thin grey edge, blue tabs, steel buttons.
## Coordinates are HUD canvas units; `px` is one real screen pixel in those units (0.5 at 720p).

const OUTLINE := Color("050608")
const STEEL_LIGHT := Color("d3d7df")
const STEEL_MID := Color("8d929c")
const STEEL_DARK := Color("4a4e57")
const FILL_TOP := Color("1f222a")
const FILL_BOT := Color("121419")
## Title bar
const TITLE_TOP := Color("3c414c")
const TITLE_BOT := Color("22252c")
const TITLE_TEXT := Color("eef0f4")
## Sunken areas (the slot grid's well, the gold field)
const WELL := Color("0b0c0f")
const WELL_EDGE := Color("3d414a")
## Slots
const SLOT_FILL := Color("07080a")
const SLOT_EDGE := Color("33363e")
const SLOT_HOVER := Color("1b1f27")
const SLOT_HOVER_EDGE := Color("9aa0ac")
## Tabs
const TAB_TOP := Color("3d8de0")
const TAB_BOT := Color("14508f")
const TAB_OFF_TOP := Color("3a3e47")
const TAB_OFF_BOT := Color("24272e")
## Text
const GOLD := Color("f6d76b")       ## item names, highlights
const TEXT := Color("e6e8ec")
const TEXT_DIM := Color("8e94a0")
const MONEY := Color("ff7a3c")      ## the gold amount (orange-red, like the reference)
## A thin line between sections of a window.
const DIVIDER := Color("454a54")

## Frame thickness (units) and the title bar under it. Content starts at FRAME + TITLE_H.
const FRAME := 2.0
const TITLE_H := 9.0


## A plain panel: steel bevel frame with clipped corners, dark gradient inside.
static func panel(c: CanvasItem, r: Rect2, px := 0.5) -> void:
	var p := px
	# outline with clipped corners
	c.draw_rect(Rect2(r.position + Vector2(p, 0), r.size - Vector2(p * 2, 0)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(0, p), r.size - Vector2(0, p * 2)), OUTLINE)
	# bevel: light top / left, dark bottom / right, a mid-steel band, then a dark line
	var b := r.grow(-p)
	c.draw_rect(b, STEEL_MID)
	c.draw_rect(Rect2(b.position, Vector2(b.size.x - p, p)), STEEL_LIGHT)
	c.draw_rect(Rect2(b.position, Vector2(p, b.size.y - p)), STEEL_LIGHT)
	c.draw_rect(Rect2(b.position + Vector2(p, b.size.y - p), Vector2(b.size.x - p, p)), STEEL_DARK)
	c.draw_rect(Rect2(b.position + Vector2(b.size.x - p, p), Vector2(p, b.size.y - p)), STEEL_DARK)
	var f := r.grow(-p * 3)
	c.draw_rect(f, OUTLINE)
	f = f.grow(-p)
	_gradient(c, f, FILL_TOP, FILL_BOT, p)


## A window: panel + title bar with `title` centred in it. Returns the area under the title bar.
## Menus give themselves a close button with CloseButton.attach (it sits in the title bar).
static func window(c: CanvasItem, r: Rect2, title: String, px := 0.5) -> Rect2:
	panel(c, r, px)
	var t := Rect2(r.position + Vector2(FRAME, FRAME), Vector2(r.size.x - FRAME * 2, TITLE_H))
	_gradient(c, t, TITLE_TOP, TITLE_BOT, px)
	c.draw_rect(Rect2(t.position, Vector2(t.size.x, px)), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(t.position + Vector2(0, t.size.y - px), Vector2(t.size.x, px)), OUTLINE)
	c.draw_rect(Rect2(t.position + Vector2(0, t.size.y), Vector2(t.size.x, px)), DIVIDER)
	if title != "":
		var w := HiFont.text_width(title, px)
		var tp := (t.position + Vector2((t.size.x - w) / 2.0, (t.size.y - HiFont.H * px) / 2.0)).snapped(Vector2(px, px))
		HiFont.draw(c, tp, title, TITLE_TEXT, px)
	return Rect2(r.position + Vector2(FRAME, FRAME + TITLE_H + px), r.size - Vector2(FRAME * 2, FRAME * 2 + TITLE_H + px))


## A sunken area (behind a slot grid, a text field, the gold amount).
static func well(c: CanvasItem, r: Rect2, px := 0.5) -> void:
	c.draw_rect(r, WELL_EDGE)
	c.draw_rect(Rect2(r.position, r.size - Vector2(px, px)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(px, px), r.size - Vector2(px * 2, px * 2)), WELL)


static func slot(c: CanvasItem, r: Rect2, hover := false, px := 0.5) -> void:
	c.draw_rect(r, SLOT_HOVER_EDGE if hover else SLOT_EDGE)
	var i := r.grow(-px)
	c.draw_rect(i, SLOT_HOVER if hover else SLOT_FILL)
	c.draw_rect(Rect2(i.position, Vector2(i.size.x, px)), Color(0, 0, 0, 0.9))       # inner shadow
	c.draw_rect(Rect2(i.position, Vector2(px, i.size.y)), Color(0, 0, 0, 0.9))


## A tab on top of a page (blue when it's the open one).
static func tab(c: CanvasItem, r: Rect2, text: String, active: bool, px := 0.5) -> void:
	c.draw_rect(Rect2(r.position + Vector2(px, 0), r.size - Vector2(px * 2, 0)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(0, px), r.size - Vector2(0, px)), OUTLINE)
	var i := Rect2(r.position + Vector2(px, px), r.size - Vector2(px * 2, px))
	_gradient(c, i, TAB_TOP if active else TAB_OFF_TOP, TAB_BOT if active else TAB_OFF_BOT, px)
	c.draw_rect(Rect2(i.position, Vector2(i.size.x, px)), Color(1, 1, 1, 0.35 if active else 0.12))
	var w := HiFont.text_width(text, px)
	var tp := (i.position + Vector2((i.size.x - w) / 2.0, (i.size.y - HiFont.H * px) / 2.0)).snapped(Vector2(px, px))
	HiFont.draw(c, tp, text, TITLE_TEXT if active else TEXT_DIM, px)


## A steel button with centred text. `state`: 0 normal, 1 hover, 2 pressed / selected.
static func button(c: CanvasItem, r: Rect2, text: String, state := 0, px := 0.5, text_color := Color(0, 0, 0, 0)) -> void:
	c.draw_rect(Rect2(r.position + Vector2(px, 0), r.size - Vector2(px * 2, 0)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(0, px), r.size - Vector2(0, px * 2)), OUTLINE)
	var b := r.grow(-px)
	var top := Color("4a505c") if state == 1 else (Color("2a2e36") if state == 2 else Color("3a3f49"))
	var bot := Color("2b2f37") if state == 1 else (Color("3a3f49") if state == 2 else Color("1f2228"))
	_gradient(c, b, top, bot, px)
	var hi := STEEL_MID if state != 2 else STEEL_DARK
	var lo := STEEL_DARK if state != 2 else STEEL_MID
	c.draw_rect(Rect2(b.position, Vector2(b.size.x, px)), hi)
	c.draw_rect(Rect2(b.position, Vector2(px, b.size.y)), hi)
	c.draw_rect(Rect2(b.position + Vector2(0, b.size.y - px), Vector2(b.size.x, px)), lo)
	c.draw_rect(Rect2(b.position + Vector2(b.size.x - px, 0), Vector2(px, b.size.y)), lo)
	if text != "":
		var w := HiFont.text_width(text, px)
		var tp := (b.position + Vector2((b.size.x - w) / 2.0, (b.size.y - HiFont.H * px) / 2.0)).snapped(Vector2(px, px))
		HiFont.draw(c, tp, text, text_color if text_color.a > 0.0 else (TEXT if state != 0 else Color("c9ced8")), px)


## A horizontal line between sections.
static func divider(c: CanvasItem, from: Vector2, width: float, px := 0.5) -> void:
	c.draw_rect(Rect2(from, Vector2(width, px)), OUTLINE)
	c.draw_rect(Rect2(from + Vector2(0, px), Vector2(width, px)), DIVIDER)


## 25558069 -> "25,558,069"
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func bar(c: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	## Rounded-end gauge with a glossy top highlight.
	c.draw_rect(Rect2(r.position + Vector2(1, 0), r.size - Vector2(2, 0)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(0, 1), r.size - Vector2(0, 2)), OUTLINE)
	var i := Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2))
	c.draw_rect(i, col.darkened(0.75))
	var w := floorf(i.size.x * clampf(frac, 0.0, 1.0))
	if w > 0.0:
		c.draw_rect(Rect2(i.position, Vector2(w, i.size.y)), col)
		c.draw_rect(Rect2(i.position, Vector2(w, 1)), col.lightened(0.45))
		c.draw_rect(Rect2(i.position + Vector2(0, i.size.y - 1), Vector2(w, 1)), col.darkened(0.3))


static func _gradient(c: CanvasItem, r: Rect2, top: Color, bot: Color, px: float) -> void:
	var bands := maxi(int(r.size.y / px), 1)
	for i in bands:
		c.draw_rect(Rect2(r.position + Vector2(0, i * px), Vector2(r.size.x, minf(px, r.size.y - i * px))),
				top.lerp(bot, float(i) / maxf(bands - 1, 1)))
