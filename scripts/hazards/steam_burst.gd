class_name SteamBurst
extends Node3D
## A cracked steam main that blows on a cycle: a rising hiss (warning), then a
## scalding burst across a box in front of it. 30 damage per burst caught in it.
## Readable: you always hear and see the warning before it blows.

@export var size := Vector3(1.6, 2.2, 2.2)     ## danger box, local, centred at +Z size.z/2
@export var idle_time := 5.0
@export var warn_time := 1.3
@export var burst_time := 1.5
@export var damage := 30.0
@export var phase := 0.0

enum P { IDLE, WARN, BURST }
var stage := P.IDLE
var t := 0.0
var _hit_this_burst := false
var _warn_fx: GPUParticles3D
var _burst_fx: GPUParticles3D
var _audio: AudioStreamPlayer3D
var _lamp: StandardMaterial3D


func _ready() -> void:
	add_to_group("hazards")
	t = phase
	_warn_fx = _particles(10, 0.4, 0.8, 0.3)
	_burst_fx = _particles(90, 3.5, 6.0, 1.0)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"SFX"
	_audio.unit_size = 5.0
	add_child(_audio)
	# valve with a red tell-tale that blinks while it builds pressure
	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = Color(0.3, 0.02, 0.0)
	_lamp.emission_enabled = true
	_lamp.emission = Color(1.0, 0.2, 0.05)
	_lamp.emission_energy_multiplier = 0.0
	var l := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	l.mesh = sm
	l.material_override = _lamp
	l.position = Vector3(0.18, 0.12, 0.05)
	add_child(l)


func _particles(amount: int, vmin: float, vmax: float, scale_k: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.4
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.1, 1)
	pm.spread = 18.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.8 * scale_k
	pm.scale_max = 2.2 * scale_k
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.1, Color(1, 1, 1, 0.45))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load("res://assets/textures/smoke_puff.png")
	m.albedo_color = Color(0.9, 0.92, 0.95)
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	if not GameState.threat_enabled:
		return
	step(delta)


func step(delta: float) -> void:
	t += delta
	match stage:
		P.IDLE:
			_lamp.emission_energy_multiplier = 0.0
			if t >= idle_time:
				_enter(P.WARN)
		P.WARN:
			_lamp.emission_energy_multiplier = 3.0 if fmod(t, 0.25) < 0.12 else 0.3
			if t >= warn_time:
				_enter(P.BURST)
		P.BURST:
			_lamp.emission_energy_multiplier = 3.0
			_check_player()
			if t >= burst_time:
				_enter(P.IDLE)


func _enter(s: int) -> void:
	stage = s
	t = 0.0
	_warn_fx.emitting = s == P.WARN
	_burst_fx.emitting = s == P.BURST
	match s:
		P.WARN:
			_play("steam_warn")
		P.BURST:
			_hit_this_burst = false
			_play("steam_burst")
			Events.noise.emit(global_position, 9.0, "steam")


func _play(id: String) -> void:
	_audio.stream = load("res://audio/sfx/%s.wav" % id)
	_audio.play()
	Sfx.caption_for(id, global_position)


func contains(world_pos: Vector3) -> bool:
	var lp := global_transform.affine_inverse() * world_pos
	return absf(lp.x) <= size.x / 2.0 and lp.y >= -1.6 and lp.y <= size.y - 1.6 and lp.z >= 0.0 and lp.z <= size.z


func is_dangerous() -> bool:
	return stage == P.BURST


func _check_player() -> void:
	if _hit_this_burst:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var pl := p as Player
		if pl and not pl.dead and not pl.hidden_in and contains(pl.global_position + Vector3.UP * 0.9):
			_hit_this_burst = true
			pl.hurt(damage, "steam")
			var push := global_transform.basis.z
			push.y = 0
			pl.velocity += push.normalized() * 4.0
