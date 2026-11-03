class_name Sway
extends Node3D
## Gentle pendulum sway for dangling cables and hanging lamps. Pivot = this node.

@export var amplitude_deg := 6.0
@export var period := 3.2
@export var phase := 0.0
@export var gust := 0.35   ## random extra swing now and then

var _t := 0.0
var _g := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_t = phase


func _process(delta: float) -> void:
	_t += delta
	if _rng.randf() < delta * 0.15:
		_g = _rng.randf_range(0.0, gust)
	_g = move_toward(_g, 0.0, delta * 0.08)
	var a := deg_to_rad(amplitude_deg) * (1.0 + _g)
	rotation.x = sin(_t * TAU / period) * a
	rotation.z = sin(_t * TAU / (period * 1.37) + 1.3) * a * 0.6
