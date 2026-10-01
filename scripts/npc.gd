class_name Npc
extends StaticBody2D
## A shopkeeper. Walk up, press F to trade.

@export var display_name := "Shopkeeper"
@export var shop: Shop
@export var interact_range := 44.0
## Optional: replaces the default shopkeeper picture.
@export var sprite_texture: Texture2D

const PX := 0.5   # one real screen pixel in world units (camera zoom is 2)

var _near := false


func _ready() -> void:
	add_to_group("interactables")
	if sprite_texture:
		$Sprite2D.texture = sprite_texture


func _process(_delta: float) -> void:
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
