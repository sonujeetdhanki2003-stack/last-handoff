class_name TextNote
extends Interactable
## A readable note whose text comes from the chain (handoff notes, wall notes).

@export var title := "NOTE"
@export_multiline var body := ""
@export var verb := "Read"
@export var box_size := Vector3(0.36, 0.1, 0.3)


func _ready() -> void:
	solid = false
	super._ready()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	cs.shape = bs
	add_child(cs)


func get_prompt(_a: Node) -> String:
	return "%s  -  %s" % [verb, title.capitalize()]


func interact(actor: Node) -> void:
	Events.show_note.emit(title, body)
	GameState.set_flag("read_" + name)
	super.interact(actor)
