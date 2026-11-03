extends Node
## Screenshot / automation harness. Inactive unless the game is started with
## user args after `--`, e.g.
##   godot --path . -- --shot=menu --out=/tmp/menu.png
## Scenarios set up a situation, wait for it to settle, save a PNG and quit.

var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if has("quality"):
		Settings.set_value("video", "quality", int(get_arg("quality")), false)
	if has("nosubs"):
		Settings.set_value("access", "subtitles", false, false)
		Settings.set_value("access", "captions", false, false)
	if has("shot"):
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run_shot.call_deferred(get_arg("shot"), get_arg("out", "/tmp/shot.png"))


func has(k: String) -> bool:
	return args.has(k)


func get_arg(k: String, d := "") -> String:
	return args.get(k, d)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		if has("debug"):
			print("frame ", Engine.get_process_frames(), " t=", Time.get_ticks_msec())


func _game() -> Node:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(3)
	while get_tree().current_scene == null or get_tree().current_scene.name != "Game":
		await get_tree().process_frame
	await _frames(2)
	var sc := get_tree().current_scene
	if get_arg("hide", "") != "":
		for n in get_arg("hide", "").split(","):
			for x in sc.find_children(n, "", true, false):
				x.queue_free()
	if get_arg("fastshadow", "") != "":
		# software-renderer screenshots: the animated player would force every
		# shadowed omni cube to re-render each frame (seconds per frame on CPU)
		get_viewport().positional_shadow_atlas_size = 2048
		RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
		for x in sc.find_children("*", "OmniLight3D", true, false):
			(x as Light3D).shadow_enabled = false
	if get_arg("nofog", "") != "":
		for x in sc.find_children("*", "WorldEnvironment", true, false):
			(x as WorldEnvironment).environment.volumetric_fog_enabled = false
	if get_arg("nolights", "") != "":
		for x in sc.find_children("*", "OmniLight3D", true, false):
			if not (x as Node).get_path().get_concatenated_names().contains("Player"):
				x.queue_free()
	if get_arg("noshadow", "") != "":
		for x in sc.find_children("*", "Light3D", true, false):
			(x as Light3D).shadow_enabled = false
	return sc


func _place(g: Node, pos: Vector3, yaw: float, pitch := -12.0, face := true) -> void:
	var p: Player = g.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.cam.set_view(yaw, pitch)
	p.cam.global_position = pos + Vector3.UP * 1.55
	if face:
		p.face_yaw_degrees(yaw)


func _power(all_lab := false) -> void:
	GameState.grid.set_on("aux", true)
	GameState.grid.set_on("corridor_lights", true)
	if all_lab:
		GameState.set_flag("fuse_panel_complete")
		GameState.grid.set_on("lab", true)


## A chain with history for screenshots: three members before you, marks, notes,
## one decision taken.
func demo_chain(n_members := 3) -> void:
	Legacy.use_path("user://shot_chain.json")
	var msgs := [["It hunts by sound. Crouch.", "second locker in security sticks"], ["Light drives it back. Not for long.", ""], ["The generator is fixed. Keep it running.", "I heard it in the vents. Go fast."]]
	var ends := ["died", "gave_up", "died"]
	var syms := ["x", "circle", "arrow"]
	var spots := [Vector3(0.4, 0.0, -9.5), Vector3(5.2, 0.0, -6.0), Vector3(-1.3, 0.0, 3.2)]
	var items := ["battery", "fuse", "medkit"]
	for i in n_members:
		Legacy.begin_expedition()
		GameState.elapsed = 300.0 + i * 140.0
		GameState.inventory.add(items[i])
		GameState.inventory.add("battery")
		GameState.note_area(["corridor", "security", "storage"][i])
		if i == 1:
			GameState.set_world("door_shaft", {"open": true})
			GameState.set_world("generator_aux", {"running": true})
		if i == 2:
			Legacy.decide("power_route", "freezer")
		Legacy.end_expedition(ends[i], spots[i], GameState.deepest)
		Legacy.commit_handoff(msgs[i][0], msgs[i][1], items[i], syms[i])
	GameState.flags.clear()


