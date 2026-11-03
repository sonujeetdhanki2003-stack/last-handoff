class_name CrtScreen
extends MeshInstance3D
## Flickering monitor face. The shader animates static, scanlines and rolling
## bars; this script powers it from a circuit and adds random dropouts.

@export var circuit := ""
@export var base_energy := 1.4
@export var glitchy := 0.5

var _rng := RandomNumberGenerator.new()
var _light: OmniLight3D
var _t := 0.0
var _k := 1.0


func _ready() -> void:
	_rng.randomize()
	for c in get_children():
		if c is OmniLight3D:
			_light = c


func _process(delta: float) -> void:
	var on := circuit == "" or GameState.grid.is_powered(circuit)
	_t -= delta
	if _t <= 0.0:
		_t = _rng.randf_range(0.04, 0.6)
		_k = 1.0 if _rng.randf() > glitchy * 0.35 else _rng.randf_range(0.0, 0.5)
	var e := (base_energy * _k) if on else 0.0
	var mat := material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("energy", e)
	if _light:
		_light.light_energy = e * 0.35
		_light.visible = e > 0.01
