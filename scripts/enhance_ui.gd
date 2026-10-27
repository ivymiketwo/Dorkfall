class_name EnhanceUI
extends Control
## The anvil's enhancing window (opened at the blacksmith's anvil, see anvil.gd):
##   - a square for the item (only staffs for now) at the top,
##   - below it a square for a Magical Elixir and one for Flux,
##   - a progress bar, and the Enhance button under it.
## Put things on it by clicking them in your bag (or dragging them onto the window, or right-click >
## Place on anvil); click a square to take it off again. Nothing leaves your bag until an attempt
## finishes; the rules (and the dice roll) are all in Enhance.attempt.

const ICONS := preload("res://art/items.png")   # 32px icons
const W := 96.0
const H := 133.0
const PAD := 6.0
const HEADER := 14.0
const ITEM_SLOT := 24.0
const MAT_SLOT := 20.0
## Seconds the progress bar takes to fill before the result.
const WORK_TIME := 1.6
const GREEN := Color("40e070")
const RED := Color("e03c3c")
const BAR := Color("e0a040")

var _anvil: Node2D
var _player: Node2D
var _inv: Inventory
var _staff: Item          # the very staff in the bag that's on the anvil
var _elixir := false      # an elixir has been placed
var _flux := false        # flux has been placed
var _work := -1.0         # seconds into an attempt (-1 = not working)
var _hover := ""
var _message := ""
var _message_color := UiStyle.TEXT_DIM
var _flash := 0.0
var _flash_color := Color.WHITE


func _ready() -> void:
	CloseButton.attach(self)
	add_to_group("enhance_ui")
	size = Vector2(W, H)
	var screen := get_viewport_rect().size / get_canvas_transform().get_scale()
	position = Vector2(floorf(screen.x / 2.0 + 24.0), floorf((screen.y - H) / 2.0) - 12.0)   # right of you: the anvil stays in view
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _px() -> float:
	return 1.0 / get_canvas_transform().get_scale().x


# --- opening, closing ---

func open(anvil: Node2D, player: Node2D) -> void:
	_anvil = anvil
	_player = player
	if _inv:
		_inv.changed.disconnect(_on_bag_changed)
	_inv = player.get_node("Inventory")
	_inv.changed.connect(_on_bag_changed)
	_staff = null
	_elixir = false
	_flux = false
	_work = -1.0
	_say("Click a staff, an elixir and flux in your bag", UiStyle.TEXT_DIM)
	visible = true
	var bag := get_tree().get_first_node_in_group("inventory_ui") as Control
	if bag:
		bag.visible = true                  # you'll need your bag to put things on the anvil
		position.x = bag.position.x - W - 4.0   # just left of the bag, so its slots stay clickable
	queue_redraw()


func close() -> void:
	visible = false
	_work = -1.0


func close_ui() -> void:
	close()


## True while the window is up (the bag then puts clicked items on the anvil).
func is_open() -> bool:
	return visible and _inv != null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_bag_changed() -> void:
	if _work < 0.0:
		_tidy()
	queue_redraw()


## Takes off anything that's no longer in the bag.
func _tidy() -> void:
	if _inv == null:
		return
	if _staff != null and _inv.items.find(_staff) == -1:
		_staff = null
	if _elixir and _inv.count_of(Enhance.ELIXIR) <= 0:
		_elixir = false
	if _flux and _inv.count_of(Enhance.FLUX) <= 0:
		_flux = false


# --- putting things on the anvil ---

## Puts a bag item on the anvil (called by the bag). Returns true if it went on.
func place(item: Item) -> bool:
	if item == null or _work >= 0.0:
		return false
	if item == Enhance.ELIXIR:
		_elixir = true
	elif item == Enhance.FLUX:
		_flux = true
	elif item.can_enhance():
		_staff = item
		if item.enhance >= Enhance.MAX_LEVEL:
			_say("%s is already at the most (+%d)" % [item.title(), Enhance.MAX_LEVEL], Color("e0a040"))
			queue_redraw()
			return true
	else:
		_say("Only staffs can be enhanced", Color("e0a040"))
		queue_redraw()
		return false
	_say(_status(), UiStyle.TEXT_DIM)
	queue_redraw()
	return true


