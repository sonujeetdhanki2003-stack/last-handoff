class_name PickupVisuals
extends RefCounted
## Procedural placeholder props for items (Phase 3 swaps in real models).

static func _mat(c: Color, emissive := 0.0, metal := 0.2, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	var c: Color = ItemDB.get_def(id)["color"]
	match id:
		"battery":
			_cyl(root, 0.035, 0.13, Vector3(0, 0.07, 0), _mat(Color(0.12, 0.12, 0.13), 0.0, 0.6, 0.35), Vector3(0, 0, PI / 2))
			_cyl(root, 0.036, 0.05, Vector3(0.03, 0.07, 0), _mat(c, 0.6, 0.3, 0.4), Vector3(0, 0, PI / 2))
		"fuse":
			_cyl(root, 0.025, 0.11, Vector3(0, 0.03, 0), _mat(Color(0.92, 0.9, 0.85), 0.0, 0.0, 0.3), Vector3(0, 0, PI / 2))
			_cyl(root, 0.027, 0.02, Vector3(0.055, 0.03, 0), _mat(Color(0.75, 0.6, 0.3), 0.0, 0.9, 0.3), Vector3(0, 0, PI / 2))
			_cyl(root, 0.027, 0.02, Vector3(-0.055, 0.03, 0), _mat(Color(0.75, 0.6, 0.3), 0.0, 0.9, 0.3), Vector3(0, 0, PI / 2))
			# small glow so a fuse is findable with the flashlight off
			_box(root, Vector3(0.03, 0.005, 0.03), Vector3(0, 0.056, 0), _mat(Color(1.0, 0.55, 0.15), 3.0))
		"keycard_blue":
			_box(root, Vector3(0.086, 0.004, 0.054), Vector3(0, 0.004, 0), _mat(c, 0.5, 0.1, 0.4))
			_box(root, Vector3(0.03, 0.005, 0.02), Vector3(-0.02, 0.006, 0.0), _mat(Color(0.9, 0.8, 0.3), 0.0, 0.9, 0.2))
		"note_code", "note_handoff":
			var p := _box(root, Vector3(0.21, 0.003, 0.29), Vector3(0, 0.003, 0), _mat(c, 0.15, 0.0, 0.9))
			p.rotation.y = 0.25
			_box(root, Vector3(0.15, 0.004, 0.012), Vector3(0, 0.005, -0.06), _mat(Color(0.2, 0.2, 0.25), 0.0, 0.0, 0.9)).rotation.y = 0.25
			_box(root, Vector3(0.12, 0.004, 0.012), Vector3(0.01, 0.005, -0.02), _mat(Color(0.2, 0.2, 0.25), 0.0, 0.0, 0.9)).rotation.y = 0.25
		"research_drive":
			_box(root, Vector3(0.16, 0.035, 0.1), Vector3(0, 0.02, 0), _mat(Color(0.08, 0.09, 0.1), 0.0, 0.7, 0.3))
			_box(root, Vector3(0.05, 0.006, 0.006), Vector3(0.03, 0.04, 0.035), _mat(c, 4.0))
		_:
			_box(root, Vector3(0.15, 0.15, 0.15), Vector3(0, 0.075, 0), _mat(c))
	return root
