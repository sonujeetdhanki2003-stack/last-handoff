extends TestCase
## v1.2: heartbeat + vibration, fake-out director, chapters, achievements, How to Play,
## and the phone RUN button fixes.

var g: Node
var p: Player


func run() -> void:
	_feedback_rules()
	_fakeout_rules()
	await _progress_store()
	await _settings_run_default()
	Legacy.reset_chain()
	Legacy.begin_expedition()
	GameState.play_intro = false
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)
	p.set_control(true)
	await _heartbeat_in_game()
	await _fakeouts_in_game()
	await _fakeout_props()
	await _achievement_hooks()
	await _run_button()
	g.queue_free()
	g = null
	await t.physics(3)
	await _touch_multitouch()
	await _new_area()
	await _chapters()
	await _menu_screens()
	_export()


# ----------------------------------------------------------------- heartbeat
func _feedback_rules() -> void:
	t.eq(ThreatFeedback.level_for(3.0, Keeper.S.DORMANT), 0.0, "heartbeat: a dormant Keeper never sets it off")
	t.eq(ThreatFeedback.level_for(30.0, Keeper.S.PATROL), 0.0, "heartbeat: silent when it is far (30 m)")
	var near := ThreatFeedback.level_for(3.0, Keeper.S.PATROL)
	var mid := ThreatFeedback.level_for(9.0, Keeper.S.PATROL)
	t.check(near > mid and mid > 0.0, "heartbeat rises as it gets closer (9 m %.2f < 3 m %.2f)" % [mid, near])
	t.check(ThreatFeedback.level_for(20.0, Keeper.S.CHASE) >= 0.7, "a chase sets it racing even from 20 m")
	t.check(ThreatFeedback.level_for(9.0, Keeper.S.SEARCH) > mid, "searching for you counts more than wandering")
	t.check(ThreatFeedback.bpm_for(1.0) > ThreatFeedback.bpm_for(0.2), "rate rises with fear")
	t.check(ThreatFeedback.volume_for(1.0) > ThreatFeedback.volume_for(0.2), "volume rises with fear")
	var pv := ThreatFeedback.pulse_for(1.0)
	t.check(pv.x <= 70.0 and pv.x >= 25.0 and pv.y <= 1.0, "a vibration pulse is short (%d ms)" % int(pv.x))
	t.check(60.0 / ThreatFeedback.bpm_for(1.0) >= ThreatFeedback.MIN_PULSE_GAP, "at most one pulse per beat, beats never closer than the pulse gap")


func _place_keeper(pos: Vector3, s: int) -> Keeper:
	var k: Keeper = g.keeper
	k.think = false
	k.velocity = Vector3.ZERO
	k.global_position = pos
	k.set_state(s)
	return k


func _heartbeat_in_game() -> void:
	var tf: ThreatFeedback = g.threat_feedback
	t.check(tf != null, "the game has the heartbeat / vibration node")
	var buzz := []
	tf.vibrate_fn = func(ms: int, s: float): buzz.append([Time.get_ticks_msec(), ms, s])
	Settings.set_value("controls", "vibration", true, false)
	Settings.set_value("audio", "heartbeat", true, false)
	p.global_position = Vector3(0.0, 0.05, -6.0)
	_place_keeper(Vector3(0.0, 0.05, -8.5), Keeper.S.SEARCH)
	var b0 := tf.beats
	await t.physics(240)
	t.check(tf.beats - b0 >= 5, "close Keeper: the heart beats (%d beats in 4 s)" % (tf.beats - b0))
	t.check(buzz.size() >= 3, "close Keeper: the phone / pad pulses (%d)" % buzz.size())
	var min_gap := 99999
	for i in range(1, buzz.size()):
		min_gap = mini(min_gap, buzz[i][0] - buzz[i - 1][0])
	t.check(buzz.size() < 2 or min_gap >= int(ThreatFeedback.MIN_PULSE_GAP * 1000.0) - 40, "pulses are rate-limited (closest %d ms apart)" % min_gap)
	t.check(buzz.size() <= 4 * 3, "battery-sane: at most ~3 pulses a second")
	# far away: it calms down and stops
	_place_keeper(Vector3(0.0, 0.05, -30.0), Keeper.S.PATROL)
	await t.physics(360)
	var b1 := tf.beats
	var n1 := buzz.size()
	await t.physics(120)
	t.eq(tf.beats, b1, "far Keeper: the heartbeat stops")
	t.eq(buzz.size(), n1, "far Keeper: no vibration")
	# vibration toggle off
	Settings.set_value("controls", "vibration", false, false)
	_place_keeper(Vector3(0.0, 0.05, -8.0), Keeper.S.SEARCH)
	await t.physics(200)
	t.eq(buzz.size(), n1, "Vibration off in Settings: no pulses at all")
	t.check(tf.beats > b1, "...while the heartbeat still plays")
	Settings.set_value("controls", "vibration", true, false)
	# paused: nothing
	get_tree_paused(true)
	var b2 := tf.beats
	for i in 60:
		tf._process(1.0 / 60.0)
	t.eq(tf.beats, b2, "paused game: no heartbeat")
	get_tree_paused(false)
	_place_keeper(Vector3(0.0, 0.05, -30.0), Keeper.S.PATROL)
	await t.physics(10)
	tf.level = 0.0


