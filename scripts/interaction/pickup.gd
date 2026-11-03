class_name Pickup
extends Interactable
## World item. Interact to put it in the inventory. Builds a simple visual
## from the item type when the scene has no "Visual" child.

@export var item_id := "battery"
@export var quantity := 1
@export var spin := false

var _visual: Node3D
var _t := 0.0


func _ready() -> void:
	solid = false
	super._ready()
	if GameState.get_world(persist_id).get("taken", false):
		queue_free()
		return
	if get_node_or_null("Visual") == null:
		_visual = PickupVisuals.build(item_id)
		_visual.name = "Visual"
		add_child(_visual)
	else:
		_visual = get_node("Visual")
	if get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var sh := SphereShape3D.new()
		sh.radius = 0.15
		cs.shape = sh
		cs.position.y = 0.05
		add_child(cs)


func _process(delta: float) -> void:
	_t += delta
	if spin and _visual:
		_visual.rotation.y += delta * 0.8


func get_prompt(_a: Node) -> String:
	var n := ItemDB.display_name(item_id)
	if quantity > 1:
		n += " x%d" % quantity
	return "Take " + n


func can_interact(_a: Node) -> bool:
	return GameState.inventory.can_add(item_id, 1)


func get_refusal(_a: Node) -> String:
	return "Inventory full"


func interact(actor: Node) -> void:
	var left := GameState.inventory.add(item_id, quantity)
	var got := quantity - left
	if got <= 0:
		Events.interaction_feedback.emit("Inventory full")
		return
	Events.toast.emit("+ %s%s" % [ItemDB.display_name(item_id), (" x%d" % got) if got > 1 else ""])
	if ItemDB.get_def(item_id)["kind"] == "document":
		var n := Notes.get_note(item_id)
		Events.show_note.emit(n["title"], n["body"])
		if item_id == "note_code":
			GameState.set_flag("code_read")
	if actor and actor.has_method("play_pickup"):
		actor.play_pickup(global_position)
	super.interact(actor)
	quantity = left
	if left <= 0:
		if persist_id != "":
			GameState.set_world(persist_id, {"taken": true})
		queue_free()
