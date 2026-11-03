extends TestCase
## v1.0.1 bug-hunt regressions: Android back button, app focus loss / background,
## controller unplugged, touch taps in the rebind screen, notch / safe area and
## 16:9 / 20:9 / 4:3 touch layout, touch prompts, the soft keyboard over the handoff
## message box, BBCode in the player's own handoff words, a 25-expedition chain
## through save/load, a second ending trigger, and the navmesh agent radius warning.

var g: Node
var p: Player


func _tree() -> SceneTree:
	return t.sandbox.get_tree()


func run() -> void:
	t.eq(ProjectSettings.get_setting("application/config/quit_on_go_back", true), false, "Android back button does not quit the app")
	Legacy.reset_chain()
	Legacy.begin_expedition()
	GameState.play_intro = false
	g = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	p = g.player
	await t.physics(10)
	p.set_control(true)
	await _lifecycle()
	await _back_button()
	await _pad_unplugged()
	await _rebind_tap()
	await _safe_area_layouts()
	await _touch_prompts()
	await _keyboard_lift()
	_bbcode_words()
	_second_ending()
	_nav_radius()
	_subtitle_timing()
	await _gas_visible()
	g.queue_free()
	g = null
	await t.physics(3)
	await _long_chain()
	await _menu_fits()


func _pm() -> Node:
	return g.get_node("PauseMenu")


func _lifecycle() -> void:
	t.check(not _tree().paused and not Events.modal_open, "precondition: playing")
	var saves_before := str(Legacy.chain.get("run", {}).get("state", ""))
	GameState.elapsed = 123.0
	Ux.app_background(true)
	await t.frames(2)
	t.check(_pm().is_open(), "focus lost / app backgrounded mid-run opens the pause menu")
	t.check(_tree().paused, "the game is paused while in the background")
	t.check(AudioServer.is_bus_mute(0), "audio is silenced while in the background")
	var run: Variant = Legacy.chain.get("run")
	t.check(run is Dictionary and run.has("state") and str(run["state"]) != saves_before, "the run is saved when the app goes to the background")
	Ux.app_foreground()
	await t.frames(2)
	t.check(not AudioServer.is_bus_mute(0), "audio comes back on return")
	t.check(_pm().is_open() and _tree().paused, "the pause menu waits for the player on return")
	_pm().resume()
	await t.frames(2)
	# with a panel open (inventory is real-time) the world still stops, and resumes on return
	g.hud.open_inventory()
	await t.frames(1)
	Ux.app_background(false)
	t.check(_tree().paused and not _pm().is_open(), "backgrounded with the inventory open: world paused, no pause menu stacked on it")
	Ux.app_foreground()
	t.check(not _tree().paused and g.hud.inventory_panel.visible, "back from the background: world runs again, inventory still open")
	g.hud.close_inventory()
	await t.frames(2)
	# a muted master volume stays muted after a round trip
	Settings.set_value("audio", "master", 0.0, false)
	Ux.app_background(false)
	Ux.app_foreground()
	t.check(AudioServer.is_bus_mute(0), "a player-muted master volume stays muted after returning")
	Settings.set_value("audio", "master", 0.9, false)
	_pm().resume()
	await t.frames(2)


func _back() -> void:
	Ux.go_back()
	Input.flush_buffered_events()
	await t.frames(3)


func _back_button() -> void:
	t.check(not _pm().is_open(), "precondition: not paused")
	await _back()
	t.check(_pm().is_open(), "back button in play opens the pause menu")
	await _back()
	t.check(not _pm().is_open() and not _tree().paused, "back button again resumes")
	g.hud.open_inventory()
	await t.frames(2)
	await _back()
	t.check(not g.hud.inventory_panel.visible, "back button closes the inventory")
	await t.frames(2)


func _pad_unplugged() -> void:
	Ux.using_pad = true
	Input.action_press("move_forward", 1.0)
	Ux._on_joy_connection(0, false)
	await t.frames(2)
	t.check(not Input.is_action_pressed("move_forward"), "controller unplugged: held stick input is released")
	t.check(_pm().is_open(), "controller unplugged mid-run: the game pauses")
	t.check(not Ux.using_pad, "prompts fall back to keyboard after the pad is gone")
	_pm().resume()
	await t.frames(2)


