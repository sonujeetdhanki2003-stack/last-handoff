class_name InteractProxy
extends AnimatableBody3D
## Moving collider (door panel, lever handle) that forwards interaction to a target.

@export var target_path: NodePath
var target: Node


func _ready() -> void:
	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	add_to_group("interactable")


func get_prompt(a: Node) -> String:
	return target.get_prompt(a) if target else ""


func can_interact(a: Node) -> bool:
	return target != null and target.can_interact(a)


func get_refusal(a: Node) -> String:
	return target.get_refusal(a) if target else ""


func get_hold_time(a: Node) -> float:
	return target.get_hold_time(a) if target else 0.0


func interact(a: Node) -> void:
	if target:
		target.interact(a)
