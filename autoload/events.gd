extends Node
## Global signal bus for decoupled UI <-> world communication.

signal toast(text: String)
signal show_note(title: String, body: String)
signal open_keypad(keypad: Node)
signal open_inventory()
signal interaction_feedback(text: String)  # short refusal line ("Needs a keycard")
signal expedition_ended(reason: String)
signal player_spawned(player: Node)
signal ui_modal_changed(open: bool)
signal tape_started(title: String, length: float)
signal tape_finished()
# Phase 4
signal noise(pos: Vector3, radius: float, source: String)   ## the Keeper listens to these
signal player_hurt(amount: float, cause: String)
signal player_died(cause: String)
signal open_choice(title: String, body: String, options: Array, callback: Callable)
signal area_entered(area: String)
signal keeper_state(state: String)
signal ending_started(id: String)

var modal_open := false

func set_modal(open: bool) -> void:
	modal_open = open
	ui_modal_changed.emit(open)
