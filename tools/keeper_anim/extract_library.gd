extends SceneTree
## Pulls the Blender-authored clips out of the imported KeeperAnimated.glb into an
## AnimationLibrary the game loads (res://assets/characters/keeper/keeper_anims.res).
##   godot --headless --path . -s res://tools/keeper_anim/extract_library.gd
## Run after tools/keeper_anim/build_clips.py (Blender) and a `godot --headless --import`.

const LOOPS := ["kp_idle", "kp_stalk", "kp_run", "kp_crawl", "kp_search"]

func _init() -> void:
	var sc: Node = load("res://assets/characters/keeper/KeeperAnimated.glb").instantiate()
	var ap: AnimationPlayer = sc.find_child("AnimationPlayer", true, false)
	var lib := AnimationLibrary.new()
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n).duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if String(n) in LOOPS else Animation.LOOP_NONE
		# keep only bone tracks the Keeper's skeleton has (drop the leaf bones' identity tracks)
		for i in range(a.get_track_count() - 1, -1, -1):
			if a.track_get_key_count(i) == 0:
				a.remove_track(i)
		lib.add_animation(n, a)
		print("clip ", n, " ", snappedf(a.length, 0.001), " s, ", a.get_track_count(), " tracks")
	var err := ResourceSaver.save(lib, "res://assets/characters/keeper/keeper_anims.res", ResourceSaver.FLAG_COMPRESS)
	print("saved keeper_anims.res err=", err)
	sc.free()
	quit(0 if err == OK else 1)
