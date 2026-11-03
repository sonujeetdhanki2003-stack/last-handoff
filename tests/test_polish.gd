extends TestCase
## Phase 5 polish: rebinding save/load, hold/toggle sprint & crouch, subtitles for
## tapes / PA / important sounds, the cold-open intro and the title card, end cards
## that finish fading, unique surnames, the F3 overlay (off by default).

func run() -> void:
	_rebinding()
	await _subtitles()
	await _hold_toggle()
	await _intro_and_card()
	_surnames()


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _rebinding() -> void:
	Settings.reset_binds(false)
	var old := Settings.binding("interact", "kb")
	t.check(old != "", "interact has a default key (%s)" % old)
	Settings.rebind("interact", _key(KEY_G))
	t.eq(Settings.binding("interact", "kb"), "k:%d" % KEY_G, "interact rebound to G")
	var has_g := InputMap.action_get_events("interact").any(func(e): return e is InputEventKey and (e.keycode == KEY_G or e.physical_keycode == KEY_G))
	t.check(has_g, "InputMap carries the new key")
	# conflict: give crouch's key to sprint -> they swap
	var crouch_k := Settings.binding("crouch", "kb")
	var sw := Settings.rebind("sprint", Settings.code_event(crouch_k))
	t.eq(sw, "crouch", "taking crouch's key swaps the two actions")
	t.check(Settings.binding("crouch", "kb") != crouch_k, "crouch moved off the key it lost")
	# pad rebinding goes into the pad slot only
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_RIGHT_STICK
	jb.pressed = true
	Settings.rebind("flashlight", jb)
	t.eq(Settings.binding("flashlight", "pad"), "j:%d" % JOY_BUTTON_RIGHT_STICK, "pad binding set separately")
	t.check(Settings.binding("flashlight", "kb") != "", "keyboard binding untouched by the pad rebind")
	# saved and loaded from disk
	Settings.save_settings()
	Settings.reset_binds(false)
	t.check(Settings.binding("interact", "kb") != "k:%d" % KEY_G, "(reset in memory)")
	Settings.load_settings()
	t.eq(Settings.binding("interact", "kb"), "k:%d" % KEY_G, "rebinding survives save + load")
	t.eq(Settings.binding("flashlight", "pad"), "j:%d" % JOY_BUTTON_RIGHT_STICK, "pad rebinding survives save + load")
	t.check(Settings.action_label("interact", false) == "G", "prompt label follows the binding (%s)" % Settings.action_label("interact", false))
	Settings.reset_binds()
	t.eq(Settings.binding("interact", "kb"), old, "reset restores defaults")


func _subtitles() -> void:
	var got: Array = []
	var cb := func(kind: String, speaker: String, text: String): got.append([kind, speaker, text])
	Ux.subtitle_shown.connect(cb)
	Settings.set_value("access", "subtitles", true, false)
	Settings.set_value("access", "captions", true, false)
	var tape_id: String = Sfx._subs.keys()[0]
	var lines := Sfx.tape_lines(tape_id)
	t.check(lines.size() > 0, "tape %s has timed subtitle lines (%d)" % [tape_id, lines.size()])
	var host := Node3D.new()
	t.sandbox.add_child(host)
	Sfx.play_tape(tape_id, host)
	await t.frames(3)
	var first: float = lines[0][0] if lines.size() > 0 else 0.0
	await t.sandbox.get_tree().create_timer(first + 0.3).timeout
	t.check(got.any(func(g): return g[0] == "speech" and g[1] == Sfx.tape_speaker(tape_id)), "tape playback shows a subtitle with the speaker's name")
	Sfx.stop_tape(false)
	got.clear()
	Sfx.play_pa("pa_generator")
	await t.sandbox.get_tree().create_timer(1.5).timeout
	t.check(got.any(func(g): return g[0] == "pa"), "station PA shows a subtitle")
	got.clear()
	Sfx.caption_for("keeper_alert", Vector3(5, 0, 0))
	await t.frames(1)
	t.check(got.any(func(g): return g[0] == "sound"), "important sound shows a caption")
	got.clear()
	Settings.set_value("access", "captions", false, false)
	Sfx.caption_for("keeper_alert", Vector3(5, 0, 0))
	Settings.set_value("access", "subtitles", false, false)
	Sfx.play_pa("pa_lab")
	await t.sandbox.get_tree().create_timer(1.5).timeout
	t.check(got.is_empty(), "captions / subtitles off: nothing shown")
	Settings.set_value("access", "subtitles", true, false)
	Settings.set_value("access", "captions", true, false)
	Ux.subtitle_shown.disconnect(cb)
	Ux.clear_subtitles()
	host.queue_free()


