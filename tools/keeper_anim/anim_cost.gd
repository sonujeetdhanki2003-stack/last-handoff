extends Node
## Animation CPU cost of the Keeper (v1.1 AnimationTree + head look-at vs the v1.0-style
## AnimationPlayer clip + full procedural poser). 12 Keepers, 600 frames each mode, headless.
##   godot --headless --path . res://tools/keeper_anim/anim_cost.tscn

func _ready() -> void:
	_go()

func _go() -> void:
	await get_tree().process_frame
	GameState.threat_enabled = true
	var ks := []
	for i in 12:
		var k: Keeper = load("res://scripts/threat/keeper.gd").new()
		k.think = false
		add_child(k)
		k.global_position = Vector3(i * 2.0, 0, 0)
		ks.append(k)
	await get_tree().process_frame
	for mode in ["none", "v11_tree", "v10_style"]:
		for k in ks:
			k.set_physics_process(false)
			match mode:
				"none":
					k.tree.active = false
					k._anim.stop()
					k.poser.active = false
				"v11_tree":
					k._anim.stop()
					k.tree.active = true
					k.poser.active = true
					k.poser.clip_mode = true
					k.poser.look_weight = 0.8
					k.poser.look_target = Vector3(0, 1.5, 5)
					k.play_clip("kp_run")
				"v10_style":
					k.tree.active = false
					k.poser.active = true
					k.poser.clip_mode = false
					k.poser.reach = 0.6
					k.poser.search = 0.5
					k._anim.play("kp_run")
		for f in 30:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for f in 600:
			await get_tree().process_frame
		var us := float(Time.get_ticks_usec() - t0) / 600.0
		print("COST %-10s %.3f ms/frame for 12 Keepers (%.3f ms each)" % [mode, us / 1000.0, us / 12000.0])
	get_tree().quit()