func get_tree_paused(v: bool) -> void:
	t.get_tree().paused = v


# ----------------------------------------------------------------- fake-outs
func _fakeout_rules() -> void:
	var S := Keeper.S
	t.check(not FakeoutDirector.allowed(10.0, 0.0, S.PATROL, 30.0, 999.0, false), "fake-outs: none in the first %d s" % int(FakeoutDirector.FIRST_DELAY))
	t.check(FakeoutDirector.allowed(200.0, 100.0, S.PATROL, 30.0, 999.0, false), "fake-outs: allowed when calm")
	for st in [S.CHASE, S.LUNGE, S.GRAB, S.INVESTIGATE, S.SEARCH, S.WAIT_LIGHT, S.REPELLED, S.RETREAT]:
		t.check(not FakeoutDirector.allowed(200.0, 100.0, st, 30.0, 999.0, false), "fake-outs: never while the Keeper is %s" % Keeper.NAMES[st])
	t.check(not FakeoutDirector.allowed(200.0, 100.0, S.PATROL, 30.0, 10.0, false), "fake-outs: not right after an alert")
	t.check(not FakeoutDirector.allowed(200.0, 100.0, S.PATROL, 8.0, 999.0, false), "fake-outs: never when the Keeper is close")
	t.check(FakeoutDirector.allowed(200.0, 100.0, S.DORMANT, 8.0, 999.0, false), "fake-outs: a sleeping Keeper is no danger")
	t.check(not FakeoutDirector.allowed(200.0, 300.0, S.PATROL, 30.0, 999.0, false), "fake-outs: rate-limited (not before next_at)")
	t.check(not FakeoutDirector.allowed(200.0, 100.0, S.PATROL, 30.0, 999.0, true), "fake-outs: never while hiding / reading / in a menu")
	t.check(not FakeoutDirector.spot_ok(Vector3(0, 0, -2), Vector3.ZERO, null), "fake-out spot: not right next to you")
	t.check(not FakeoutDirector.spot_ok(Vector3(0, 0, -30), Vector3.ZERO, null), "fake-out spot: not out of earshot")
	t.check(not FakeoutDirector.spot_ok(Vector3(0, 0, -10), Vector3.ZERO, Vector3(0, 0, -15)), "fake-out spot: never near the Keeper's real position")
	t.check(FakeoutDirector.spot_ok(Vector3(0, 0, -10), Vector3.ZERO, Vector3(0, 0, 25)), "fake-out spot: fine far from the Keeper")
	t.check(FakeoutDirector.MIN_GAP >= 60.0 and FakeoutDirector.MIN_GAP <= 90.0, "fake-outs: at least %d s apart" % int(FakeoutDirector.MIN_GAP))


