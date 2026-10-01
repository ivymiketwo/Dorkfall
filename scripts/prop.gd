extends StaticBody2D
## Small decoration from art/props.png. Pick which one with `prop_frame`:
## 0 well, 1 barrel, 2 crate, 3 anvil.

@export_range(0, 3) var prop_frame := 0


func _ready() -> void:
	$Sprite2D.frame = prop_frame
