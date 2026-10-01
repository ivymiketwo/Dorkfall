extends StaticBody2D
## Luck: an old, fat, very smelly-nosed knight who wants Vorly the dragon gone.
## Walk up and press F. His talk is driven by DialogueUI through get_dialogue / choose.

@export var display_name := "Luck"
@export var interact_range := 44.0

const PX := 0.5
const QUEST := "vorly"

const BOB_PERIOD := 0.6        ## seconds per up/down step
const SPLIT_ROW := 32          ## art row where the upper body ends (below the belt and hands)
const OVERLAP := 4             ## rows the legs sprite shares with the upper body, so the seam never opens

var _near := false
var _upper: Sprite2D
var _bob := 0.0


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("quest_giver_npc")
	_split_sprite()


## Idle animation: the sprite is cut in two so the upper body can bob 1px up and down.
func _split_sprite() -> void:
	var legs: Sprite2D = $Sprite2D
	var tex := legs.texture
	var h := tex.get_height()
	legs.region_enabled = true
	legs.region_rect = Rect2(0, SPLIT_ROW - OVERLAP, tex.get_width(), h - SPLIT_ROW + OVERLAP)
	legs.offset = Vector2(0, -(h - SPLIT_ROW + OVERLAP) / 2.0)
	_upper = Sprite2D.new()
	_upper.texture = tex
	_upper.scale = legs.scale
	_upper.region_enabled = true
	_upper.region_rect = Rect2(0, 0, tex.get_width(), SPLIT_ROW)
	_upper.offset = Vector2(0, -(h - SPLIT_ROW / 2.0))
	add_child(_upper)
	_bob = randf() * BOB_PERIOD * 2.0


func _process(delta: float) -> void:
	_bob += delta
	if _upper:
		_upper.position.y = -1.0 if int(_bob / BOB_PERIOD) % 2 == 0 else 0.0
	var player := Players.local(get_tree())
	var near := player != null and global_position.distance_to(player.global_position) <= interact_range
	if near != _near:
		_near = near
		queue_redraw()


func interact(player: Node2D) -> void:
	var ui := get_tree().get_first_node_in_group("dialogue_ui")
	if ui:
		ui.open(self, player)


## What he says right now: {"text", "buttons": [{"id", "label"}]}.
func get_dialogue(_player: Node2D) -> Dictionary:
	var d := _quest_dialogue()
	# once you have taken the quest, he is happy to talk about the old days
	if Quests.state_of(QUEST) != 0:
		var story := {"id": "story", "label": "TELL ME ABOUT YOU"}
		if d["buttons"][0]["id"] == "turnin":
			d["buttons"].append(story)
		else:
			d["buttons"].insert(0, story)
	return d


func _quest_dialogue() -> Dictionary:
	match Quests.state_of(QUEST):
		0:
			return {
				"text": "Ugh! Can't you smell that? UGH! It smells so bad! Hey kid! You wanna make some gold? I need that smelly dragon taken care of. Tell you what, if you manage to slay Vorly the dragon, I'll reward you handsomely.",
				"buttons": [{"id": "accept", "label": "I'LL SLAY VORLY"}, {"id": "close", "label": "NOT NOW"}],
			}
		1:
			return {
				"text": "Still alive, is he?! Ugh, that stench is going to be the death of me. Go on, kid, Vorly won't slay himself!",
				"buttons": [{"id": "close", "label": "I'M ON IT"}],
			}
		2:
			return {
				"text": "HA! Can you smell that? ...Nothing! Sweet, sweet nothing! You did it, kid! Here, take your gold and my thanks, you earned every coin.",
				"buttons": [{"id": "turnin", "label": "TAKE REWARD"}],
			}
	return {
		"text": "Ahh, fresh air at last! Best day of my life, kid. If the stink ever comes back, I'll know who to call!",
		"buttons": [{"id": "close", "label": "GOODBYE"}],
	}


## A button was pressed. Returns the next dialogue, or {} to close.
func choose(id: String, player: Node2D) -> Dictionary:
	match id:
		"story":
			return {
				"text": "You know... I used to be the strongest knight in Espenhal... I could throw a sword over that mountain! These days I'm washed up, couldn't even kill a Mangyang.",
				"buttons": [{"id": "back", "label": "BACK"}, {"id": "close", "label": "GOODBYE"}],
			}
		"back":
			return get_dialogue(player)
		"accept":
			Quests.accept(QUEST)
			return {"text": "That's the spirit! The big stinky beast is out past the village. Come back when he's dead and I'll pay you handsomely!", "buttons": [{"id": "close", "label": "LEAVE IT TO ME"}]}
		"turnin":
			var r := Quests.turn_in(QUEST, player)
			if r["ok"]:
				return {"text": "%s Now, if you'll excuse me, I'm going to go stand somewhere breezy." % r["message"], "buttons": [{"id": "close", "label": "THANKS, LUCK"}]}
			return {"text": "Your pockets are full, kid! Make some room, I can't hand over the gold.", "buttons": [{"id": "close", "label": "OK"}]}
	return {}


func _draw() -> void:
	var name_text := display_name.to_upper()
	HiFont.draw(self, Vector2(-floorf(HiFont.text_width(name_text, PX) / 2.0), -27), name_text, Color("9ad0ff"), PX)
	if _near:
		var t := "F  TALK"
		HiFont.draw(self, Vector2(-floorf(HiFont.text_width(t, PX) / 2.0), -20), t, Color("f0d040"), PX)
