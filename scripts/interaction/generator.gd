class_name Generator
extends Interactable
## Emergency diesel generator. Hold Interact to crank; it powers `circuit_id`.

signal started

@export var circuit_id := "aux"

var running := false
var _body: Node3D
var _lamp: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _hum: AudioStreamPlayer3D
var _t := 0.0


func _ready() -> void:
	if hold_time <= 0.0:
		hold_time = 2.0
	super._ready()
	_build()
	if GameState.grid.is_on(circuit_id):
		_set_running(true, false)


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var metal := ArtMats.local("green_metal", Color(0.85, 0.9, 0.7))
	var dark := ArtMats.local("rusty", Color(0.45, 0.45, 0.45))
	# Phase 4 art pass: a horizontal finned engine drum on a tube skid instead of a crate
	var drum := MeshInstance3D.new()
	var dcm := CylinderMesh.new()
	dcm.top_radius = 0.4
	dcm.bottom_radius = 0.4
	dcm.height = 1.35
	dcm.radial_segments = 28
	drum.mesh = dcm
	drum.rotation.z = PI / 2
	drum.position = Vector3(0, 0.6, -0.02)
	drum.material_override = metal
	_body.add_child(drum)
	for sx in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		sm.radial_segments = 24
		sm.rings = 10
		cap.mesh = sm
		cap.scale = Vector3(0.28, 1.0, 1.0)
		cap.position = Vector3(0.675 * sx, 0.6, -0.02)
		cap.material_override = metal
		_body.add_child(cap)
	for k in 7:
		var rib := MeshInstance3D.new()
		var tr := TorusMesh.new()
		tr.inner_radius = 0.39
		tr.outer_radius = 0.435
		tr.rings = 28
		rib.mesh = tr
		rib.rotation.z = PI / 2
		rib.position = Vector3(-0.54 + k * 0.18, 0.6, -0.02)
		rib.material_override = dark
		_body.add_child(rib)
	# skid: two rails + cross members
	for sz in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = 0.04
		rc.bottom_radius = 0.04
		rc.height = 1.8
		rail.mesh = rc
		rail.rotation.z = PI / 2
		rail.position = Vector3(0, 0.05, 0.36 * sz)
		rail.material_override = dark
		_body.add_child(rail)
	for k in 3:
		_add_box(_body, Vector3(0.09, 0.08, 0.8), Vector3(-0.6 + k * 0.6, 0.06, 0), dark)
		_add_box(_body, Vector3(0.07, 0.22, 0.07), Vector3(-0.6 + k * 0.6, 0.2, 0.25), dark)
		_add_box(_body, Vector3(0.07, 0.22, 0.07), Vector3(-0.6 + k * 0.6, 0.2, -0.29), dark)
	# control box on the front, air filter can on top
	_add_box(_body, Vector3(0.64, 0.36, 0.12), Vector3(-0.05, 0.85, 0.39), metal)
	_add_box(_body, Vector3(0.68, 0.03, 0.15), Vector3(-0.05, 1.04, 0.38), dark)
	var filt := MeshInstance3D.new()
	var fcm := CylinderMesh.new()
	fcm.top_radius = 0.17
	fcm.bottom_radius = 0.19
	fcm.height = 0.22
	filt.mesh = fcm
	filt.position = Vector3(-0.5, 1.08, -0.05)
	filt.material_override = dark
	_body.add_child(filt)
	var ex := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.07
	cm.height = 0.9
	ex.mesh = cm
	ex.material_override = dark
	ex.position = Vector3(0.55, 1.35, -0.3)
	_body.add_child(ex)
	# crank wheel on the front
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.14
	wheel.mesh = tm
	wheel.rotation.x = PI / 2
	wheel.position = Vector3(0.5, 0.62, 0.43)
	wheel.material_override = dark
	_body.add_child(wheel)
	# exposed flywheel + belt guard on the side: spins up when the generator runs
	var fly := Spinner.new()
	fly.axis = Vector3(1, 0, 0)
	fly.speed = 14.0
	fly.circuit = circuit_id
	fly.spool_time = 1.8
	fly.position = Vector3(0.86, 0.62, 0.0)
	_body.add_child(fly)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.32
	dm.bottom_radius = 0.32
	dm.height = 0.06
	disc.mesh = dm
	disc.rotation.z = PI / 2
	disc.material_override = dark
	fly.add_child(disc)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.07, 0.56, 0.05)
		spoke.mesh = sb
		spoke.position.x = 0.04
		spoke.rotation.x = k * PI / 4.0
		spoke.material_override = metal
		fly.add_child(spoke)
	# radiator grille and fuel tank on top
	# radiator on the far end
	_add_box(_body, Vector3(0.1, 0.72, 0.78), Vector3(-0.84, 0.55, -0.02), dark)
	for k in 9:
		_add_box(_body, Vector3(0.03, 0.62, 0.035), Vector3(-0.9, 0.55, -0.38 + k * 0.09), metal)
	var tank := MeshInstance3D.new()
	var tm2 := CylinderMesh.new()
	tm2.top_radius = 0.2
	tm2.bottom_radius = 0.2
	tm2.height = 0.9
	tank.mesh = tm2
	tank.rotation.z = PI / 2
	tank.position = Vector3(0.25, 1.17, 0.05)
	tank.material_override = metal
	_body.add_child(tank)
	for k in 2:
		var g := MeshInstance3D.new()
		var gm := CylinderMesh.new()
		gm.top_radius = 0.045
		gm.bottom_radius = 0.045
		gm.height = 0.02
		g.mesh = gm
		g.rotation.x = PI / 2
		g.position = Vector3(-0.05 + k * 0.14, 0.85, 0.46)
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.85, 0.82, 0.7)
		g.material_override = gmat
		_body.add_child(g)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.8, 0.05, 0.02)
	_lamp_mat.emission_energy_multiplier = 1.5
	var lamp := _add_box(_body, Vector3(0.08, 0.08, 0.04), Vector3(-0.3, 0.85, 0.46), _lamp_mat)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1, 0.3, 0.1)
	_lamp.light_energy = 0.25
	_lamp.omni_range = 1.6
	_lamp.position = lamp.position + Vector3(0, 0, 0.15)
	_body.add_child(_lamp)
	var l := Label3D.new()
	l.double_sided = false
	l.text = "AUX GEN-2"
	l.font_size = 36
	l.pixel_size = 0.004
	l.position = Vector3(0, 0.95, 0.46)
	l.modulate = Color(0.95, 0.9, 0.7)
	l.double_sided = false
	_body.add_child(l)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 1.2, 1.0)
	cs.shape = bs
	cs.position.y = 0.6
	add_child(cs)
	_hum = AudioStreamPlayer3D.new()
	_hum.bus = &"Ambience"
	_hum.unit_size = 4.0
	var s := load("res://audio/sfx/generator_loop.wav")
	if s:
		_hum.stream = s
	add_child(_hum)