func _rebind_tap() -> void:
	var sm := SettingsMenu.new()
	t.sandbox.add_child(sm)
	await t.frames(2)
	var before := Settings.binding("interact", "kb")
	sm.start_listen("interact", "kb")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.device = InputEvent.DEVICE_ID_EMULATION   # a finger tap posing as a click
	sm._capture(e)
	t.check(sm.listening.is_empty(), "a touchscreen tap cancels 'press a key' instead of leaving it stuck")
	t.eq(Settings.binding("interact", "kb"), before, "a tap is never bound as Left Mouse (it would fire on every tap)")
	sm.queue_free()
	await t.frames(2)


func _layout_ok(tc: TouchControls, vs: Vector2, safe: Rect2, label: String) -> void:
	var names: Array = tc.button_names()
	var inside := true
	var overlap := false
	for n in names:
		var b := tc.button(n)
		var r: float = b.get_meta("radius")
		var c: Vector2 = b.position + Vector2(r, r)
		if c.x - r < safe.position.x - 0.5 or c.x + r > safe.end.x + 0.5 or c.y - r < safe.position.y - 0.5 or c.y + r > safe.end.y + 0.5 or c.x < vs.x * 0.5:
			inside = false
			t.fail("%s: %s outside the safe right half (%.0f, %.0f)" % [label, n, c.x, c.y])
		for m in names:
			if m != n:
				var b2 := tc.button(m)
				var r2: float = b2.get_meta("radius")
				if c.distance_to(b2.position + Vector2(r2, r2)) < r + r2:
					overlap = true
	t.check(inside, "%s: every touch button inside the safe area, right half" % label)
	t.check(not overlap, "%s: no touch buttons overlap" % label)


func _safe_area_layouts() -> void:
	for spec in [[Vector2i(1600, 900), "16:9"], [Vector2i(2000, 900), "20:9"], [Vector2i(1600, 1200), "4:3"]]:
		for notch in [false, true]:
			var sv := SubViewport.new()
			sv.size = spec[0]
			t.sandbox.add_child(sv)
			var vs := Vector2(spec[0])
			var safe := Rect2(Vector2.ZERO, vs)
			if notch:   # notch on the right edge (sensor landscape) + a gesture bar
				safe = Rect2(60, 0, vs.x - 60 - 120, vs.y - 28)
				Ux.safe_override = safe
			var tc := TouchControls.new()
			sv.add_child(tc)
			await t.frames(2)
			_layout_ok(tc, vs, safe, "%s%s" % [spec[1], " + notch" if notch else ""])
			Ux.safe_override = Rect2()
			sv.queue_free()
			await t.frames(1)
	# the HUD corner widgets step out of a notch on the left
	var vs2 := g.get_viewport().get_visible_rect().size
	Ux.safe_override = Rect2(120, 30, vs2.x - 240, vs2.y - 60)
	g.hud.apply_safe_area()
	t.check(g.hud._obj_box.position.x >= 120 and g.hud._obj_box.position.y >= 30, "HUD objective moves out of a notch")
	t.check(g.hud._device.offset_left >= 120, "HUD field device moves out of a notch")
	t.check(g.hud._toasts.offset_right <= -120 - 44, "HUD toasts move out of a right-side notch")
	Ux.safe_override = Rect2()
	g.hud.apply_safe_area()
	t.eq(g.hud._obj_box.position, Vector2(48, 38), "no notch: HUD layout unchanged")