func _fakeouts_in_game() -> void:
	var fd: FakeoutDirector = g.fakeouts
	t.check(fd != null, "the game has a fake-out director")
	var noises := [0]
	var cb := func(_p, _r, _s): noises[0] += 1
	Events.noise.connect(cb)
	p.global_position = Vector3(0.0, 0.05, -10.0)
	var k := _place_keeper(Vector3(-5.0, 0.05, -30.0), Keeper.S.PATROL)
	# each kind can play in a fair spot
	for kind in FakeoutDirector.KINDS:
		var before: int = fd.fired.size()
		var ok := fd.try_fire(kind)
		t.check(ok, "fake-out '%s' plays from the corridor" % kind)
		if ok:
			var at: Vector3 = fd.fired[before][2]
			var dp := Vector2(at.x - p.global_position.x, at.z - p.global_position.z).length()
			var dk := Vector2(at.x - k.global_position.x, at.z - k.global_position.z).length()
			t.check(dp >= FakeoutDirector.SPOT_MIN and dp <= FakeoutDirector.SPOT_MAX and dk >= FakeoutDirector.SPOT_FROM_KEEPER, "  '%s' at %.1f m from you, %.1f m from the Keeper" % [kind, dp, dk])
	await t.physics(90)
	t.eq(noises[0], 0, "fake-outs make no noise the Keeper can hear")
	t.eq(k.state, Keeper.S.PATROL, "the Keeper ignores fake-outs")
	# a 30-minute simulated session: random Keeper behaviour, check every rule on every scare
	fd.fired.clear()
	fd.clock = 0.0
	fd.next_at = FakeoutDirector.FIRST_DELAY
	fd.last_alert = -999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var hunting_until := -1.0
	var hunt_log: Array = []
	var bad := []
	for sec in 1800:
		var tsec := float(sec)
		if tsec > hunting_until and rng.randf() < 0.02:
			hunting_until = tsec + rng.randf_range(5.0, 40.0)
		var hunting := tsec <= hunting_until
		var st := Keeper.S.CHASE if hunting else Keeper.S.PATROL
		var kp := Vector3(rng.randf_range(-6.0, 6.0), 0.05, rng.randf_range(-30.0, 4.0))
		if not hunting and rng.randf() < 0.4:
			kp = p.global_position + Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-6.0, 6.0))
		k.global_position = kp
		k.state = st
		if hunting:
			hunt_log.append(tsec)
		var n_before: int = fd.fired.size()
		fd._process(1.0)
		if fd.fired.size() > n_before:
			var f: Array = fd.fired[-1]
			var at: Vector3 = f[2]
			if hunting:
				bad.append("fired during a hunt at %d s" % sec)
			if not hunt_log.is_empty() and tsec - float(hunt_log[-1]) < FakeoutDirector.CALM_AFTER:
				bad.append("fired %.0f s after a hunt" % (tsec - float(hunt_log[-1])))
			if k.global_position.distance_to(p.global_position) < FakeoutDirector.KEEPER_CLEAR:
				bad.append("fired with the Keeper close")
			if Vector2(at.x - kp.x, at.z - kp.z).length() < FakeoutDirector.SPOT_FROM_KEEPER:
				bad.append("spot near the Keeper")
	var gaps_ok := true
	for i in range(1, fd.fired.size()):
		if float(fd.fired[i][0]) - float(fd.fired[i - 1][0]) < FakeoutDirector.MIN_GAP - 0.01:
			gaps_ok = false
	t.check(bad.is_empty(), "30 min simulated: no scare breaks the rules %s" % str(bad.slice(0, 3)))
	t.check(gaps_ok, "30 min simulated: scares are >= %d s apart" % int(FakeoutDirector.MIN_GAP))
	t.check(fd.fired.size() >= 3 and fd.fired.size() <= 1800 / int(FakeoutDirector.MIN_GAP), "30 min simulated: %d scares (rare, but they happen)" % fd.fired.size())
	t.check(fd.fired.size() == 0 or float(fd.fired[0][0]) >= FakeoutDirector.FIRST_DELAY, "no scare in the opening minute")
	Events.noise.disconnect(cb)
	_place_keeper(Vector3(0.0, 0.05, -30.0), Keeper.S.PATROL)
	fd.enabled = false


func _fakeout_props() -> void:
	var spots: Array = t.get_tree().get_nodes_in_group("hiding_spots").filter(func(s): return s is HidingSpot and s.kind == "locker")
	t.check(not spots.is_empty(), "lockers exist")
	await t.physics(70)   # let rattles from the simulated session finish
	var hs: HidingSpot = spots[0]
	var pos := hs.global_position
	t.check(hs.rattle(), "an empty locker rattles")
	await t.physics(70)
	t.check(hs.global_position.is_equal_approx(pos) and not hs.rattling, "the rattle moves nothing and ends")
	hs.occupant = p
	t.check(not hs.rattle(), "an occupied locker never rattles")
	hs.occupant = null
	var lamps: Array = t.get_tree().get_nodes_in_group("powered_lights").filter(func(l): return (l as PoweredLight).pool_radius > 0.0)
	if lamps.is_empty():
		lamps = t.get_tree().get_nodes_in_group("powered_lights")
	GameState.grid.set_on("aux", true)
	GameState.grid.set_on("corridor_lights", true)
	await t.physics(30)
	var lamp: PoweredLight = null
	for l in lamps:
		if (l as PoweredLight).is_on():
			lamp = l
			break
	t.check(lamp != null, "a lit lamp to brown out")
	if lamp:
		var probe := lamp.global_position + Vector3(0.3, -lamp.global_position.y, 0.0)
		var cov := lamp.covers(probe)
		t.check(lamp.brownout(), "a lamp browns out")
		await t.physics(20)
		t.eq(lamp.covers(probe), cov, "a brownout does not change where the light keeps the Keeper out")
		lamp.suppress(1.0)
		t.check(not lamp.browning, "the Keeper's real smothering cancels a brownout")
		await t.physics(150)


