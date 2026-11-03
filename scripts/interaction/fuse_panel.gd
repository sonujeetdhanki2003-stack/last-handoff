class_name FusePanel
extends Interactable
## Puzzle 1: three fuse sockets. Insert fuses one per interaction; when all
## are seated the panel sets flag "fuse_panel_complete" (the master switch needs it).

signal fuse_inserted(count: int)
signal completed

@export var slots := 3

var inserted := 0
var _fuse_meshes: Array[MeshInstance3D] = []
var _slot_lamps: Array[StandardMaterial3D] = []


func _ready() -> void:
	if hold_time <= 0.0:
		hold_time = 0.6
	super._ready()
	_build()
	_refresh()


func _build() -> void:
	var m := ArtMats.local("metal")
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.8, 0.14)
	box.mesh = bm
	box.material_override = m
	add_child(box)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(0.72, 0.82, 0.3)
	cs.shape = shp
	cs.position.z = 0.08
	add_child(cs)
	var lbl := Label3D.new()
	lbl.double_sided = false
	lbl.text = "FUSE PANEL  F-3\nLAB 3 SUPPLY"
	lbl.font_size = 26
	lbl.pixel_size = 0.003
	lbl.position = Vector3(0, 0.3, 0.075)
	lbl.modulate = Color(0.9, 0.85, 0.7)
	add_child(lbl)
	var fuse_mat := StandardMaterial3D.new()
	fuse_mat.albedo_color = Color(0.92, 0.9, 0.85)
	for i in slots:
		var x := -0.2 + i * 0.2
		var sock := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.1, 0.24, 0.03)
		sock.mesh = sm
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.03, 0.03, 0.03)
		sock.material_override = dark
		sock.position = Vector3(x, -0.05, 0.075)
		add_child(sock)
		var fm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.025
		cyl.height = 0.18
		fm.mesh = cyl
		fm.material_override = fuse_mat
		fm.position = Vector3(x, -0.05, 0.1)
		add_child(fm)
		_fuse_meshes.append(fm)
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.02
		lm.height = 0.04
		lamp.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.emission_enabled = true
		lamp.material_override = lmat
		lamp.position = Vector3(x, -0.25, 0.08)
		add_child(lamp)
		_slot_lamps.append(lmat)


func is_complete() -> bool:
	return inserted >= slots


func get_prompt(_a: Node) -> String:
	return "Insert fuse (%d/%d)" % [inserted, slots]


func can_interact(_a: Node) -> bool:
	return not is_complete() and GameState.inventory.has("fuse")


func get_refusal(_a: Node) -> String:
	if is_complete():
		return "All fuses seated"
	return "Needs fuses (%d/%d seated)" % [inserted, slots]


func interact(a: Node) -> void:
	if not can_interact(a):
		return
	if GameState.inventory.remove("fuse", 1):
		inserted += 1
		Sfx.play_at("fuse_insert", global_position)
		GameState.set_flag("fuses_installed", inserted)
		fuse_inserted.emit(inserted)
		_refresh()
		if is_complete():
			GameState.set_flag("fuse_panel_complete")
			Events.toast.emit("Fuse panel repaired. Throw the master switch")
			completed.emit()
		else:
			Events.toast.emit("Fuse seated (%d/%d)" % [inserted, slots])
		super.interact(a)
		store()


func _refresh() -> void:
	for i in slots:
		_fuse_meshes[i].visible = i < inserted
		var c := Color(0.1, 1.0, 0.3) if i < inserted else Color(0.7, 0.05, 0.03)
		_slot_lamps[i].emission = c
		_slot_lamps[i].albedo_color = c * 0.3
		_slot_lamps[i].emission_energy_multiplier = 2.0


func save_state() -> Dictionary:
	return {"inserted": inserted}


func load_state(st: Dictionary) -> void:
	inserted = int(st.get("inserted", 0))
	GameState.set_flag("fuses_installed", inserted)
	if inserted >= slots:
		GameState.set_flag("fuse_panel_complete")
