class_name ChatCommands
extends RefCounted
## Slash commands typed into the chat. Rules only, no UI: `run` returns the lines to show.
## (Dev/admin tools for now. With a server these become permission-checked requests.)

const COINS := preload("res://items/coins.tres")

## THE switch. Set to false (or make can_use() check an account role) and every slash
## command stops working: the chat then treats "/..." as ordinary talk. Single-player: on.
const ENABLED := true


## Who may run commands. Later: look up the player's account role (admin / GM) here.
static func can_use(_player: Node2D) -> bool:
	return ENABLED

const HELP := [
	"/help - this list",
	"/resetquests - clear all quest progress and completions",
	"/quests - show your quest status",
	"/time 0-24 - set the hour of the day",
	"/xp N - give yourself N XP",
	"/gold N - give yourself N coins",
	"/heal - refill health, stamina and mana",
]


## Returns {"lines": Array[String], "ok": bool}.
static func run(text: String, player: Node2D) -> Dictionary:
	if not can_use(player):
		return _out(["Commands are disabled"], false)
	var parts := text.strip_edges().trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return _out(["Type /help for commands"], false)
	var cmd := parts[0].to_lower()
	var arg := parts[1] if parts.size() > 1 else ""
	match cmd:
		"help":
			return _out(HELP)
		"resetquests":
			Quests.reset_all()
			return _out(["All quests reset"])
		"quests":
			var rows: Array = []
			for q in Quests.LIST:
				var st := Quests.state_of(q["id"])
				var word: String = ["not taken", "%d/%d" % [Quests.progress_of(q["id"]), q["count"]], "ready to hand in", "done"][st]
				rows.append("%s: %s" % [q["title"], word])
			return _out(rows)
		"time":
			var dn := player.get_tree().get_first_node_in_group("day_night") as DayNight
			if dn == null or not arg.is_valid_float():
				return _out(["Usage: /time 0-24"], false)
			dn.hour = fposmod(arg.to_float(), 24.0)
			return _out(["It is now %s" % dn.clock_text()])
		"xp":
			var e := player.get_node_or_null("Experience") as Experience
			if e == null or not arg.is_valid_int():
				return _out(["Usage: /xp N"], false)
			e.add_xp(arg.to_int())
			return _out(["Gave %d XP" % arg.to_int()])
		"gold":
			var inv := player.get_node_or_null("Inventory") as Inventory
			if inv == null or not arg.is_valid_int() or arg.to_int() <= 0:
				return _out(["Usage: /gold N"], false)
			inv.add(COINS, arg.to_int())
			return _out(["Gave %d coins" % arg.to_int()])
		"heal":
			var st := player.get_node_or_null("Stats") as Stats
			if st:
				st.refill()
			return _out(["Refilled"])
	return _out(["Unknown command: /%s  (try /help)" % cmd], false)


static func _out(lines: Array, ok := true) -> Dictionary:
	return {"lines": lines, "ok": ok}
