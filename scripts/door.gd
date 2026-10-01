extends Area2D
## Building entrance. Walking into it asks the World to teleport the player
## into the interior named `interior_id` (a child of World/Interiors).

signal entered(door: Area2D)

@export var interior_id := ""


func _ready() -> void:
	add_to_group("doors")
	body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			entered.emit(self))