func _add_box(p: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	p.add_child(mi)
	return mi


func _process(delta: float) -> void:
	if running:
		_t += delta
		_body.position = Vector3(sin(_t * 61.0), 0, cos(_t * 47.0)) * 0.004


func get_prompt(_a: Node) -> String:
	return "Hold to crank the generator"


func can_interact(_a: Node) -> bool:
	return not running


func get_refusal(_a: Node) -> String:
	return "Running" if running else ""


func interact(a: Node) -> void:
	if running:
		return
	_set_running(true, true)
	super.interact(a)
	store()


func _set_running(on: bool, announce: bool) -> void:
	running = on
	GameState.grid.set_on(circuit_id, on)
	var c := Color(0.1, 1.0, 0.3) if on else Color(0.8, 0.05, 0.02)
	_lamp_mat.emission = c
	_lamp.light_color = c
	if on and _hum.stream:
		_hum.play()
	if announce:
		Sfx.play_at("gen_start", global_position)
		Events.toast.emit("Generator running. Emergency power restored")
		started.emit()
		if GameState.chain_mode or GameState.threat_enabled:
			get_tree().create_timer(4.0).timeout.connect(func(): Sfx.play_pa("pa_generator"))


func save_state() -> Dictionary:
	return {"running": running}


func load_state(st: Dictionary) -> void:
	if st.get("running", false):
		GameState.grid.set_on(circuit_id, true)