func _touch_prompts() -> void:
	var hb := UIKit.hint_bar([["ui_accept", "Select"], ["ui_cancel", "Back"]])
	t.sandbox.add_child(hb)
	var gb := GlyphBadge.new("interact", 20)
	t.sandbox.add_child(gb)
	await t.frames(1)
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = Vector2(50, 50)
	e.pressed = true
	Ux._input(e)
	t.check(Ux.using_touch, "a finger on the screen switches prompts to touch")
	t.eq(Ux.glyph("interact"), "USE", "prompts name the on-screen USE button")
	t.eq(Ux.glyph("reload_battery"), "CELL", "swap-cell prompt names the CELL button")
	t.eq(gb._text, "USE", "interaction prompt badge shows USE on a touchscreen")
	t.eq(hb.modulate.a, 0.0, "keyboard / pad hint bars are hidden on a touchscreen")
	var k := InputEventKey.new()
	k.keycode = KEY_W
	k.pressed = true
	Ux._input(k)
	t.check(not Ux.using_touch, "a real key press switches prompts back")
	t.eq(hb.modulate.a, 1.0, "hint bars come back with a keyboard")
	Ux.go_back()   # the synthetic back-button Esc must not count as a keyboard
	Input.flush_buffered_events()
	await t.frames(2)
	if _pm().is_open():
		_pm().resume()
	hb.queue_free()
	gb.queue_free()
	await t.frames(2)
	# the CELL button exists, drives reload, and shows only with a spare cell
	var tl := CanvasLayer.new()
	g.hud.add_child(tl)
	var tc := TouchControls.new()
	tc.player = p
	tl.add_child(tc)
	await t.frames(2)
	t.check(tc.button("Cell") != null and tc.button("Cell").action == "reload_battery", "touch CELL button drives the battery swap")
	while GameState.inventory.count("battery") > 0:
		GameState.inventory.remove("battery", 1)
	await t.frames(2)
	t.check(not tc.button("Cell").visible, "CELL hidden with no spare cell")
	GameState.inventory.add("battery", 1)
	await t.frames(2)
	t.check(tc.button("Cell").visible, "CELL shown with a spare cell")
	tl.queue_free()
	await t.frames(2)


func _keyboard_lift() -> void:
	var cl := CanvasLayer.new()
	t.sandbox.add_child(cl)
	var hs := HandoffScreen.new()
	cl.add_child(hs)
	await t.frames(3)
	t.eq(hs.keyboard_shift(0, 900), 0.0, "no soft keyboard: the handoff form stays put")
	var vs := hs.get_viewport().get_visible_rect().size
	var win_h := int(vs.y)
	var kh := int(vs.y * 0.5)
	var sh := hs.keyboard_shift(kh, win_h)
	var bottom := hs._custom_edit.get_global_rect().end.y + sh
	t.check(bottom <= vs.y - kh + 0.5, "soft keyboard open: the message box is lifted above it (bottom %.0f, keyboard top %.0f)" % [bottom, vs.y - kh])
	t.check(hs._custom_edit.virtual_keyboard_enabled, "the message box opens the soft keyboard")
	cl.queue_free()
	await t.frames(2)


func _bbcode_words() -> void:
	var words := "[/i][color=red]x[img]res://icon.png[/img] [url=a]b[/url]"
	var body := ChainDirector._note_body(9, "R. Okafor", "", words)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = body
	t.sandbox.add_child(rt)
	t.check(words in rt.get_parsed_text(), "the player's handoff words show literally, BBCode is not parsed")
	rt.queue_free()


func _second_ending() -> void:
	var fake := Node.new()
	g.ending = fake
	var was: bool = g.ended
	g._on_ending("seal")
	t.eq(g.ended, was, "a second ending trigger during an ending is ignored")
	g.ending = null
	fake.free()


func _nav_radius() -> void:
	var nav := g.find_child("KeeperNav", true, false) as NavigationRegion3D
	t.check(nav != null and nav.navigation_mesh != null, "Keeper navmesh exists")
	if nav and nav.navigation_mesh:
		var nm := nav.navigation_mesh
		t.check(is_zero_approx(fmod(nm.agent_radius, nm.cell_size)), "navmesh agent radius is whole cells (no precision warning)")


