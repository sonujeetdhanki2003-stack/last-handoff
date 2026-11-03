class_name Transmitter
extends Interactable
## The old relay transmitter in the archive vault: the BROADCAST ending.
## Needs the lift + relay line powered, the vault opened, and Varga's drive in hand.

func _ready() -> void:
	solid = true
	hold_time = 3.0
	super._ready()


func get_prompt(_a: Node) -> String:
	return "Upload Varga's data to the surface"


func can_interact(_a: Node) -> bool:
	return refusal() == ""


func get_refusal(_a: Node) -> String:
	return refusal()


func refusal() -> String:
	if Legacy.decision("power_route") != "lift":
		return "Dead. Nothing powers the relay line"
	if Legacy.decision("archive") == "sealed":
		return "The vault is sealed"
	if Legacy.decision("drive") == "destroyed":
		return "Varga's data is gone"
	if not GameState.inventory.has("research_drive"):
		return "Needs the research drive"
	if Legacy.expeditions_done() < 1:
		return "The relay won't answer an unregistered member"
	return ""


func interact(a: Node) -> void:
	if not can_interact(a):
		return
	if Legacy.decision("drive") == "":
		Legacy.decide("drive", "kept")
	super.interact(a)
	Events.ending_started.emit("broadcast")