func _status() -> String:
	if _staff == null:
		return "Place a staff on the anvil"
	if _staff.enhance >= Enhance.MAX_LEVEL:
		return "Already at +%d" % Enhance.MAX_LEVEL
	if not _elixir:
		return "Add a Magical Elixir"
	if not _flux:
		return "Add Flux"
	return "Chance  %d%%" % roundi(Enhance.chance(_staff.enhance) * 100.0)


# --- the window's layout ---

func _item_rect() -> Rect2:
	return Rect2(Vector2(floorf((W - ITEM_SLOT) / 2.0), HEADER + 3.0), Vector2(ITEM_SLOT, ITEM_SLOT))


func _elixir_rect() -> Rect2:
	return Rect2(Vector2(floorf(W / 2.0) - MAT_SLOT - 4.0, HEADER + 49.0), Vector2(MAT_SLOT, MAT_SLOT))


func _flux_rect() -> Rect2:
	return Rect2(Vector2(floorf(W / 2.0) + 4.0, HEADER + 49.0), Vector2(MAT_SLOT, MAT_SLOT))


func _bar_rect() -> Rect2:
	return Rect2(Vector2(PAD, HEADER + 82.0), Vector2(W - PAD * 2.0, 6.0))


func _button_rect() -> Rect2:
	return Rect2(Vector2(floorf(W / 2.0) - 22.0, HEADER + 92.0), Vector2(44.0, 12.0))


func _part_at(p: Vector2) -> String:
	if _item_rect().has_point(p):
		return "item"
	if _elixir_rect().has_point(p):
		return "elixir"
	if _flux_rect().has_point(p):
		return "flux"
	if _button_rect().has_point(p):
		return "button"
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _part_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		match _part_at(event.position):
			"button":
				_start()
			"item":
				if _work < 0.0:
					_staff = null           # click a square to take it off
			"elixir":
				if _work < 0.0:
					_elixir = false
			"flux":
				if _work < 0.0:
					_flux = false
		if _work < 0.0 and _part_at(event.position) != "button":
			_say(_status(), UiStyle.TEXT_DIM)
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = ""
		queue_redraw()


# --- enhancing ---

func _ready_to_go() -> String:
	if _staff == null:
		return "Place a staff on the anvil"
	if not _elixir:
		return "Add a Magical Elixir"
	if not _flux:
		return "Add Flux"
	return Enhance.blocked_reason(_inv, _staff)


func _start() -> void:
	if _work >= 0.0:
		return
	var why := _ready_to_go()
	if why != "":
		_say(why, RED)
		return
	_work = 0.0
	_say("Enhancing...", UiStyle.TEXT)


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_anvil) or not is_instance_valid(_player) \
			or _anvil.global_position.distance_to(_player.global_position) > 60.0:
		close()
		return
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()
	if _work < 0.0:
		return
	_work += delta
	queue_redraw()
	if _work < WORK_TIME:
		return
	_work = -1.0
	var r := Enhance.attempt(_inv, _staff)
	_staff = r["item"]
	_tidy()
	if not r["ok"]:
		_say(r["message"], RED)
		return
	_flash = 0.6
	_flash_color = GREEN if r["success"] else RED
	_say(r["message"], GREEN if r["success"] else RED)
	_play(r["success"])


func _play(success: bool) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = preload("res://audio/fireball_hit.wav")
	p.pitch_scale = 1.8 if success else 0.7
	p.volume_db = -6.0
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _say(text: String, color: Color) -> void:
	_message = text
	_message_color = color
	queue_redraw()


# --- drawing ---

