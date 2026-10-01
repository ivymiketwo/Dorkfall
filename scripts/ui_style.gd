class_name UiStyle
## Shared look for every panel and slot: dark plum-brown glass, bronze bevel,
## clipped corners and a soft inner shadow. Coordinates are HUD canvas units.

const OUTLINE := Color("120d14")
const BRONZE_LIGHT := Color("d2a85a")
const BRONZE_MID := Color("8f6a35")
const BRONZE_DARK := Color("4e3519")
const FILL_TOP := Color("2b2436")
const FILL_BOT := Color("1a1522")
const GOLD := Color("f6d76b")
const TEXT := Color("efe6d2")
const TEXT_DIM := Color("9a8f7c")


static func panel(c: CanvasItem, r: Rect2, px := 0.5) -> void:
	var p := px
	# Outline with clipped corners
	c.draw_rect(Rect2(r.position + Vector2(p, 0), r.size - Vector2(p * 2, 0)), OUTLINE)
	c.draw_rect(Rect2(r.position + Vector2(0, p), r.size - Vector2(0, p * 2)), OUTLINE)
	# Bronze bevel
	var b := Rect2(r.position + Vector2(p, p), r.size - Vector2(p * 2, p * 2))
	c.draw_rect(Rect2(b.position + Vector2(p, 0), b.size - Vector2(p * 2, 0)), BRONZE_MID)
	c.draw_rect(Rect2(b.position + Vector2(0, p), b.size - Vector2(0, p * 2)), BRONZE_MID)
	c.draw_rect(Rect2(b.position + Vector2(p, 0), Vector2(b.size.x - p * 2, p)), BRONZE_LIGHT)
	c.draw_rect(Rect2(b.position + Vector2(0, p), Vector2(p, b.size.y - p * 2)), BRONZE_LIGHT)
	c.draw_rect(Rect2(b.position + Vector2(p, b.size.y - p), Vector2(b.size.x - p * 2, p)), BRONZE_DARK)
	c.draw_rect(Rect2(b.position + Vector2(b.size.x - p, p), Vector2(p, b.size.y - p * 2)), BRONZE_DARK)
	# Dark gap then gradient fill
	var f := Rect2(r.position + Vector2(p * 2, p * 2), r.size - Vector2(p * 4, p * 4))
	c.draw_rect(f, OUTLINE)
	f = Rect2(f.position + Vector2(p, p), f.size - Vector2(p * 2, p * 2))
	var bands := maxi(int(f.size.y / (p * 2.0)), 1)
	for i in bands:
		var t := float(i) / bands
		c.draw_rect(Rect2(f.position + Vector2(0, i * p * 2.0), Vector2(f.size.x, p * 2.0)), FILL_TOP.lerp(FILL_BOT, t))
	# Gold corner studs
	for corner: Vector2 in [Vector2.ZERO, Vector2(r.size.x - p * 2, 0), Vector2(0, r.size.y - p * 2), r.size - Vector2(p * 2, p * 2)]:
		c.draw_rect(Rect2(r.position + corner + Vector2(p, p) * 0.0, Vector2(p * 2, p * 2)), Color(0, 0, 0, 0))
		c.draw_rect(Rect2(r.position + corner + Vector2(p * 0.5, p * 0.5), Vector2(p, p)), BRONZE_LIGHT)


static func slot(c: CanvasItem, r: Rect2, hover := false, px := 0.5) -> void:
	c.draw_rect(r, OUTLINE)
	var i := Rect2(r.position + Vector2(px, px), r.size - Vector2(px * 2, px * 2))
	c.draw_rect(i, Color("3a3046") if hover else Color("15101c"))
	c.draw_rect(Rect2(i.position, Vector2(i.size.x, px)), Color("0a070d"))
	c.draw_rect(Rect2(i.position, Vector2(px, i.size.y)), Color("0a070d"))
	c.draw_rect(Rect2(i.position + Vector2(px, i.size.y - px), Vector2(i.size.x - px, px)), Color("4a3d5a"))
	c.draw_rect(Rect2(i.position + Vector2(i.size.x - px, px), Vector2(px, i.size.y - px)), Color("4a3d5a"))


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
