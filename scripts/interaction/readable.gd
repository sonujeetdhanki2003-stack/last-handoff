class_name Readable
extends Interactable
## A document you read where it lies (clipboards, posters, pinned sheets): it opens
## in the reader but does not take an inventory slot. Sets flag "doc_<note_id>".

@export var note_id := ""
@export var verb := "Read"
@export var box_size := Vector3(0.3, 0.06, 0.36)


func _ready() -> void:
	solid = false
	super._ready()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	cs.shape = bs
	add_child(cs)


func get_prompt(_a: Node) -> String:
	return "%s  -  %s" % [verb, Notes.get_note(note_id)["title"].capitalize()]


func interact(actor: Node) -> void:
	var n := Notes.get_note(note_id)
	GameState.set_flag("doc_" + note_id)
	if note_id == "doc_rotation":
		GameState.set_flag("code_read")
	Events.show_note.emit(n["title"], n["body"])
	super.interact(actor)
