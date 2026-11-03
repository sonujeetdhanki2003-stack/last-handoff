extends TestCase
## Phase 3: world and atmosphere. Loads the real game scene and checks the art
## pass did not break anything and that every atmosphere system is wired:
## audio logs (voiced + transcripts), readable documents, ambient director
## (room detection, buses, tension), animated props, power-tied lights,
## decals/props present, story marks, the LIFT label and the explorer's gear.

var g: Node
var p: Player


func run() -> void:
	GameState.new_expedition(77)
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)
	var lvl: Node = g.get_node("Level")

	# --- character
	var skel := p.model.find_children("*", "Skeleton3D", true, false)
	t.check(skel.size() == 1 and skel[0].name == "GeneralSkeleton", "explorer uses the retargeted humanoid skeleton")
	var ap := p.model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	t.check(ap != null and ap.has_animation("Walk") and ap.has_animation("Idle_Torch") and ap.has_animation("Fixing_Kneeling"), "UAL clips available on the explorer")
	var a := ap.get_animation("Walk")
	t.check(String(a.track_get_path(1)).begins_with("%GeneralSkeleton:"), "clips address the unique humanoid skeleton")
	var gear := 0
	for m in p.model.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).get_parent() and (m as MeshInstance3D).get_parent().get_parent() is BoneAttachment3D:
			gear += 1
	t.check(gear >= 15, "helmet, headlamp, backpack and straps attached to bones (%d parts)" % gear)
	var body: MeshInstance3D = null
	for m in p.model.find_children("SuperHero*", "MeshInstance3D", true, false):
		body = m
	t.check(body != null and body.material_override is StandardMaterial3D and (body.material_override as StandardMaterial3D).next_pass is ShaderMaterial, "jumpsuit material has the rim-light pass")
	var hips := (skel[0] as Skeleton3D).find_bone("Hips")
	var before := (skel[0] as Skeleton3D).get_bone_pose_rotation(hips)
	Input.action_press("move_forward")
	for i in 30:
		await t.physics(1)
	Input.action_release("move_forward")
	var after := (skel[0] as Skeleton3D).get_bone_pose_rotation(hips)
	t.check(not before.is_equal_approx(after), "skeleton animates while walking")

	# --- audio logs
	var logs := lvl.find_children("Log_*", "", true, false)
	# Phase 3 placed 4-6; Phase 4 adds Mara's three later tapes (archive, crawlspace, old camp)
	t.check(logs.size() >= 4 and logs.size() <= 6 + 3, "4-6 audio logs (+3 Phase 4 Mara tapes) placed in the level (%d)" % logs.size())
	for l in logs:
		var id: String = l.log_id
		t.check(AudioLogs.has(id) and ResourceLoader.exists(AudioLogs.stream_path(id)), "tape %s has a transcript and a voiced recording" % id)
	var log0: AudioLog = logs[0]
	var started := [""]
	Events.tape_started.connect(func(title, _len): started[0] = title, CONNECT_ONE_SHOT)
	log0.interact(p)
	await t.physics(2)
	t.eq(Sfx.tape_playing, log0.log_id, "interacting plays the tape")
	t.check(started[0] != "" and g.hud.tape_bar.visible, "HUD shows the now-playing strip")
	t.check(g.hud.note_panel.visible and g.hud._note_title.text.begins_with("TAPE"), "transcript opens in the document reader")
	t.check(GameState.get_flag("log_" + log0.log_id), "played tape is remembered (flag)")
	g.hud.close_note()
	t.check(log0.get_prompt(p).begins_with("Stop"), "prompt offers to stop a playing tape")
	log0.interact(p)
	await t.physics(2)
	t.eq(Sfx.tape_playing, "", "interacting again stops it")
	t.check(not g.hud.tape_bar.visible, "now-playing strip hides when stopped")
	t.check(GameState.inventory.slots.all(func(s): return s == null), "tapes take no inventory slot")

	# --- readable documents
	var docs := lvl.find_children("Doc_*", "", true, false)
	t.check(docs.size() >= 4, "research documents placed (%d)" % docs.size())
	for d in docs:
		var n := Notes.get_note(d.note_id)
		t.check(n["title"] != d.note_id and n["body"].length() > 60, "document %s has real text" % d.note_id)
	docs[0].interact(p)
	t.check(g.hud.note_panel.visible, "reading a document opens the reader")
	g.hud.close_note()

	# --- ambient director
	var amb: AmbientDirector = lvl.get_node("AmbientDirector")
	t.eq(amb.room_at(Vector3(0, 0, 4)), "shaft", "room detection: shaft")
	t.eq(amb.room_at(Vector3(0, 0, -10)), "corridor", "room detection: corridor")
	t.eq(amb.room_at(Vector3(-6, 0, -5)), "generator", "room detection: generator room")
	t.eq(amb.room_at(Vector3(5, 0, -7)), "security", "room detection: security")
	t.eq(amb.room_at(Vector3(-5, 0, -15)), "storage", "room detection: storage")
	t.eq(amb.room_at(Vector3(0, 0, -28)), "lab", "room detection: lab")
	var buses_ok := true
	for c in amb.get_children():
		if c is AudioStreamPlayer:
			buses_ok = buses_ok and (c.bus == &"Ambience" or c.bus == &"Music") and c.playing
			buses_ok = buses_ok and (c.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
	t.check(buses_ok, "room tones + drone + tension loop on the Ambience/Music buses")
	p.global_position = Vector3(0, 0.05, -28)
	p.flashlight.set_on(false)
	for i in 40:
		await t.physics(1)
	t.check(amb.tension > 0.6, "tension rises in Lab 3 in the dark (%.2f)" % amb.tension)
	p.global_position = Vector3(0, 0.05, 4.4)
	p.flashlight.set_on(true)
	await t.physics(40)

	# --- animated details and power-tied effects
	var fan := lvl.find_child("ExtractorFan", true, false)
	var rotor: Spinner = fan.get_node("Rotor")
	var r0 := rotor.rotation
	await t.physics(20)
	t.check(not rotor.rotation.is_equal_approx(r0), "generator-room fan turns on its own with no power (story)")
	var sparks: Sparker = lvl.find_child("Sparks", true, false)
	t.check(not sparks._powered(), "corridor junction box does not spark before power")
	GameState.grid.set_on("aux", true)
	t.check(sparks._powered(), "it sparks once aux power is on")
	sparks.burst()
	await t.physics(2)
	t.check(sparks._light.light_energy > 0.0, "spark burst flashes a light")
	var sways := lvl.find_children("*", "Node3D", true, false).filter(func(n): return n is Sway)
	t.check(sways.size() >= 6, "dangling cables / loose lamp sway (%d)" % sways.size())
	var s0: float = sways[0].rotation.x
	await t.physics(15)
	t.check(absf(sways[0].rotation.x - s0) > 0.0001, "sway animates")
	var crts := lvl.find_children("Screen", "MeshInstance3D", true, false)
	t.check(crts.size() >= 3, "flickering CRT monitors (%d)" % crts.size())
	var vents := lvl.find_children("*", "Node3D", true, false).filter(func(n): return n is SteamVent)
	t.check(vents.size() >= 1, "steam leak present")
	var beacon: Spinner = lvl.find_child("Beacon", true, false)
	var b0 := beacon.rotation.y
	await t.physics(10)
	t.check(absf(beacon.rotation.y - b0) > 0.01, "shaft emergency beacon rotates")
	var loose := lvl.find_child("LooseLamp", true, false)
	var pl: PoweredLight = loose.get_node("Bulb")
	t.check(not pl.is_on(), "loose corridor lamp is dark until the corridor breaker")
	GameState.grid.set_on("corridor_lights", true)
	await t.physics(30)
	t.check(pl.is_on(), "loose lamp powers with the corridor circuit")

	# --- dressing present, decals load, story marks
	var decals := lvl.find_children("*", "Decal", true, false)
	t.check(decals.size() >= 80, "decals placed (%d)" % decals.size())
	var bad := 0
	for d in decals:
		if (d as Decal).texture_albedo == null:
			bad += 1
	t.eq(bad, 0, "every decal has its texture")
	for mark in ["TallyMarks", "SixBeforeMe", "OldCrateRelay2", "OldCrateExp1", "SleepingBag"]:
		t.check(lvl.find_child(mark, true, false) != null, "story mark present: " + mark)
	var props := lvl.get_node("Dressing").find_children("Collision", "StaticBody3D", true, false)
	var on_world := props.filter(func(b): return (b as StaticBody3D).collision_layer & 1)
	t.check(props.size() >= 30, "physical props with collision (%d)" % props.size())
	var blockers := 0
	for b in props:
		var cs: CollisionShape3D = b.get_child(0)
		var c := (cs.global_position)
		if (b as StaticBody3D).collision_layer & 1 == 0:
			continue
		if absf(c.x) < 0.9 and c.z < 0.5 and c.z > -22.0:
			blockers += 1
	t.eq(blockers, 0, "no solid prop in the corridor walking lane")

	# --- the LIFT label fix
	var lift: Node = lvl.get_node("Interactables/LiftPanel")
	var lbl: Label3D = null
	for c in lift.get_children():
		if c is Label3D:
			lbl = c
	t.check(lbl != null and not lbl.double_sided, "LIFT label is single-sided (never mirrored from behind)")
	var mirrored := 0
	for l in lvl.find_children("*", "Label3D", true, false):
		if (l as Label3D).double_sided:
			mirrored += 1
	t.eq(mirrored, 0, "no level sign can be read mirrored")
	print("  INFO  props=%d (solid world=%d), decals=%d, logs=%d, docs=%d" % [props.size(), on_world.size(), decals.size(), logs.size(), docs.size()])
	Sfx.stop_tape(false)