func _long_chain() -> void:
	Legacy.reset_chain()
	var first := Legacy.next_expedition()
	var syms: Array = Lore.SYMBOLS.keys()
	for i in 25:
		Legacy.begin_expedition()
		Legacy.end_expedition("died" if i % 3 else "extracted", Vector3(i * 0.5, 0, -3), "corridor")
		Legacy.commit_handoff(Lore.TEMPLATES[i % Lore.TEMPLATES.size()], "nr %d: ünï \"q\" [b] \\ / %%s" % i, "", str(syms[i % syms.size()]))
	var path := Legacy.path
	t.check(SaveIO.load_json(path)["ok"], "after 25 expeditions the save file reads back")
	Legacy.load_chain()
	t.eq(Legacy.load_notice, "", "the 25-expedition save loads clean (no repair)")
	t.eq(Legacy.expeditions_done(), 25, "25 expeditions in the history after reload")
	t.eq(Legacy.next_expedition(), first + 25, "expedition numbering continues")
	var h: Array = Legacy.chain["history"]
	t.eq(str(h[24]["custom"]), "nr 24: ünï \"q\" [b] \\ / %s", "the last member's own words survive save/load exactly")
	t.check(Legacy.chain["marks"].size() <= Legacy.MAX_MARKS and Legacy.chain["notes"].size() <= Legacy.MAX_NOTES, "marks and wall notes stay capped")
	var nums := {}
	for e in h:
		nums[int(e["expedition"])] = true
	t.eq(nums.size(), 25, "no duplicated or lost expedition numbers")
	t.check(Legacy.history_rows().size() >= 25, "history screen rows include all 25")
	# and the 26th expedition boots into a world carrying all of that
	Legacy.begin_expedition()
	var g2: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g2)
	await t.physics(10)
	t.check(is_instance_valid(g2.player) and g2.player.global_position.y > -5.0, "expedition 26 boots with the player on the floor")
	g2.queue_free()
	await t.physics(3)
	Legacy.reset_chain()


func _subtitle_timing() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/logs/subtitles.json"))
	var bad := []
	for k in d:
		var L: Array = d[k]["lines"]
		for i in L.size():
			if float(L[i][1]) <= float(L[i][0]):
				bad.append("%s#%d empty" % [k, i])
			if i > 0 and float(L[i][0]) < float(L[i - 1][1]):
				bad.append("%s#%d overlaps" % [k, i])
	t.check(bad.is_empty(), "tape subtitles never overlap the previous line %s" % str(bad))


func _menu_fits() -> void:
	# worst case: a run in progress (CONTINUE shown) and a save-repair notice
	Legacy.reset_chain()
	Legacy.begin_expedition()
	Legacy.load_notice = "Your save file was damaged. Restored the previous save."
	var m: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	t.sandbox.add_child(m)
	await t.frames(4)
	var vs := m.get_viewport().get_visible_rect().size
	t.check(m.buttons["Continue"].visible, "precondition: CONTINUE shown")
	t.check(m.column_bottom() <= vs.y - 80.0, "main menu buttons clear the footer hint bar (bottom %.0f of %.0f)" % [m.column_bottom(), vs.y])
	var q: Control = m.buttons["Quit"]
	t.check(q.get_global_rect().end.y <= vs.y - 76.0, "QUIT does not overlap the footer (%.0f)" % q.get_global_rect().end.y)
	Legacy.load_notice = ""
	m.queue_free()
	await t.frames(2)
	Legacy.reset_chain()


func _gas_visible() -> void:
	var gas: Array = _tree().get_nodes_in_group("hazards").filter(func(n): return n is GasPocket and g.is_ancestor_of(n))
	t.check(gas.size() > 0, "the station has gas pockets")
	if gas.is_empty():
		return
	var q0: int = Settings.get_value("video", "quality")
	for q in [0, 3]:   # Low and Phone: no volumetric fog
		Settings.set_value("video", "quality", q, false)
		await t.frames(3)
		var gp: GasPocket = gas[0]
		t.check(gp.volumetric_active() or gp._haze.visible, "gas pocket is visible on the %s preset (volumetric fog or haze)" % Settings.QUALITY_NAMES[q])
	Settings.set_value("video", "quality", q0, false)
	await t.frames(2)