# ----------------------------------------------------------------- achievements / chapters
func _progress_store() -> void:
	Progress.use_path("user://test_progress_v12.json")
	t.eq(Progress.ACHIEVEMENTS.size(), 14, "14 achievements")
	var hidden := 0
	for id in Progress.ACHIEVEMENTS:
		if Progress.ACHIEVEMENTS[id][2]:
			hidden += 1
			t.eq(Progress.display(id)["title"], "???", "hidden achievement '%s' shows as ???" % id)
	t.eq(hidden, 3, "3 of them hidden")
	t.check(Progress.chapter_open("descent") and not Progress.chapter_open("lab"), "a new player has chapter I only")
	Progress.toasts_shown.clear()
	t.check(Progress.unlock("repel"), "unlocking an achievement")
	t.check(not Progress.unlock("repel"), "...only once")
	await t.frames(3)
	t.check(Progress.toasts_shown.has("repel"), "a toast pops up on unlock")
	Progress.load_progress()
	t.check(Progress.is_unlocked("repel"), "achievements survive a restart (saved locally)")
	t.check(not Progress.unlock("no_such_thing"), "unknown ids are ignored")
	# a corrupt file: fresh progress, no crash
	var f := FileAccess.open(Progress.path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	SaveIO.delete_all(Progress.path + ".bak")
	Progress.load_progress()
	t.check(Progress.data["achievements"] is Dictionary, "a damaged progress file loads as fresh instead of crashing")
	# an old 1.0/1.1 chain: unlocks what it shows, quietly
	Progress.use_path("user://test_progress_v12b.json")
	Progress._queue.clear()
	var old := {"version": 1, "history": [
		{"expedition": 7, "depth": "lab", "end": "died", "item": "battery", "message": "x", "refused": false},
		{"expedition": 8, "depth": "storage", "end": "extracted", "item": "", "message": "", "refused": true}],
		"endings_seen": [], "tapes": {}, "decisions": {}, "run": null}
	Progress.retro_from_chain(old)
	t.check(Progress.chapter_open("power") and Progress.chapter_open("lab") and Progress.chapter_open("ascent"), "an old save opens the chapters it reached")
	t.check(Progress.is_unlocked("relay") and Progress.is_unlocked("extracted") and Progress.is_unlocked("descent"), "an old save unlocks what it earned")
	t.check(not Progress.is_unlocked("ending") and not Progress.is_unlocked("tapes"), "...and nothing it did not")
	t.check(Progress._queue.is_empty(), "old-save unlocks are quiet (no toast flood)")
	Progress.retro_from_chain({"history": "broken", "run": 5, "tapes": [], "endings_seen": {}})
	t.check(true, "a malformed old chain does not crash the import")
	Progress.use_path("user://test_progress_v12.json")


func _achievement_hooks() -> void:
	Progress.use_path("user://test_progress_v12c.json")
	GameState.grid.set_on("aux", false)
	await t.physics(2)
	GameState.grid.set_on("aux", true)
	await t.physics(2)
	t.check(Progress.is_unlocked("generator"), "starting the generator unlocks Emergency Power")
	t.check(Progress.chapter_open("power"), "...and opens chapter II")
	GameState.set_flag("lab_entered")
	t.check(Progress.is_unlocked("lab_open"), "entering Lab 3 unlocks Clearance")
	GameState.inventory.add("research_drive")
	t.check(Progress.is_unlocked("drive") and Progress.chapter_open("ascent"), "the drive unlocks The Drive and chapter IV")
	var k: Keeper = g.keeper
	k.set_state(Keeper.S.REPELLED)
	t.check(Progress.is_unlocked("repel"), "driving it back unlocks Not Today")
	GameState.set_flag("doc_lift_log")
	t.check(Progress.is_unlocked("engineer"), "reading the engineer's log unlocks Winch Room")
	_place_keeper(Vector3(0.0, 0.05, -30.0), Keeper.S.PATROL)


func _chapters() -> void:
	Progress.use_path("user://test_progress_v12d.json")
	Legacy.reset_chain()
	Legacy.begin_expedition()
	var run_before: Variant = Legacy.chain["run"]
	var counter := int(Legacy.chain["counter"])
	t.check(not Progress.begin_chapter("lab"), "a locked chapter cannot be started")
	for c in Progress.CHAPTERS:
		Progress.open_chapter(c["id"], true)
	var want := {"descent": [[], false], "power": [["aux", "corridor_lights"], false], "lab": [["aux", "lab"], false], "ascent": [["aux", "lab"], true]}
	for c in Progress.CHAPTERS:
		var id: String = c["id"]
		t.check(Progress.begin_chapter(id), "chapter %s starts" % id)
		var gg: Node = load("res://scenes/game.tscn").instantiate()
		t.sandbox.add_child(gg)
		await t.physics(8)
		var pr := Progress.preset(id)
		if not (pr["spawn"] as Array).is_empty():
			var sp: Array = pr["spawn"][0]
			t.check(gg.player.global_position.distance_to(Vector3(sp[0], sp[1], sp[2])) < 0.6, "  %s: you start at the checkpoint" % id)
		for circ in want[id][0]:
			t.check(GameState.grid.is_on(circ), "  %s: circuit %s is on" % [id, circ])
		t.eq(GameState.inventory.has("research_drive"), want[id][1], "  %s: drive in hand only in the last chapter" % id)
		if gg.keeper:
			t.check(gg.keeper.global_position.distance_to(gg.player.global_position) > 12.0, "  %s: the Keeper starts well away from you" % id)
		t.check(not GameState.chain_mode and GameState.chapter_run == id, "  %s: a replay, not a chain run" % id)
		Legacy.decide("drive", "kept")
		Legacy.record_tape("tape_mara")
		gg.autosave()
		t.check(not Legacy.chain["decisions"].has("drive") and not Legacy.chain["tapes"].has("tape_mara"), "  %s: decisions and tapes never reach the chain" % id)
		gg.queue_free()
		await t.physics(3)
	t.eq(Legacy.chain["run"], run_before, "the chain's Continue slot is untouched by chapter runs")
	t.eq(int(Legacy.chain["counter"]), counter, "the chain save was never written by chapter runs")
	GameState.new_expedition(1234)
	t.eq(GameState.chapter_run, "", "a new expedition is not a chapter run")


# ----------------------------------------------------------------- menus
func _fire(action: String) -> void:
	var ev: InputEvent = null
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			ev = e.duplicate()
			break
	if ev == null:
		return
	ev.pressed = true
	Input.parse_input_event(ev)
	await t.frames(2)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await t.frames(2)


func _menu_screens() -> void:
	Progress.use_path("user://test_progress_v12e.json")
	var m: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	t.sandbox.add_child(m)
	await t.frames(6)
	for pair in [["HowTo", "howto"], ["Achievements", "achievements"], ["Chapters", "chapters"]]:
		t.check(m.buttons.has(pair[0]) and m.buttons[pair[0]].visible, "main menu has %s" % pair[0])
		m.buttons[pair[0]].grab_focus()
		await _fire("ui_accept")
		await t.frames(3)
		t.eq(m.current_screen(), pair[1], "%s opens" % pair[0])
		var fo: Control = t.sandbox.get_viewport().gui_get_focus_owner()
		t.check(fo != null and m.is_ancestor_of(fo), "%s has focus (keyboard / controller)" % pair[0])
		if pair[1] == "howto":
			var h: HowToPlayScreen = m._howto
			t.eq(h.page, 0, "How to Play opens on the goal")
			await _fire("ui_tab_next")
			t.eq(h.page, 1, "next page with E / RB")
			t.check("Interact" in h._text.get_parsed_text() and "RUN" in h._text.get_parsed_text(), "the controls page lists keyboard, controller and touch")
			for i in 4:
				var txt := HowToPlayScreen.page_text(i).to_lower()
				t.check(not ("camp" in txt or "seal" in txt or "broadcast" in txt or "mara" in txt or "archive" in txt), "page %d has no spoilers" % i)
			t.check("heartbeat" in HowToPlayScreen.page_text(2), "survival tips mention the heartbeat")
			h._next.pressed.emit()
			t.eq(h.page, 2, "the Next button turns the page (touch)")
		if pair[1] == "chapters":
			var cs: ChaptersScreen = m._chapters
			t.eq(cs.rows.size(), Progress.CHAPTERS.size(), "all chapters listed")
			var started := [""]
			cs.start.connect(func(id): started[0] = id)
			(cs.rows["lab"] as FocusRow).activated.emit()
			t.eq(started[0], "", "a locked chapter does not start")
		await _fire("ui_cancel")
		await t.frames(3)
		t.eq(m.current_screen(), "main", "%s escapes back to the menu" % pair[0])
	# the taller menu still clears the footer at every aspect ratio
	for vs in [Vector2(1600, 900), Vector2(2000, 900), Vector2(1600, 1200)]:
		t.sandbox.get_viewport().size = Vector2i(vs)
		await t.frames(3)
		m.fit_column()
		var vis := m.get_viewport().get_visible_rect().size
		t.check(m.column_bottom() <= vis.y - 80.0, "menu column clears the footer at %dx%d (bottom %.0f of %.0f)" % [vs.x, vs.y, m.column_bottom(), vis.y])
	t.sandbox.get_viewport().size = Vector2i(1600, 900)
	m.queue_free()
	await t.frames(3)


# ----------------------------------------------------------------- RUN on phones
func _settings_run_default() -> void:
	var pth := "user://test_settings_v12.cfg"
	var keep := Settings.path
	Settings.path = pth
	Settings.force_touch = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pth))
	Settings.load_settings()
	t.eq(int(Settings.get_value("controls", "sprint_mode")), Settings.HOLD, "desktop: RUN stays hold by default")
	t.eq(bool(Settings.get_value("audio", "heartbeat")), true, "heartbeat on by default")
	t.eq(bool(Settings.get_value("controls", "vibration")), true, "vibration on by default")
	Settings.force_touch = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pth))
	Settings.load_settings()
	t.eq(int(Settings.get_value("controls", "sprint_mode")), Settings.TOGGLE, "touch: RUN is a tap (toggle) by default")
	# a 1.1 phone save with the old default stored: migrated once
	var cf := ConfigFile.new()
	cf.set_value("controls", "sprint_mode", 0)
	cf.save(pth)
	Settings.load_settings()
	t.eq(int(Settings.get_value("controls", "sprint_mode")), Settings.TOGGLE, "touch: an old save's untouched Hold becomes Toggle")
	Settings.set_value("controls", "sprint_mode", Settings.HOLD)
	Settings.load_settings()
	t.eq(int(Settings.get_value("controls", "sprint_mode")), Settings.HOLD, "touch: a Hold the player chose is kept")
	Settings.force_touch = false
	Settings.path = keep
	Settings.load_settings()