func _run_shot(name_: String, out: String) -> void:
	await _frames(5)
	if has("chain"):
		demo_chain(int(get_arg("chain", "3")))
		Legacy.begin_expedition()
	var settle := int(get_arg("frames", "90"))
	match name_:
		"menu":
			await _frames(settle)
		"menu_howto", "menu_achievements", "menu_chapters":   # v1.2 screens
			var m := get_tree().current_scene
			if has("demo_progress"):
				Progress.use_path("user://shot_progress.json")
				for id in ["descent", "generator", "lab_power", "repel", "hide", "engineer", "tapes"]:
					Progress.unlock(id, true)
				for c in ["descent", "power", "lab"]:
					Progress.open_chapter(c, true)
			await _frames(5)
			m.call("open_" + name_.trim_prefix("menu_"))
			if has("page"):
				var sc: Node = m.get_node_or_null("HowToPlay")
				for x in m.find_children("*", "HowToPlayScreen", true, false):
					sc = x
				if sc and sc.has_method("set_page"):
					sc.set_page(int(get_arg("page")))
			await _frames(settle)
		"menu_settings":
			var m := get_tree().current_scene
			await _frames(5)
			m.open_settings()
			m._settings.set_tab(int(get_arg("tab", "0")), false)
			m._settings.focus_first()
			if has("focus"):
				for i in int(get_arg("focus")):
					var f: Array = m._settings.focusables()
					(f[(i + 1) % f.size()] as Control).grab_focus()
			await _frames(settle)
		"menu_history":
			var m := get_tree().current_scene
			await _frames(5)
			m.open_history()
			await _frames(settle)
		"brightness":
			var m := get_tree().current_scene
			await _frames(5)
			m.open_brightness(false)
			await _frames(settle)
		"titlecard":
			var g: Node = await _game()
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			TitleCard.time_scale = 40.0
			g.hud.visible = false
			Ux.show_title_card("Expedition 11", "Priya Rao", "HALDEN DEEP  //  LEVEL B2", 100000.0, true)
			await _frames(settle)
		"intro":
			GameState.play_intro = true
			IntroDirector.time_scale = float(get_arg("speed", "1"))
			var g: Node = await _game()
			await _frames(settle)
		"pause":
			var g: Node = await _game()
			GameState.inventory.add("battery", 2)
			GameState.inventory.add("medkit", 1)
			GameState.elapsed = 312.0
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			await _frames(10)
			g.get_node("PauseMenu").open()
			await _frames(settle)
		"hud":
			var g: Node = await _game()
			_power()
			GameState.inventory.add("battery", 2)
			g.player.flashlight.set_on(true)
			g.player.vitals.health = 62.0
			g.player.vitals.stamina = 0.55
			_place(g, Vector3(float(get_arg("x", "0.3")), 0.05, float(get_arg("z", "-4.0"))), float(get_arg("yaw", "8")), -6.0)
			await _frames(5)
			g.hud.show_objective(60.0)
			g.hud._wake_device(60.0)
			g.hud.show_area("corridor")
			if has("sub"):
				Ux.subtitle("Gen-two maintenance, Brandt. Note for whoever pulls the next shift.", "Joel Brandt", 60.0, "speech")
				Ux.subtitle("metal banging in the vents (left)", "", 60.0, "sound")
			if has("debug"):
				g.debug_overlay.set_on(true)
			await _frames(settle)
		"start":
			var g: Node = await _game()
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			await _frames(settle)
		"crate":
			var g: Node = await _game()
			g.player.flashlight.set_on(true)
			_place(g, Vector3(-1.3, 0.05, 4.4), 40.0, -30.0)
			await _frames(settle)
		"dark":
			var g: Node = await _game()
			g.player.flashlight.set_on(true)
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			_place(g, Vector3(0.3, 0.05, -1.5), 0.0, -6.0)
			await _frames(settle)
		"dark_off":
			var g: Node = await _game()
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			_place(g, Vector3(0.3, 0.05, -1.5), 0.0, -6.0)
			await _frames(settle)
		"generator":
			var g: Node = await _game()
			g.get_node("Level/Interactables/DoorGenerator").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(-3.2, 0.05, -3.2), 65.0, -14.0)
			await _frames(settle)
		"prompt":
			var g: Node = await _game()
			g.get_node("Level/Interactables/DoorGenerator").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			GameState.grid.set_on("corridor_lights", true)
			_place(g, Vector3(-3.7, 0.05, -4.3), 75.0, -18.0)
			await _frames(settle)
		"powered":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			_place(g, Vector3(0.0, 0.05, -1.0), 0.0, -5.0)
			await _frames(settle)
		"inventory":
			var g: Node = await _game()
			for it in [["battery", 2], ["fuse", 2], ["keycard_blue", 1], ["note_handoff", 1], ["note_code", 1]]:
				GameState.inventory.add(it[0], it[1])
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			await _frames(20)
			g.hud.open_inventory()
			g.hud._select(1)
			await _frames(settle)
		"note":
			var g: Node = await _game()
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			await _frames(20)
			var n := Notes.get_note("note_handoff")
			g.hud.open_note(n["title"], n["body"])
			await _frames(settle)
		"keypad":
			var g: Node = await _game()
			_power(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(0.6, 0.05, -20.3), 10.0, -10.0)
			await _frames(30)
			g.hud.open_keypad(g.get_node("Level/Interactables/LabKeypad"))
			g.hud._keypad_press("4")
			g.hud._keypad_press("1")
			await _frames(settle)
		"fusepanel":
			var g: Node = await _game()
			_power()
			GameState.inventory.add("fuse", 2)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(0.2, 0.05, -16.2), -105.0, -8.0)
			await _frames(settle)
		"lab":
			var g: Node = await _game()
			_power(true)
			var d: Door = g.get_node("Level/Interactables/DoorLab")
			d.unlock_code()
			d.set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(-1.0, 0.05, -24.5), 10.0, -8.0)
			await _frames(settle)
		"crouch":
			var g: Node = await _game()
			_power()
			g.player.toggle_crouch()
			g.player.flashlight.set_on(true)
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			_place(g, Vector3(0.0, 0.05, -4.0), 160.0, -10.0, false)
			g.player.face_yaw_degrees(-20.0)
			await _frames(settle)
		"wallhug":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			_place(g, Vector3(1.25, 0.05, -10.0), 90.0, -5.0)
			await _frames(settle)
		"hero":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(0.2, 0.05, -3.2), float(get_arg("yaw", "200")), -8.0, false)
			g.player.face_yaw_degrees(float(get_arg("face", "-20")))
			await _frames(settle)
		"security":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorSecurity").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(3.0, 0.05, -5.6), float(get_arg("yaw", "-35")), -14.0)
			await _frames(settle)
		"storage":
			var g: Node = await _game()
			_power()
			var d: Door = g.get_node("Level/Interactables/DoorStorage")
			d.set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(-2.4, 0.05, -14.2), 125.0, -16.0)
			await _frames(settle)
		"lab_wide":
			var g: Node = await _game()
			_power(true)
			var d: Door = g.get_node("Level/Interactables/DoorLab")
			d.unlock_code()
			d.set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(0.6, 0.05, -23.4), float(get_arg("yaw", "-20")), -8.0)
			await _frames(settle)
		"shaft":
			var g: Node = await _game()
			g.player.flashlight.set_on(true)
			_place(g, Vector3(-0.8, 0.05, 2.0), float(get_arg("yaw", "170")), float(get_arg("pitch", "4")))
			await _frames(settle)
		"gen_on":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorGenerator").set_open_immediate(true)
			g.get_node("Level/Interactables/Generator")._set_running(true, false)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(float(get_arg("px", "-2.6")), 0.05, float(get_arg("pz", "-4.2"))), float(get_arg("yaw", "75")), float(get_arg("pitch", "-12")))
			await _frames(settle)
		"threat":
			var g: Node = await _game()
			GameState.grid.set_on("aux", true)
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = Vector3(float(get_arg("kx", "-0.2")), 0.0, float(get_arg("kz", "-8.6")))
			k.look_at_flat(Vector3(0.3, 0, -3.0))
			k.set_state(Keeper.S.CHASE)
			k.velocity = Vector3(0, 0, 2.0)
			_place(g, Vector3(0.45, 0.05, float(get_arg("pz", "-3.6"))), float(get_arg("yaw", "8")), float(get_arg("pitch", "-4")))
			await _frames(settle)
		"keeper_close":
			var g: Node = await _game()
			GameState.grid.set_on("aux", true)
			GameState.grid.set_on("corridor_lights", true)
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = Vector3(-0.3, 0.0, float(get_arg("kz", "-6.2")))
			k.look_at_flat(Vector3(0.3, 0, -2.0))
			k.set_state(Keeper.S.WAIT_LIGHT)
			_place(g, Vector3(0.5, 0.05, -2.8), float(get_arg("yaw", "10")), -2.0)
			await _frames(settle)
		"keeper_portrait":
			var g: Node = await _game()
			GameState.grid.set_on("aux", true)
			GameState.grid.set_on("corridor_lights", true)
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = Vector3(float(get_arg("kx", "0.0")), 0.0, float(get_arg("kz", "-9.0")))
			k.look_at_flat(k.global_position + Vector3(0, 0, 5))
			k.set_state(int(get_arg("state", str(Keeper.S.WAIT_LIGHT))))
			_place(g, Vector3(0.6, 0.05, 4.4), 15.0, -8.0)
			g.hud.visible = false
			var cam := Camera3D.new()
			g.add_child(cam)
			var dist := float(get_arg("dist", "2.6"))
			var ang := deg_to_rad(float(get_arg("ang", "20")))
			cam.global_position = k.global_position + Vector3(sin(ang) * dist, float(get_arg("camy", "1.45")), cos(ang) * dist)
			cam.look_at(k.global_position + Vector3(0, float(get_arg("looky", "1.35")), 0), Vector3.UP)
			cam.fov = float(get_arg("fov", "50"))
			cam.current = true
			var sl := SpotLight3D.new()
			sl.light_energy = float(get_arg("light", "6"))
			sl.spot_range = 12.0
			sl.spot_angle = 24.0
			sl.light_color = Color(1.0, 0.93, 0.8)
			sl.shadow_enabled = true
			cam.add_child(sl)
			sl.position = Vector3(0.35, -0.2, 0)
			await _frames(4)
			if get_arg("clip", "") != "":
				k.pose_clip(get_arg("clip", ""), float(get_arg("clip_t", "0")))
			if k.poser:
				for kv in get_arg("pose", "").split(",", false):
					var pr := kv.split("=")
					k.poser.set(pr[0], float(pr[1]))
				k.set_physics_process(not has("freeze"))
			await _frames(settle)
		"handoff":
			Legacy.begin_expedition()   # a real chain member (name, expedition number)
			var g: Node = await _game()
			for it in ["keycard_blue", "battery", "fuse", "medkit"]:
				GameState.inventory.add(it)
			GameState.elapsed = 512.0
			GameState.note_area("storage")
			Legacy.end_expedition("died", Vector3(-3.0, 0.0, -14.6), "storage")
			g.ended = true
			g.hud.show_handoff()
			g.hud.handoff.select_template(1)
			g.hud.handoff._custom_edit.text = "it waited by the storage door. don't run past it"
			g.hud.handoff.set_custom(g.hud.handoff._custom_edit.text)
			g.hud.handoff.select_item("keycard_blue")
			g.hud.handoff.select_symbol("eye")
			await _frames(settle)
		"handoff_done":
			var g: Node = await _game()
			GameState.inventory.add("battery")
			Legacy.end_expedition("extracted", Vector3(0.0, 0.0, 6.0), "lab")
			g.ended = true
			g.hud.show_handoff()
			g.hud.handoff.confirm()
			await _frames(settle)
		"history":
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
			await _frames(10)
			get_tree().current_scene.open_history()
			await _frames(settle)
		"menu_chain":
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
			await _frames(settle)
		"crate_latest":
			var g: Node = await _game()
			g.player.flashlight.set_on(true)
			_place(g, Vector3(float(get_arg("px", "-1.2")), 0.05, float(get_arg("pz", "3.0"))), float(get_arg("yaw", "60")), float(get_arg("pitch", "-22")))
			await _frames(settle)
		"marks":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
			g.player.flashlight.set_on(true)
			_place(g, Vector3(float(get_arg("px", "0.3")), 0.05, float(get_arg("pz", "-6.5"))), float(get_arg("yaw", "0")), float(get_arg("pitch", "-30")))
			await _frames(settle)
		"locker":
			var g: Node = await _game()
			_power()
			g.get_node("Level/Interactables/DoorSecurity").set_open_immediate(true)
			var spot: HidingSpot = g.get_node("Level/Interactables/LockerSecurityA")
			_place(g, spot.outside_point(), 90.0, -5.0)
			await _frames(5)
			spot.interact(g.player)
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = Vector3(5.6, 0.0, -6.0)
			k.look_at_flat(Vector3(3.0, 0, -6.0))
			k.set_state(Keeper.S.SEARCH)
			await _frames(settle)
		"area":
			var g: Node = await _game()
			_power(true)
			for dn in ["DoorShaft", "DoorArchive", "DoorGenerator", "CrawlGrate", "DoorLab", "DoorVault", "DoorStorage", "DoorSecurity"]:
				var dd: Door = g.get_node("Level/Interactables/" + dn)
				dd.code_unlocked = true
				dd.set_open_immediate(true)
			g.player.flashlight.set_on(get_arg("light", "1") == "1")
			if has("crouch"):
				g.player.toggle_crouch()
			_place(g, Vector3(float(get_arg("px", "0")), 0.05, float(get_arg("pz", "0"))), float(get_arg("yaw", "0")), float(get_arg("pitch", "-10")))
			await _frames(settle)
		"broadcast_frame":
			var g: Node = await _game()
			Legacy.decide("power_route", "lift")
			Legacy.decide("archive", "opened")
			for gid in ["aux", "corridor_lights", "lab"]:
				GameState.grid.set_on(gid, true)
			for dn in ["DoorShaft", "DoorArchive", "DoorVault"]:
				var dd: Door = g.get_node("Level/Interactables/" + dn)
				dd.code_unlocked = true
				dd.set_open_immediate(true)
			var tx: Node3D = g.get_node("Level/Interactables/Transmitter")
			var at := tx.global_position
			g.player.global_position = at + Vector3(-0.9, -0.7, 0.0)
			g.player.face_yaw_degrees(-90.0)
			var k: Keeper = g.keeper if g.keeper else g.spawn_keeper()
			k.think = false
			k.global_position = Vector3(float(get_arg("kx", "4.0")), 0.0, float(get_arg("kz", "-16.6")))
			k.set_state(Keeper.S.CHASE)
			k.look_at_flat(at)
			var cam := Camera3D.new()
			g.add_child(cam)
			cam.global_position = at + Vector3(float(get_arg("cx", "-1.3")), float(get_arg("cy", "0.6")), float(get_arg("cz", "2.4")))
			cam.look_at(Vector3(4.6, 1.4, -17.2))
			cam.fov = 62.0
			cam.current = true
			g.hud.cinematic(true)
			g.hud.caption("UPLOAD 66%   -   every light in Halden Deep is on")
			await _frames(settle)
		"ending":
			var g: Node = await _game()
			if get_arg("id", "seal") == "seal":
				Legacy.decide("power_route", "freezer")
				Legacy.decide("drive", "destroyed")
			elif get_arg("id", "seal") == "broadcast":
				Legacy.decide("power_route", "lift")
				Legacy.decide("archive", "opened")
			EndingDirector.time_scale = float(get_arg("speed", "1"))
			Events.ending_started.emit(get_arg("id", "seal"))
			await _frames(settle)
			if has("card"):
				while g.hud.end_card == null or not g.hud.end_card.fully_shown:
					await get_tree().process_frame
				await _frames(3)
		"end":
			var g: Node = await _game()
			GameState.inventory.add("research_drive")
			GameState.elapsed = 417.0
			await _frames(10)
			Events.expedition_ended.emit("extracted")
			await _frames(settle)
		"session":
			await _session()
			get_tree().quit(0)
			return
		"keeper_preview":
			# v1.1 preview reel (tools/keeper_anim/keeper_preview.gd), meant for --write-movie
			await load("res://tools/keeper_anim/keeper_preview.gd").new().run(self)
			get_tree().quit(0)
			return
		_:
			push_error("unknown shot " + name_)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SHOT SAVED ", out, " ", img.get_size())
	get_tree().quit(0)