func _hold_toggle() -> void:
	GameState.new_expedition(55)
	GameState.threat_enabled = false
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(6)
	var p: Player = g.player
	t.check(not g.debug_overlay.on, "F3 debug overlay is off by default")
	var f3 := _key(KEY_F3)
	Input.parse_input_event(f3)
	Input.flush_buffered_events()
	await t.frames(2)
	t.check(g.debug_overlay.on, "F3 shows the debug overlay")
	g.debug_overlay.set_on(false)
	# crouch: toggle (default) vs hold
	Settings.set_value("controls", "crouch_mode", Settings.TOGGLE, false)
	var c := InputEventAction.new()
	c.action = "crouch"
	c.pressed = true
	p._unhandled_input(c)
	await t.physics(2)
	var cu := InputEventAction.new()
	cu.action = "crouch"
	cu.pressed = false
	p._unhandled_input(cu)
	await t.physics(4)
	t.check(p.crouching, "toggle crouch: still crouched after release")
	p._unhandled_input(c)
	p._unhandled_input(cu)
	await t.physics(4)
	t.check(not p.crouching, "toggle crouch: second press stands")
	Settings.set_value("controls", "crouch_mode", Settings.HOLD, false)
	p._unhandled_input(c)
	await t.physics(4)
	t.check(p.crouching, "hold crouch: crouched while held")
	p._unhandled_input(cu)
	await t.physics(6)
	t.check(not p.crouching, "hold crouch: stands on release")
	Settings.set_value("controls", "crouch_mode", Settings.TOGGLE, false)
	# sprint toggle latches
	Settings.set_value("controls", "sprint_mode", Settings.TOGGLE, false)
	var s := InputEventAction.new()
	s.action = "sprint"
	s.pressed = true
	p._unhandled_input(s)
	t.check(p.sprint_latched, "toggle sprint: one press latches sprint")
	p._unhandled_input(s)
	t.check(not p.sprint_latched, "toggle sprint: next press releases")
	Settings.set_value("controls", "sprint_mode", Settings.HOLD, false)
	# camera shake setting scales the shake
	Settings.set_value("access", "camera_shake", 0.0, false)
	p.cam._shake = 0.0
	p.cam.shake(0.8)
	t.near(p.cam._shake, 0.0, 0.001, "camera shake at 0%% does nothing")
	Settings.set_value("access", "camera_shake", 1.0, false)
	p.cam.shake(0.5)
	t.check(p.cam._shake > 0.4, "camera shake at 100%% shakes")
	# footsteps by surface
	t.eq(p.surface(), "metal", "standing on the lift deck / shaft grating: metal footsteps") if Zones.area_at(p.global_position) == "shaft" and absf(p.global_position.x) < 1.6 and p.global_position.z > 5.0 else t.check(p.surface() in ["concrete", "metal", "tile", "water"], "surface for footsteps: " + p.surface())
	t.check(Sfx.footstep_stream("tile") != null and Sfx.footstep_stream("water") != null, "footstep sounds exist per surface")
	g.queue_free()
	await t.frames(4)


func _intro_and_card() -> void:
	GameState.new_expedition(66)
	GameState.threat_enabled = false
	Legacy.begin_expedition()
	GameState.play_intro = true
	IntroDirector.time_scale = 12.0
	TitleCard.time_scale = 12.0
	var cards: Array = []
	var cb := func(): cards.append(true)
	Ux.title_card_done.connect(cb)
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(3)
	t.check(g.intro != null, "a new expedition opens on the cold-open intro")
	t.check(not g.player.control_enabled, "player has no control during the intro")
	var cage := g.level.find_child("Lift", true, false) as Node3D
	var t0 := Time.get_ticks_msec()
	var saw_cage_up := cage != null and cage.global_position.y > 1.0
	while not g.intro.done and Time.get_ticks_msec() - t0 < 20000:
		await t.frames(1)
	t.check(saw_cage_up, "the cage starts up the shaft")
	t.check(g.intro.done, "intro descent completes")
	t.check(cage == null or absf(cage.global_position.y) < 0.01, "the cage is back at the bottom")
	var crate := g.level.find_child("HandoffCrateLatest", true, false) as Node3D
	t0 = Time.get_ticks_msec()
	while cards.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		await t.frames(1)
	t.check(not cards.is_empty(), "title card shows and finishes")
	t.check(Ux.last_title.begins_with("EXPEDITION %d" % GameState.expedition_number), "title card reads " + Ux.last_title)
	await t.frames(5)
	t.check(g.player.control_enabled, "player gets control after the title card")
	if crate:
		var fwd: Vector3 = -g.player.cam.camera.global_transform.basis.z
		var to: Vector3 = (crate.global_position - g.player.global_position).normalized()
		t.check(Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.7, "camera ends on the previous member's crate (cam yaw %.0f, player %s, crate %s)" % [g.player.cam.yaw, str(g.player.global_position), str(crate.global_position)])
	g.queue_free()
	await t.frames(4)
	# skip
	GameState.play_intro = true
	IntroDirector.time_scale = 1.0
	var g2: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g2)
	await t.physics(10)
	var sk := InputEventAction.new()
	sk.action = "skip"
	sk.pressed = true
	g2.intro._unhandled_input(sk)
	t0 = Time.get_ticks_msec()
	while not g2.intro.done and Time.get_ticks_msec() - t0 < 5000:
		await t.frames(1)
	t.check(g2.intro.done and Time.get_ticks_msec() - t0 < 3000, "the intro can be skipped")
	g2.queue_free()
	await t.frames(4)
	Ux.title_card_done.disconnect(cb)
	IntroDirector.time_scale = 1.0
	TitleCard.time_scale = 1.0
	Ux.set_black(0.0)


func _surnames() -> void:
	var seen := {}
	var dup := false
	for i in 20:
		var n := Lore.member_name(4242, 7 + i)
		var sur := n.split(" ")[-1]
		if seen.has(sur):
			dup = true
		seen[sur] = true
	t.check(not dup, "20 members of one chain, no repeated surname")
