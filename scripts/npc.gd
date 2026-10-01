class_name Npc
extends StaticBody2D
## A shopkeeper. Walk up, press F to trade.

@export var display_name := "Shopkeeper"
@export var shop: Shop
@export var interact_range := 44.0
## Optional: replaces the default shopkeeper picture.
@export var sprite_texture: Texture2D

## Idle animation: art row where the upper body ends (0 = no idle bob). The upper body
## dips 1px every BOB_PERIOD seconds, sliding over the legs, like Luck and the player.
@export var idle_split_row := 0

const PX := 0.5   # one real screen pixel in world units (camera zoom is 2)
const BOB_PERIOD := 0.6

var _near := false
var _upper: Sprite2D
var _bob := 0.0


func _ready() -> void:
	add_to_group("interactables")
	if sprite_texture:
		$Sprite2D.texture = sprite_texture
	if idle_split_row > 0:
		_split_sprite()


func _split_sprite() -> void:
	var legs: Sprite2D = $Sprite2D
	var tex := legs.texture
	var h := tex.get_height()
	var bottom := legs.offset.y + h / 2.0          # keep the feet where they were
	legs.region_enabled = true
	legs.region_rect = Rect2(0, idle_split_row, tex.get_width(), h - idle_split_row)
	legs.offset = Vector2(legs.offset.x, bottom - (h - idle_split_row) / 2.0)
	_upper = Sprite2D.new()
	_upper.texture = tex
	_upper.scale = legs.scale
	_upper.region_enabled = true
	_upper.region_rect = Rect2(0, 0, tex.get_width(), idle_split_row)
	_upper.offset = Vector2(legs.offset.x, bottom - h + idle_split_row / 2.0)
	add_child(_upper)
	_bob = randf() * BOB_PERIOD * 2.0


func _process(delta: float) -> void:
	if _upper:
		_bob += delta
		_upper.position.y = 0.0 if int(_bob / BOB_PERIOD) % 2 == 0 else 1.0
	var player := Players.local(get_tree())
	var near := player != null and global_position.distance_to(player.global_position) <= interact_range
	if near != _near:
		_near = near
		queue_redraw()


func interact(player: Node2D) -> void:
	var ui := get_tree().get_first_node_in_group("shop_ui")
	if ui and shop:
		ui.open(shop, self, player)


func _draw() -> void:
	var name_text := display_name.to_upper()
	HiFont.draw(self, Vector2(-floorf(HiFont.text_width(name_text, PX) / 2.0), -27), name_text, Color("9ad0ff"), PX)
	if _near:
		var t := "F  TRADE"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), -20), t, Color("f0d040"), PX)
