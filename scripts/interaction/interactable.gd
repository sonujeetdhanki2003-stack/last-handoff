class_name Interactable
extends StaticBody3D
## Base for anything the player can aim at and press Interact on.
## The player's InteractionRay calls: get_prompt, can_interact, get_refusal,
## get_hold_time and interact. Override what you need.

signal interacted(actor: Node)

const LAYER_WORLD := 1
const LAYER_INTERACT := 4  # physics layer 3

@export var prompt := "Use"
@export var hold_time := 0.0
@export var required_circuit := ""      ## needs this power circuit to work
@export var no_power_text := "No power"
@export var persist_id := ""            ## key into GameState.world (Phase 4 persistence)
@export var solid := true               ## also blocks the player (world layer)


func _ready() -> void:
	collision_layer = (LAYER_WORLD if solid else 0) | LAYER_INTERACT
	collision_mask = 0
	add_to_group("interactable")
	if persist_id != "":
		add_to_group("persistent")
		var st := GameState.get_world(persist_id)
		if not st.is_empty():
			load_state(st)


func is_powered() -> bool:
	return required_circuit == "" or GameState.grid.is_powered(required_circuit)


func get_prompt(_actor: Node) -> String:
	return prompt


func can_interact(_actor: Node) -> bool:
	return is_powered()


func get_refusal(_actor: Node) -> String:
	if not is_powered():
		return no_power_text
	return ""


func get_hold_time(_actor: Node) -> float:
	return hold_time


func interact(actor: Node) -> void:
	interacted.emit(actor)


# Persistence hooks ------------------------------------------------------------
func save_state() -> Dictionary:
	return {}


func load_state(_state: Dictionary) -> void:
	pass


func store() -> void:
	if persist_id != "":
		GameState.set_world(persist_id, save_state())