# ------------------------------------------------------------------ scripted session
## `-- --shot=session` : a scripted ~10 minute play session for release smoke tests
## (Windows build under Wine, or any desktop): menu -> intro -> explore every area ->
## hide in a locker -> Keeper -> die -> handoff -> next member -> pause / save & quit ->
## Continue -> extract -> handoff -> an ending -> end card. Uses its own save file.
## Prints "SESSION step ..." lines and "SESSION DONE" at the end.
func _step(s: String) -> void:
	print("SESSION step %s  t=%.1fs  fps=%d" % [s, Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second()])


func _wait_game(prev: Variant) -> Node:
	var prev_id: int = prev.get_instance_id() if is_instance_valid(prev) else 0
	for i in 3000:
		await get_tree().process_frame
		var sc := get_tree().current_scene
		if sc and sc.get_instance_id() != prev_id and sc.name == "Game" and sc.is_node_ready():
			await _frames(5)
			return sc
	push_error("SESSION: game scene never loaded")
	return null


func _wait_menu() -> Node:
	for i in 3000:
		await get_tree().process_frame
		var sc := get_tree().current_scene
		if sc and sc.has_method("open_history"):
			await _frames(5)
			return sc
	push_error("SESSION: menu never loaded")
	return null


func _tour(g: Node, frames_each: int) -> void:
	for a in Zones.RECTS:
		var r: Array = Zones.RECTS[a]
		var c := Vector3((r[0] + r[1]) * 0.5, 0.05, (r[2] + r[3]) * 0.5)
		var map: RID = g.get_world_3d().navigation_map
		var q := NavigationServer3D.map_get_closest_point(map, c)
		if Zones.area_at(q) == a:
			c = q + Vector3(0, 0.1, 0)
		g.player.global_position = c
		g.player.velocity = Vector3.ZERO
		await _frames(frames_each)
		if g.player.global_position.y < -3.0:
			push_error("SESSION: player fell out of the map in " + str(a))
		_step("explored " + str(a))


