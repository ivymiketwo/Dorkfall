class_name Players
extends RefCounted
## Single place that answers "which player?". Nothing else should call
## get_first_node_in_group("player") directly, so that going multiplayer
## later only means changing this file.

static func all(tree: SceneTree) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n in tree.get_nodes_in_group("player"):
		if n is Node2D:
			out.append(n)
	return out

## Players that are still standing.
static func alive(tree: SceneTree) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for p in all(tree):
		var st := p.get_node_or_null("Stats") as Stats
		if st == null or st.health > 0.0:
			out.append(p)
	return out


## The player controlled on THIS machine (camera, HUD, ambient, day/night).
static func local(tree: SceneTree) -> Node2D:
	return tree.get_first_node_in_group("player") as Node2D

## Closest player to a point (enemy targeting). `alive_only` skips dead players.
static func nearest(tree: SceneTree, pos: Vector2, alive_only := false) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for p in (alive(tree) if alive_only else all(tree)):
		var d := p.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best
