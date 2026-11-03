extends Node
## v1.1 baked room AO, step 1 of 3 (Godot side): dumps the built station for Blender.
##   godot --headless --path . res://tools/gfx_blender/export_level.tscn
## Writes tools/gfx_blender/build/level_receivers.json (every architecture box that uses the
## facility_surface shader: node path, global transform, size) and level_occluders.bin
## (float32 triangle soup, world space, of everything else that is opaque and visible).
## Step 2: blender -b -P tools/gfx_blender/bake_level_ao.py ; step 3 happens at load (GfxUpgrade).

const OUTDIR := "res://tools/gfx_blender/build/"

func _ready() -> void:
	GameState.new_expedition(77)
	GameState.threat_enabled = false
	var lvl: Node3D = load("res://scenes/levels/facility_greybox.tscn").instantiate()
	add_child(lvl)
	for i in 3:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	var recv := []
	var tris := PackedFloat32Array()
	var nrecv := 0
	for n in lvl.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			if _is_receiver(mi):
				var xf := mi.global_transform
				recv.append({"path": String(lvl.get_path_to(mi)), "size": _v((mi.mesh as BoxMesh).size),
					"basis": [_v(xf.basis.x), _v(xf.basis.y), _v(xf.basis.z)], "origin": _v(xf.origin),
					"mat": (mi.material_override as Resource).resource_path.get_file().get_basename()})
				nrecv += 1
				continue
			if _transparent(mi):
				continue
			_add(tris, mi.mesh.get_faces(), mi.global_transform)
		elif gi is MultiMeshInstance3D:
			var mmi := gi as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null:
				continue
			var f := mm.mesh.get_faces()
			for i in mm.instance_count:
				_add(tris, f, mmi.global_transform * mm.get_instance_transform(i))
	# receivers are occluders of each other too: Blender adds them itself
	var fj := FileAccess.open(OUTDIR + "level_receivers.json", FileAccess.WRITE)
	fj.store_string(JSON.stringify(recv))
	fj.close()
	var fb := FileAccess.open(OUTDIR + "level_occluders.bin", FileAccess.WRITE)
	fb.store_buffer(tris.to_byte_array())
	fb.close()
	print("EXPORT receivers ", nrecv, " occluder tris ", tris.size() / 9)
	get_tree().quit()


func _is_receiver(mi: MeshInstance3D) -> bool:
	if not (mi.mesh is BoxMesh) or mi.name != "Mesh":
		return false
	var m := mi.material_override as ShaderMaterial
	if m == null or m.shader == null:
		return false
	return m.shader.resource_path.ends_with("facility_surface.gdshader")


func _transparent(mi: MeshInstance3D) -> bool:
	var m := mi.material_override as BaseMaterial3D
	if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return true
	if m and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return true
	return false


func _add(out: PackedFloat32Array, faces: PackedVector3Array, xf: Transform3D) -> void:
	for p in faces:
		var w := xf * p
		out.append(w.x)
		out.append(w.y)
		out.append(w.z)


func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
