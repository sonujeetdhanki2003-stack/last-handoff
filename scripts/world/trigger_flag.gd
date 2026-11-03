class_name TriggerFlag
extends Area3D
## Sets a GameState flag the first time the player walks in.

@export var flag := ""
@export var size := Vector3(2, 2.5, 2)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	if get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		cs.position.y = size.y / 2.0
		add_child(cs)
	body_entered.connect(func(b): if b is Player: GameState.set_flag(flag))
