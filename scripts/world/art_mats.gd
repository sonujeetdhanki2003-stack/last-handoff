class_name ArtMats
extends RefCounted
## Shared textured materials (saved by tools/build_scenes.gd) for script-built
## interactables. `local()` switches to object-space triplanar so textures stay
## glued to moving parts (door panels, levers).

static func local(n: String, tint := Color.WHITE) -> Material:
	var p := "res://assets/materials/%s.tres" % n
	if not ResourceLoader.exists(p):
		var f := StandardMaterial3D.new()
		f.albedo_color = Color(0.3, 0.3, 0.3)
		return f
	var m: Material = load(p).duplicate()
	if m is StandardMaterial3D:
		(m as StandardMaterial3D).uv1_world_triplanar = false
		(m as StandardMaterial3D).uv1_scale = Vector3.ONE * 1.6
		(m as StandardMaterial3D).albedo_color *= tint
	return m
