extends SceneTree
func _initialize() -> void:
	var ps: PackedScene = load("res://assets/characters/mannequin/AnimationLibrary_Godot_Standard.gltf")
	var n := ps.instantiate()
	root.add_child(n)
	_print_tree(n, 0)
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	print("libs ", ap.get_animation_library_list(), " ", ap.get_animation_list())
	for a in ["Idle","Walk","Jog_Fwd","Sprint","Crouch_Idle","Crouch_Fwd","Interact","PickUp_Table","Fixing_Kneeling","Idle_Torch","Death01"]:
		var an := ap.get_animation(a)
		print(a, " len=", an.length, " loop=", an.loop_mode, " tracks=", an.get_track_count())
	var an2 := ap.get_animation("Idle_Torch")
	for i in min(6, an2.get_track_count()):
		print("  track ", an2.track_get_path(i), " type ", an2.track_get_type(i))
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	print("skeleton path ", n.get_path_to(sk), " bones ", sk.get_bone_count())
	# measure: in torch anim vs idle, which hand is higher at t=0.5
	for anim in ["Idle_Loop", "Idle_Torch", "Walk_Loop"]:
		ap.play(anim)
		ap.seek(0.5, true)
		sk.force_update_all_bone_transforms() if sk.has_method("force_update_all_bone_transforms") else null
		var l := sk.get_bone_global_pose(sk.find_bone("DEF-hand.L")).origin
		var r := sk.get_bone_global_pose(sk.find_bone("DEF-hand.R")).origin
		var h := sk.get_bone_global_pose(sk.find_bone("DEF-head")).origin
		print(anim, " handL ", l, " handR ", r, " head ", h)
	quit()

func _print_tree(n: Node, d: int) -> void:
	if d > 3: return
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", " pos ", n.position if n is Node3D else "", " rot ", n.rotation if n is Node3D else "", " scale ", n.scale if n is Node3D else "")
	for c in n.get_children():
		_print_tree(c, d + 1)
