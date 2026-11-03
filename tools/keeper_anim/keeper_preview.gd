extends RefCounted
## v1.1 preview reel of the Blender-keyframed Keeper (for sharing): crawl -> scream -> lunge ->
## stagger, then the vent drop and the stalk. Renders through Movie Maker:
##   xvfb-run godot --path . --write-movie /tmp/keeper.avi --fixed-fps 30 --resolution 854x480 -- --shot=keeper_preview --fastshadow=1
## The Keeper is puppeted (brain and mover off) so the shot is repeatable; the clips, the
## AnimationTree, the cross-fades and the playback-by-speed are the game's own.

const DT := 1.0 / 30.0
var h: Node
var k: Keeper
var cam: Camera3D
var look_at := Vector3.ZERO


func _tick(n := 1) -> void:
	for i in n:
		await h.get_tree().process_frame
		k._time += DT
		k.state_t += DT
		k._animate()
		var want := k.global_position + Vector3(0, 0.9, 0) if look_at == Vector3.ZERO else look_at
		cam.look_at(want, Vector3.UP)


func _move(v: Vector3, seconds: float) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		k.velocity = v
		k.global_position += v * DT
		if v.length() > 0.01:
			k.look_at_flat(k.global_position + v)
		await _tick()


func run(harness: Node) -> void:
	h = harness
	var g: Node = await h._game()
	GameState.grid.set_on("aux", true)
	GameState.grid.set_on("corridor_lights", true)
	g.get_node("Level/Interactables/DoorShaft").set_open_immediate(true)
	g.hud.visible = false
	Settings.set_value("access", "captions", false, false)
	Settings.set_value("access", "subtitles", false, false)
	g.player.global_position = Vector3(0.6, 0.05, 1.5)
	g.player.model.visible = false
	g.player.flashlight.set_on(false)
	k = g.keeper if g.keeper else g.spawn_keeper()
	k.think = false
	k.set_physics_process(false)
	cam = Camera3D.new()
	g.add_child(cam)
	cam.fov = 58.0
	cam.current = true
	var torch := SpotLight3D.new()
	torch.light_energy = 5.0
	torch.spot_range = 16.0
	torch.spot_angle = 26.0
	torch.light_color = Color(1.0, 0.92, 0.78)
	torch.shadow_enabled = true
	cam.add_child(torch)
	torch.position = Vector3(0.3, -0.25, 0.0)
	await h._frames(10)

	# 1. it comes down the corridor at you on all fours (search crawl, 1.6 m/s)
	cam.global_position = Vector3(0.35, 0.85, -4.6)
	k.global_position = Vector3(-0.1, 0.0, -11.6)
	k.look_at_flat(k.global_position + Vector3(0, 0, 1))
	k.set_state(Keeper.S.SEARCH)
	k.play_clip("kp_crawl", 0.0)
	await _move(Vector3(0, 0, 1.6), 2.9)
	# 2. it rears up and screams (0.5 s telegraph), lunges (0.3 s at 7 m/s), you sidestep, it staggers past
	k.set_state(Keeper.S.LUNGE)
	k._play_voice("keeper_scream", 3.0)
	var t := 0.0
	while t < 1.8:
		var ph := k.lunge_phase()
		var v := Vector3(0, 0, Keeper.LUNGE_SPEED) if ph == "lunge" else Vector3.ZERO
		if ph == "lunge" and not k._lunge_hit:
			k._lunge_hit = true
			k._play_voice("keeper_strike", 2.0)
		k.velocity = v
		k.global_position += v * DT
		if ph == "lunge":
			cam.global_position += Vector3(3.6, 0.0, 2.4) * DT
		elif ph == "recover":
			look_at = look_at.lerp(k.global_position + Vector3(0, 0.8, 0), 0.25) if look_at != Vector3.ZERO else k.global_position + Vector3(0, 0.8, 0)
		await _tick()
		t += DT
	look_at = Vector3.ZERO
	k.set_state(Keeper.S.WAIT_LIGHT)
	await _move(Vector3.ZERO, 0.4)
	# 3. cut: the ceiling vent by the lab door. It pours out head first and drops.
	k.set_state(Keeper.S.PATROL)
	k.velocity = Vector3.ZERO
	k.global_position = Keeper.VENT_EXIT
	k.look_at_flat(Keeper.VENT_EXIT + Vector3(0, 0, 1))
	cam.global_position = Vector3(0.75, 1.0, -16.4)
	cam.fov = 64.0
	look_at = Keeper.VENT_EXIT + Vector3(0, 2.3, 0)
	await _tick(8)
	Sfx.play_at("vent_bang", Keeper.VENT_EXIT + Vector3.UP * 3.0)
	k.hold_clip("kp_vent_drop", 1.2, 0.0)
	for i in 36:
		look_at = look_at.lerp(Keeper.VENT_EXIT + Vector3(0, 0.8, 0), 0.07)
		await _tick()
	Sfx.play_at("keeper_drag", Keeper.VENT_EXIT, -2.0)
	look_at = Vector3.ZERO
	await _move(Vector3.ZERO, 0.5)
	# 4. it gets up and stalks toward you
	await _move(Vector3(0, 0, 1.25), 2.0)
	await _tick(4)