func _run_button() -> void:
	Settings.set_value("controls", "sprint_mode", Settings.TOGGLE, false)
	p.global_position = Vector3(0.0, 0.05, -10.0)
	p.vitals.stamina = 1.0
	p.vitals.exhausted = false
	p.vitals.health = 100.0
	Input.action_press("move_forward")
	await t.physics(4)
	_press("sprint")
	await t.physics(6)
	t.check(p.running and p.sprint_latched, "toggle: tap RUN while moving and you run")
	Input.action_release("move_forward")
	await t.physics(45)
	t.check(not p.sprint_latched, "toggle: let go of the stick and it stops")
	# tap first, then push (the old version dropped the latch on the very next frame)
	_press("sprint")
	await t.physics(8)
	Input.action_press("move_forward")
	await t.physics(6)
	t.check(p.running, "toggle: tap RUN, then push the stick: you run")
	Input.action_release("move_forward")
	await t.physics(45)
	# crouched: RUN stands you up
	p._set_crouch(true)
	Input.action_press("move_forward")
	_press("sprint")
	await t.physics(6)
	t.check(not p.crouching and p.running, "RUN while crouched stands you up and runs")
	Input.action_release("move_forward")
	await t.physics(45)
	# winded: feedback
	var why := [""]
	var cb := func(r): why[0] = r
	p.run_blocked.connect(cb)
	p.vitals.exhausted = true
	p.vitals.stamina = 0.1
	_press("sprint")
	await t.physics(2)
	t.eq(why[0], "Too tired to run", "winded: RUN says why it can't")
	t.check(p.run_block_t > 0.0, "winded: the RUN button flashes")
	p.vitals.exhausted = false
	p.vitals.stamina = 0.01
	Input.action_press("move_forward")
	_press("sprint")
	await t.physics(20)
	t.eq(why[0], "Out of breath", "running out of breath: a hint and a gasp")
	Input.action_release("move_forward")
	p.vitals.health = 10.0
	p.vitals.exhausted = false
	p.vitals.stamina = 1.0
	_press("sprint")
	await t.physics(2)
	t.eq(why[0], "Too hurt to run", "badly hurt: RUN says why")
	p.vitals.health = 100.0
	# pressed with no stick input: told to push the stick
	why[0] = ""
	await t.physics(45)
	_press("sprint")
	await t.physics(50)
	t.check(why[0] in ["Push the stick to run", "Move to run"], "RUN with no movement: told to move (%s)" % why[0])
	p.run_blocked.disconnect(cb)
	Settings.set_value("controls", "sprint_mode", Settings.HOLD, false)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventAction.new()
	u.action = action
	u.pressed = false
	Input.parse_input_event(u)


