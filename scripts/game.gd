extends Node
## The window. The game world renders pixel-perfect on its own 640x360 screen (a SubViewport,
## blown up to the window without smoothing, exactly as before; the camera sits on whole screen
## pixels (Player._place_camera), otherwise fine pixel patterns shimmer when it stops between two),
## and every interface layer
## (HUD, map, menus, fades) is lifted out of it to draw at the window's full resolution on top.
## That is what lets item icons and text show all their pixels.
##
## Interface layers are CanvasLayers in the "ui_layer" group. They stay where they are in the
## scene tree (so all node paths and input keep working); only where they are DRAWN changes.

const UI_GROUP := "ui_layer"


func _ready() -> void:
	for n in get_tree().get_nodes_in_group(UI_GROUP):
		_lift(n)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is CanvasLayer and n.is_in_group(UI_GROUP):
			_lift(n))


func _lift(layer: CanvasLayer) -> void:
	layer.custom_viewport = get_viewport()
	# (Godot prints a few harmless "nonexistent connection" warnings for these layers when
	# the game closes. Known engine quirk; nothing is affected.)
