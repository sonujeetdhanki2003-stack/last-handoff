extends Node3D
## Visual for the power_route decision: the Lab 3 freezer (mode "freezer") or the
## lamp on the lift line (mode "lift"). Dark until the junction feeds it.

@export var mode := "freezer"
var _lamp: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	_lamp = StandardMaterial3D.new()
	_lamp.emission_enabled = true
	if mode == "freezer":
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.3, 1.9, 0.75)
		body.mesh = bm
		body.position.y = 0.95
		body.material_override = ArtMats.local("painted_metal", Color(0.85, 0.88, 0.9))
		add_child(body)
		var door := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(1.2, 1.7, 0.04)
		door.mesh = dm
		door.position = Vector3(0, 0.95, 0.39)
		door.material_override = ArtMats.local("metal", Color(0.7, 0.75, 0.8))
		add_child(door)
		var lbl := Label3D.new()
		lbl.text = "COLD STORE  H-7\n-20 C"
		lbl.font_size = 34
		lbl.pixel_size = 0.003
		lbl.double_sided = false
		lbl.position = Vector3(0, 1.55, 0.42)
		lbl.modulate = Color(0.2, 0.25, 0.3)
		add_child(lbl)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		cs.position.y = 0.95
		sb.add_child(cs)
		add_child(sb)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.04
	lm.height = 0.08
	lamp.mesh = lm
	lamp.material_override = _lamp
	lamp.position = Vector3(0.45, 1.75, 0.42) if mode == "freezer" else Vector3(0, 0.0, 0.08)
	add_child(lamp)
	_light = OmniLight3D.new()
	_light.omni_range = 2.5
	_light.light_energy = 0.0
	_light.position = lamp.position + Vector3(0, 0, 0.2)
	add_child(_light)
	Legacy.decision_made.connect(func(_i, _c): _refresh())
	_refresh()


func _refresh() -> void:
	var on := Legacy.decision("power_route") == mode
	var c := Color(0.35, 0.7, 1.0) if mode == "freezer" else Color(0.3, 1.0, 0.45)
	_lamp.albedo_color = c * (0.3 if on else 0.05)
	_lamp.emission = c
	_lamp.emission_energy_multiplier = 3.0 if on else 0.0
	_light.light_color = c
	_light.light_energy = 0.6 if on else 0.0
