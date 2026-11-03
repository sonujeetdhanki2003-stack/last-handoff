extends Node
func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is Skeleton3D: extra = " bones=%d first=%s" % [n.get_bone_count(), n.get_bone_name(0)]
	if n is MeshInstance3D: extra = " skin=%s skel=%s surf=%d aabb=%s" % [str(n.skin != null), n.skeleton, n.mesh.get_surface_count(), n.get_aabb()]
	print("  ".repeat(d), n.name, " <", n.get_class(), ">", extra, " unique=", n.is_unique_name_in_owner())
	for c in n.get_children(): _dump(c, d + 1)
func _ready() -> void:
	for p in ["res://assets/characters/explorer/Explorer.gltf", "res://assets/characters/mannequin/AnimationLibrary_Godot_Standard.gltf"]:
		var s: Node = load(p).instantiate()
		_dump(s, 0)
		var ap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var a := ap.get_animation("Walk")
			print("Walk tracks ", a.get_track_count())
			for i in mini(6, a.get_track_count()): print("   ", a.track_get_path(i), " ", a.track_get_type(i))
		s.free()
	get_tree().quit(0)