func _resume_if_paused(g: Node) -> void:
	var pm: Node = g.get_node_or_null("PauseMenu")
	if pm and pm.is_open():
		pm.resume()
	g.player.set_control(true)


func _session() -> void:
	var fpe := int(get_arg("fpe", "90"))
	Legacy.use_path("user://session_chain.json")
	Settings.set_value("video", "calibrated", true, false)
	_step("menu")
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	var m := await _wait_menu()
	m.open_history()
	await _frames(30)
	m._close_sub()
	m.open_settings()
	for tab in 4:
		m._settings.set_tab(tab, false)
		await _frames(10)
	m._settings.go_back()
	_step("start chain")
	m._start()
	var g := await _wait_game(null)
	_step("intro")
	await _frames(fpe * 3)
	Ux.go_back()   # Esc skips the intro
	await _frames(fpe)
	_resume_if_paused(g)
	await _tour(g, fpe)
	_step("hide")
	var spots := get_tree().get_nodes_in_group("hiding_spots")
	if not spots.is_empty():
		var hs: Node = spots[0]
		g.player.global_position = hs.outside_point()
		await _frames(10)
		hs.interact(g.player)
		await _frames(fpe)
		hs.leave(g.player)
		await _frames(fpe / 2)
	_step("keeper")
	if g.keeper == null:
		g.spawn_keeper()
	g.keeper.global_position = g.player.global_position + Vector3(2.5, 0, 0)
	await _frames(fpe * 2)
	_step("die")
	g.player.vitals.damage(1000.0, "keeper")
	for i in 600:
		await get_tree().process_frame
		if g.hud.handoff != null and g.hud.handoff.visible:
			break
	_step("handoff")
	var h: HandoffScreen = g.hud.handoff
	h.select_template(2)
	h._custom_edit.text = "keep the light low [b]near the lift[/b]"
	h.set_custom(h._custom_edit.text)
	var ch: Array = Legacy.handoff_choices()
	if not ch.is_empty():
		h.select_item(str(ch[0]))
	h.select_symbol(str(Lore.SYMBOLS.keys()[0]))
	await _frames(30)
	h.confirm()
	await _frames(fpe)
	_step("next member")
	h.next_member()
	g = await _wait_game(g)
	await _frames(fpe * 2)
	Ux.go_back()
	await _frames(fpe)
	_resume_if_paused(g)
	await _frames(fpe)
	_step("crate + pause")
	Ux.go_back()   # opens the pause menu
	await _frames(fpe)
	var pm: Node = g.get_node("PauseMenu")
	if not pm.is_open():
		push_error("SESSION: pause menu did not open")
	pm._open_settings()
	await _frames(30)
	pm._close_settings()
	_step("save and quit to menu")
	pm._to_menu()
	m = await _wait_menu()
	_step("continue")
	m._continue()
	g = await _wait_game(g)
	await _tour(g, fpe / 2)
	_step("extract")
	GameState.inventory.add("research_drive")
	Events.expedition_ended.emit("extracted")
	for i in 600:
		await get_tree().process_frame
		if g.hud.handoff != null and g.hud.handoff.visible:
			break
	g.hud.handoff.select_template(0)
	g.hud.handoff.confirm()
	await _frames(fpe)
	_step("third member -> ending")
	g.hud.handoff.next_member()
	g = await _wait_game(g)
	await _frames(fpe)
	Legacy.decide("power_route", "freezer")
	Legacy.decide("drive", "destroyed")
	EndingDirector.time_scale = float(get_arg("speed", "2"))
	Events.ending_started.emit("seal")
	for i in 20000:
		await get_tree().process_frame
		if g.hud.end_card != null and g.hud.end_card.visible and g.hud.end_card.fully_shown:
			break
	await _frames(fpe)
	_step("end card")
	print("SESSION history rows ", Legacy.history_rows(false).size(), " ending ", Legacy.ending_reached())
	SaveIO.delete_all("user://session_chain.json")
	print("SESSION DONE")