var _xf := Transform2D.IDENTITY   ## viewport (canvas) -> window coordinates
func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = _xf * pos
	e.pressed = down
	Input.parse_input_event(e)


func _touch_multitouch() -> void:
	Legacy.reset_chain()
	Legacy.begin_expedition()
	GameState.play_intro = false
	var gg: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(gg)
	await t.physics(8)
	var pl: Player = gg.player
	pl.set_control(true)
	var tc := TouchControls.new()
	tc.player = pl
	var cl := CanvasLayer.new()
	t.sandbox.add_child(cl)
	cl.add_child(tc)
	await t.frames(4)
	var run_b := tc.button("Sprint")
	var r: float = run_b.get_meta("radius")
	t.check(r >= 56.0, "RUN is a big target (%.0f px radius)" % r)
	t.check(run_b.passby_press, "sliding a thumb onto RUN presses it")
	var c := run_b.position + Vector2(r, r)
	var vs := tc.get_viewport().get_visible_rect().size
	_xf = tc.get_viewport().get_final_transform()
	t.check(not tc._button_at(c + Vector2(r + 4.0, 0)), "no dead ring: a touch just outside RUN is not swallowed")
	t.check(tc._button_at(c + Vector2(r - 2.0, 0)), "the edge of RUN is RUN")
	# order 1: stick finger down first, then RUN
	_touch(0, Vector2(vs.x * 0.15, vs.y * 0.7), true)
	await t.frames(2)
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = _xf * Vector2(vs.x * 0.15, vs.y * 0.7 - 80.0)
	d.relative = _xf.basis_xform(Vector2(0, -80))
	Input.parse_input_event(d)
	await t.frames(2)
	_touch(1, c, true)
	await t.frames(2)
	t.check(Input.is_action_pressed("sprint"), "stick first, then RUN: RUN registers")
	t.check(tc.stick_vec.length() > 0.5, "stick first, then RUN: the stick still moves you")
	_touch(1, c, false)
	_touch(0, Vector2(vs.x * 0.15, vs.y * 0.7 - 80.0), false)
	await t.frames(2)
	t.check(not Input.is_action_pressed("sprint") and tc.stick_vec.length() < 0.01, "both released")
	# order 2: RUN first, then the stick
	_touch(0, c, true)
	await t.frames(2)
	_touch(1, Vector2(vs.x * 0.15, vs.y * 0.7), true)
	await t.frames(1)
	var d2 := InputEventScreenDrag.new()
	d2.index = 1
	d2.position = _xf * Vector2(vs.x * 0.15, vs.y * 0.7 - 80.0)
	d2.relative = _xf.basis_xform(Vector2(0, -80))
	Input.parse_input_event(d2)
	await t.frames(2)
	t.check(Input.is_action_pressed("sprint"), "RUN first, then the stick: RUN stays held")
	t.check(tc.stick_vec.length() > 0.5, "RUN first, then the stick: the stick works")
	_touch(1, Vector2(vs.x * 0.15, vs.y * 0.7 - 80.0), false)
	_touch(0, c, false)
	await t.frames(2)
	# a touch just outside RUN on the right half becomes look, not a dead touch
	_touch(2, c + Vector2(0, -(r + 6.0)), true)
	await t.frames(2)
	t.eq(tc._look_finger, 2, "a touch just outside RUN turns the camera instead of vanishing")
	_touch(2, c + Vector2(0, -(r + 6.0)), false)
	await t.frames(2)
	t.check(tc.run_ring != null, "a stamina ring is drawn around RUN")
	cl.queue_free()
	gg.queue_free()
	await t.physics(3)


