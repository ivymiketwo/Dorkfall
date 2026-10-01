class_name StatsFx
extends RefCounted
## The visible side of Stats: damage numbers and the red "OUT OF MANA" text. Stats itself has
## no visuals; it only emits `damaged` and `out_of_mana`, and this listens. A server leaves
## `show_effects` off on its Stats and never loads any of this.

static func attach(stats: Stats) -> void:
	stats.damaged.connect(func(amount: float): _number(stats, amount))
	stats.out_of_mana.connect(func(): _say(stats, "OUT OF MANA", Color("e03c3c")))


static func _host(stats: Stats) -> Node2D:
	var host := stats.get_parent() as Node2D
	return host if host != null and host.get_parent() != null else null


static func _number(stats: Stats, amount: float) -> void:
	var host := _host(stats)
	if host:
		FloatingText.damage(host.get_parent(), host.position + Vector2(0, -26), amount, host.is_in_group("player"))


static func _say(stats: Stats, text: String, col: Color) -> void:
	var host := _host(stats)
	if host:
		FloatingText.spawn(host.get_parent(), host.position + Vector2(0, -26), text, col)
