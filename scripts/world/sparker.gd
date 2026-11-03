class_name Sparker
extends Node3D
## A shorting panel: every few seconds it spits a burst of sparks with a blue-white
## flash and a crackle. Only sparks while `circuit` is powered ("" = always).

@export var circuit := ""
@export var min_gap := 2.5
@export var max_gap := 7.0

var _particles: GPUParticles3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _t := 1.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_particles = GPUParticles3D.new()
	_particles.amount = 40
	_particles.lifetime = 0.7
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.emitting = false
	_particles.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.3, 1)
	pm.spread = 55.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.3
	_particles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.emission_energy_multiplier = 8.0
	q.material = m
	_particles.draw_pass_1 = q
	add_child(_particles)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.85, 1.0)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.unit_size = 3.0
	_audio.max_db = -2.0
	if ResourceLoader.exists("res://audio/sfx/spark.wav"):
		_audio.stream = load("res://audio/sfx/spark.wav")
	add_child(_audio)


func _powered() -> bool:
	return circuit == "" or GameState.grid.is_powered(circuit)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 9.0)
	_light.light_energy = _flash * (2.5 + _rng.randf() * 2.0)
	_light.visible = _flash > 0.01
	if not _powered():
		return
	_t -= delta
	if _t <= 0.0:
		_t = _rng.randf_range(min_gap, max_gap)
		burst()


func burst() -> void:
	_particles.restart()
	_particles.emitting = true
	_flash = 1.0
	if _audio.stream:
		_audio.pitch_scale = _rng.randf_range(0.85, 1.2)
		_audio.play()