func _export() -> void:
	var cf := ConfigFile.new()
	cf.load("res://export_presets.cfg")
	var vib := false
	for s in cf.get_sections():
		if s.ends_with(".options") and cf.has_section_key(s, "permissions/vibrate"):
			vib = bool(cf.get_value(s, "permissions/vibrate"))
	t.check(vib, "Android export asks for the VIBRATE permission")
	t.eq(str(ProjectSettings.get_setting("application/config/version")), "1.2.0", "the game says v1.2.0")
	var code := 0
	var vname := ""
	var winv := ""
	for s in cf.get_sections():
		if s.ends_with(".options"):
			if cf.has_section_key(s, "version/code"):
				code = int(cf.get_value(s, "version/code"))
				vname = str(cf.get_value(s, "version/name"))
			if cf.has_section_key(s, "application/file_version"):
				winv = str(cf.get_value(s, "application/file_version"))
	t.eq(code, 4, "Android versionCode 4 (installs over v1.1's 3)")
	t.eq(vname, "1.2.0", "Android version name 1.2.0")
	t.eq(winv, "1.2.0.0", "Windows file version 1.2.0.0")


# ----------------------------------------------------------------- v1.2 lift + winch room
func _new_area() -> void:
	Legacy.reset_chain()
	Legacy.begin_expedition()
	GameState.play_intro = false
	var gg: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(gg)
	await t.physics(10)
	var lvl: Node3D = gg.level
	var pl: Player = gg.player
	pl.set_control(true)
	for n in ["lift_cage", "lift_rail", "lift_cables", "lift_counterweight", "shaft_bunton", "shaft_column", "lift_callbox", "winch", "records_fill"]:
		t.check(GfxV12.mesh(n) != null and GfxV12.added.has(n), "v1.2 Blender mesh '%s' loads and is placed" % n)
		var me := GfxV12.mesh(n)
		if me:
			var has_uv2 := false
			for s in me.get_surface_count():
				var arr := me.surface_get_arrays(s)
				has_uv2 = has_uv2 or (arr[Mesh.ARRAY_TEX_UV2] != null and (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() > 0)
			t.check(has_uv2 and ResourceLoader.exists(GfxV12.DIR + n + "_bake.png"), "  '%s' has a lightmap UV and a baked AO/grime map" % n)
	var cage := lvl.find_child("v12_lift_cage", true, false) as Node3D
	t.check(cage != null and lvl.find_child("Lift", true, false).is_ancestor_of(cage), "the new cage rides with the Lift group (cold-open still carries it)")
	t.check(lvl.find_child("CageFrontCollision", true, false) != null, "the cage front still stops the player")
	var rails := 0
	for c in lvl.get_node("Geometry/EntranceShaft").get_children():
		if GfxV12._is_rail(c) and (c as Node).find_children("*", "CollisionShape3D", true, false).size() > 0 and not (c.get_node("Mesh") as MeshInstance3D).visible:
			rails += 1
	t.eq(rails, 2, "both guide rails keep their colliders (old boxes hidden)")
	var tris := 0
	for n in GfxV12.added:
		var me := GfxV12.mesh(n)
		for s in me.get_surface_count():
			tris += (me.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	t.check(tris < 70000, "v1.2 meshes stay light (%d tris placed in total)" % tris)
	# the door and the room
	var door: Door = lvl.get_node("Interactables/DoorWinch")
	t.check(door != null and door.lock_reason(pl) == "", "the winch room door is unlocked")
	t.eq(Zones.area_at(Vector3(7.0, 0, 4.0)), "winch", "the winch room is its own area")
	t.eq(Lore.depth_rank("winch"), 0, "...at the depth of the shaft (no handoff 'deepest' change)")
	door.set_open_immediate(true)
	await t.physics(2)
	pl.global_position = Vector3(2.6, 0.05, 4.0)
	pl.cam.set_view(-90.0, -5.0)
	Input.action_press("move_forward")
	var reached := false
	for i in 300:
		await t.physics(1)
		if pl.global_position.x > 6.0:
			reached = true
			break
	Input.action_release("move_forward")
	t.check(reached, "you can walk from the shaft through the door into the winch room (x %.1f)" % pl.global_position.x)
	# the Keeper can reach it (nav mesh) and its patrol includes it
	var map := lvl.get_world_3d().navigation_map
	await t.physics(4)
	var path := NavigationServer3D.map_get_path(map, Vector3(0.0, 0.05, -3.0), Vector3(7.0, 0.05, 4.6), true)
	t.check(path.size() > 1 and path[path.size() - 1].distance_to(Vector3(7.0, 0.05, 4.6)) < 0.8, "the Keeper's nav mesh reaches the winch room")
	t.check(NavBaker.PATROL.has(Vector3(6.6, 0, 4.6)), "the winch room is on its patrol")
	# the locker hides you, and the Keeper can't see you in it from the doorway
	var lk: HidingSpot = lvl.get_node("Interactables/LockerWinch")
	pl.global_position = lk.outside_point()
	await t.physics(2)
	lk.interact(pl)
	await t.physics(4)
	t.check(pl.hidden_in == lk, "the winch room locker hides you")
	var k: Keeper = gg.keeper
	k.think = false
	k.global_position = Vector3(4.6, 0.05, 4.0)
	k.look_at_flat(lk.global_position)
	await t.physics(2)
	t.check(not k.can_see_player(), "hidden in it, the Keeper at the door can't see you")
	lk.leave(pl)
	await t.physics(4)
	# a clear line from the shaft into the room only through the door
	var space := lvl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(2.0, 1.5, 2.0), Vector3(7.0, 1.5, 2.0))
	q.collision_mask = 1
	t.check(not space.intersect_ray(q).is_empty(), "the shaft wall blocks sight into the room away from the door")
	# the engineer's log
	var log_ := lvl.find_child("Doc_lift_log", true, false)
	t.check(log_ != null, "the engineer's log lies on the desk")
	if log_:
		log_.interact(pl)
		t.check(GameState.get_flag("doc_lift_log"), "reading it sets its flag (achievement: Winch Room)")
		Events.set_modal(false)
	t.check(not ("camp" in Notes.get_note("lift_log")["body"].to_lower()), "the log spoils nothing")
	gg.queue_free()
	await t.physics(3)
