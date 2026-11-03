class_name Spinner
extends Node3D
## Spins around a local axis (fan blades, flywheels). With a circuit set, it
## spools up when that circuit is powered and winds down when it is cut.

@export var axis := Vector3.FORWARD
@export var speed := 6.0          ## radians per second at full power
@export var idle_speed := 0.0     ## speed when unpowered (e.g. a fan turning in a draught)
@export var circuit := ""
@export var spool_time := 2.5

var _cur := 0.0


func _ready() -> void:
	_cur = _target()


func _target() -> float:
	if circuit == "" or GameState.grid.is_powered(circuit):
		return speed
	return idle_speed


func _process(delta: float) -> void:
	_cur = move_toward(_cur, _target(), delta * maxf(speed, 0.1) / maxf(spool_time, 0.01))
	if absf(_cur) > 0.0001:
		rotate_object_local(axis.normalized(), _cur * delta)
