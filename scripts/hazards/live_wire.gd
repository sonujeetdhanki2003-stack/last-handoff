class_name LiveWire
extends Node3D
## A cable down in a puddle. While its circuit has power the water is live:
## stepping in it shocks you (35 damage, thrown clear). Sparks and a buzz tell
## you it's live; with the power off it's just a puddle.

@export var circuit := "aux"
@export var radius := 1.1
@export var damage := 35.0

var _cool := 0.0
var _buzz: AudioStreamPlayer3D
var _zap: AudioStreamPlayer3D
var _sparks: GPUParticles3D
var _spark_t := 0.0
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("hazards")
	add_to_group("puddles")
	_buzz = AudioStreamPlayer3D.new()
	_buzz.bus = &"SFX"
	_buzz.unit_size = 2.0
	_buzz.max_distance = 14.0
	_buzz.stream = AudioLoop.make(load("res://audio/sfx/wire_buzz.wav"))
	add_child(_buzz)
	_zap = AudioStreamPlayer3D.new()
	_zap.bus = &"SFX"
	_zap.stream = load("res://audio/sfx/zap.wav")
	add_child(_zap)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.75, 1.0)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.position.y = 0.3
	add_child(_light)
	_sparks = GPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.5
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -9.8, 0)
	_sparks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(0.8, 0.9, 1.0)
	q.material = m
	_sparks.draw_pass_1 = q
	_sparks.position.y = 0.05
	add_child(_sparks)
	GameState.grid.circuit_changed.connect(func(_i, _p): _sync())
	_sync()


func is_live() -> bool:
	return GameState.grid.is_powered(circuit) and GameState.threat_enabled


func _sync() -> void:
	if is_live():
		if not _buzz.playing:
			_buzz.play()
	else:
		_buzz.stop()


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if not is_live():
		_light.light_energy = 0.0
		return
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.6, 2.2)
		_sparks.restart()
		_light.light_energy = 2.5
	_light.light_energy = move_toward(_light.light_energy, 0.15, delta * 10.0)
	if _cool > 0.0:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var pl := p as Player
		if pl and not pl.dead and touches(pl.global_position):
			_cool = 1.0
			_zap.play()
			_sparks.restart()
			_light.light_energy = 6.0
			pl.hurt(damage, "shock")
			var away := pl.global_position - global_position
			away.y = 0
			pl.velocity += away.normalized() * 5.0
			Events.noise.emit(global_position, 8.0, "zap")


func touches(pos: Vector3) -> bool:
	return absf(pos.y - global_position.y) < 0.6 and Vector2(pos.x - global_position.x, pos.z - global_position.z).length() <= radius