func _draw() -> void:
	if _inv == null:
		return
	var px := _px()
	UiStyle.panel(self, Rect2(Vector2.ZERO, size))
	HiFont.draw(self, Vector2(PAD, 4), "ENHANCE", UiStyle.GOLD, px)
	draw_rect(Rect2(PAD, HEADER - 3, size.x - PAD * 2, px), UiStyle.BRONZE_MID)
	# the item on top
	var ir := _item_rect()
	UiStyle.slot(self, ir, _hover == "item")
	if _flash > 0.0:
		draw_rect(ir.grow(1.0), Color(_flash_color, _flash), false, 1.0)
	var name_line := "Staff"
	var name_col := UiStyle.TEXT_DIM
	if _staff:
		draw_texture_rect_region(ICONS, Rect2(ir.position + Vector2(2, 2), Vector2(20, 20)),
				Rect2(_staff.frame_for(1) * 32, 0, 32, 32))
		if _staff.enhance > 0:
			var lv := "+%d" % _staff.enhance
			HiFont.draw(self, ir.position + Vector2(ITEM_SLOT - 1.5 - HiFont.text_width(lv, px), 1.5), lv, UiStyle.GOLD, px)
		name_line = _staff.title()
		name_col = UiStyle.GOLD
		if _staff.enhance < Enhance.MAX_LEVEL:
			name_line += "  to +%d" % (_staff.enhance + 1)
	HiFont.draw(self, Vector2(floorf((W - HiFont.text_width(name_line, px)) / 2.0), ir.end.y + 3.0), name_line, name_col, px)
	if _staff and _staff.has_damage():
		# what this level does: the damage range now, and after a success
		var now := _staff.damage_range()
		var dmg := "DAMAGE %d-%d" % [now.x, now.y]
		if _staff.enhance < Enhance.MAX_LEVEL:
			var nx := _staff.damage_range(_staff.enhance + 1)
			dmg += "  to %d-%d" % [nx.x, nx.y]
		HiFont.draw(self, Vector2(floorf((W - HiFont.text_width(dmg, px)) / 2.0), ir.end.y + 11.0), dmg, Color("8fd0ff"), px)
	# the elixir and the flux below it
	_material(_elixir_rect(), Enhance.ELIXIR, _elixir, "elixir", "ELIXIR")
	_material(_flux_rect(), Enhance.FLUX, _flux, "flux", "FLUX")
	# progress bar and button
	var frac := clampf(_work / WORK_TIME, 0.0, 1.0) if _work >= 0.0 else 0.0
	UiStyle.bar(self, _bar_rect(), frac, BAR)
	var br := _button_rect()
	var can := _work < 0.0 and _ready_to_go() == ""
	UiStyle.slot(self, br, _hover == "button" and can)
	if can:
		draw_rect(Rect2(br.position + Vector2.ONE * px, Vector2(br.size.x - px * 2, px)), UiStyle.BRONZE_LIGHT)
	var label := "ENHANCE"
	HiFont.draw(self, br.position + Vector2(floorf((br.size.x - HiFont.text_width(label, px)) / 2.0), 3.5), label,
			UiStyle.GOLD if can else UiStyle.TEXT_DIM, px)
	# message line
	var my := br.end.y + 4.0
	HiFont.draw(self, Vector2(floorf((W - HiFont.text_width(_message, px)) / 2.0), my), _message, _message_color, px)


func _material(r: Rect2, item: Item, placed: bool, key: String, label: String) -> void:
	var px := _px()
	UiStyle.slot(self, r, _hover == key)
	var have := _inv.count_of(item)
	if placed:
		draw_texture_rect_region(ICONS, Rect2(r.position + Vector2(2, 1), Vector2(16, 16)),
				Rect2(item.frame_for(1) * 32, 0, 32, 32))
		var n := HiFont.short_count(have)
		HiFont.draw(self, r.position + Vector2(MAT_SLOT - 1.5 - HiFont.text_width(n, px), MAT_SLOT - 5.0), n, Color("f0d040"), px)
	else:
		draw_texture_rect_region(ICONS, Rect2(r.position + Vector2(2, 1), Vector2(16, 16)),
				Rect2(item.frame_for(1) * 32, 0, 32, 32), Color(1, 1, 1, 0.18))
	HiFont.draw(self, Vector2(r.position.x + floorf((MAT_SLOT - HiFont.text_width(label, px)) / 2.0), r.end.y + 2.0),
			label, UiStyle.TEXT if placed else UiStyle.TEXT_DIM, px)
