class_name Lift
extends Interactable
## The way out. Rides up with the research drive (or once the drive is wiped).
## Once the chain has frozen H-7 and wiped the drive, it can also be sealed
## from below: the SEAL ending.

func get_prompt(_a: Node) -> String:
	if Legacy.can_seal():
		return "Lift controls"
	return "Ride the lift up"


func can_interact(_a: Node) -> bool:
	return GameState.inventory.has("research_drive") or Legacy.decision("drive") == "destroyed" or Legacy.can_seal()


func get_refusal(_a: Node) -> String:
	return "Not leaving without the research drive"


func interact(a: Node) -> void:
	if not can_interact(a):
		return
	if Legacy.can_seal():
		var opts := [["seal", "Cut the cable. Stay."], ["wait", "Not yet"]]
		if GameState.inventory.has("research_drive") or Legacy.decision("drive") == "destroyed":
			opts.insert(0, ["ride", "Ride up"])
		Events.open_choice.emit("THE LAST CAGE", "The freezer hums. The drive is gone. If you cut the cable from down here, nobody comes down after you, and nobody goes up.\n\nVarga said someone has to keep the lights off and keep it company.", opts, func(c: String):
			if c == "ride":
				ride(a)
			elif c == "seal":
				interacted.emit(a)
				Events.ending_started.emit("seal"))
		return
	ride(a)


func ride(a: Node) -> void:
	GameState.objectives.complete("extract")
	GameState.active = false
	super.interact(a)
	Events.expedition_ended.emit("extracted")
