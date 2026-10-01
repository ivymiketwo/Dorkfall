extends Control
## Small list of your running kill quests, under the XP bar.

const ORIGIN := Vector2(4, 40)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var y := ORIGIN.y
	for q in Quests.active():
		var st := Quests.state_of(q["id"])
		var n := Quests.progress_of(q["id"])
		var mark := "> " if q["id"] == Quests.tracked_id() else ""
		var text := mark + "%s  %s" % [String(q["title"]).to_upper(), "DONE - TURN IN" if st == 2 else "%d/%d" % [n, q["count"]]]
		HiFont.draw(self, Vector2(ORIGIN.x, y), text, Color("ffe066") if st == 2 else Color("9ad0ff"), 0.5)
		y += 7
