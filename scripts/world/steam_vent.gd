class_name SteamVent
extends Node3D
## A leaking pipe joint: soft steam puffs drifting out along -Z (local) with a hiss.

@export var strength := 1.0

func _ready() -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 2.6
	p.preprocess = 3.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.2, -1)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.6 * strength
	pm.initial_velocity_max = 1.3 * strength
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.25))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.12, Color(1, 1, 1, 0.22))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load("res://assets/textures/smoke_puff.png")
	m.albedo_color = Color(0.85, 0.87, 0.9)
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	var a := AudioStreamPlayer3D.new()
	a.bus = &"Ambience"
	a.unit_size = 2.0
	a.max_db = -6.0
	if ResourceLoader.exists("res://audio/ambience/steam_hiss.wav"):
		a.stream = load("res://audio/ambience/steam_hiss.wav")
		a.autoplay = true
	add_child(a)
