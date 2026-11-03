extends SceneTree
## Checks the Blender export against the game's Keeper: same bones, rest pose within a tolerance,
## same meshes, and lists the imported clips.
##   godot --headless --path . -s res://tools/keeper_anim/check_import.gd
func _init():
	var a = load("res://assets/characters/keeper/Keeper.gltf").instantiate()
	var b = load("res://assets/characters/keeper/KeeperAnimated.glb").instantiate()
	var sa: Skeleton3D = a.find_child("GeneralSkeleton", true, false)
	var sb: Skeleton3D = b.find_child("GeneralSkeleton", true, false)
	print("SK ", sa != null, " ", sb != null, " bones ", sa.get_bone_count(), " ", sb.get_bone_count())
	var worst := 0.0
	for i in sa.get_bone_count():
		var n := sa.get_bone_name(i)
		var j := sb.find_bone(n)
		if j < 0:
			print("MISSING ", n); continue
		var ra := sa.get_bone_global_rest(i)
		var rb := sb.get_bone_global_rest(j)
		var d := ra.origin.distance_to(rb.origin) + (ra.basis.get_rotation_quaternion().angle_to(rb.basis.get_rotation_quaternion()))
		if d > worst: worst = d
		if d > 0.01: print("DIFF ", n, " ", ra.origin, rb.origin, " ", d)
	print("WORST ", worst)
	for m in b.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", m.name, " surf ", m.mesh.get_surface_count(), " verts ", m.mesh.surface_get_array_len(0), " path ", b.get_path_to(m))
	for m in a.find_children("*", "MeshInstance3D", true, false):
		print("MESHA ", m.name, " surf ", m.mesh.get_surface_count(), " verts ", m.mesh.surface_get_array_len(0))
	var ap: AnimationPlayer = b.find_child("AnimationPlayer", true, false)
	print("AP ", ap, " root ", ap.root_node if ap else "")
	if ap:
		for n in ap.get_animation_list():
			var an := ap.get_animation(n)
			print("ANIM ", n, " len ", an.length, " loop ", an.loop_mode, " tracks ", an.get_track_count(), " first ", an.track_get_path(0) if an.get_track_count() else "")
	print("TREE ", b.get_child_count(), " ", b.get_children())
	quit()
