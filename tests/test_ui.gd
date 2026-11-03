extends TestCase
## Phase 5 UI: every screen is reachable and escapable with the keyboard AND with a
## gamepad, using the real input events bound in the InputMap (not direct calls).

var pad := false


## Fire the first InputMap event of `action` for the current device (key or pad).
func fire(action: String) -> void:
	var ev: InputEvent = null
	for e in InputMap.action_get_events(action):
		if pad and (e is InputEventJoypadButton):
			ev = e.duplicate()
			break
		if not pad and (e is InputEventKey):
			ev = e.duplicate()
			break
	if ev == null and pad:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion:
				ev = e.duplicate()
				break
	if ev == null:
		t.fail("no %s binding for %s" % ["pad" if pad else "key", action])
		return
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.keycode == KEY_NONE and k.physical_keycode != KEY_NONE:
			k.keycode = k.physical_keycode
		k.pressed = true
	elif ev is InputEventJoypadButton:
		(ev as InputEventJoypadButton).pressed = true
	elif ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		m.axis_value = signf(m.axis_value) if m.axis_value != 0.0 else 1.0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await t.frames(2)
	var up: InputEvent = ev.duplicate()
	if up is InputEventKey:
		(up as InputEventKey).pressed = false
	elif up is InputEventJoypadButton:
		(up as InputEventJoypadButton).pressed = false
	elif up is InputEventJoypadMotion:
		(up as InputEventJoypadMotion).axis_value = 0.0
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await t.frames(2)


func focused() -> Control:
	return t.sandbox.get_viewport().gui_get_focus_owner()


## Walk with `dir` up to n steps; return the set of controls that held focus.
func walk(dir: String, n: int) -> Array:
	var seen: Array = []
	for i in n:
		var f := focused()
		if f and not seen.has(f):
			seen.append(f)
		await fire(dir)
	var f2 := focused()
	if f2 and not seen.has(f2):
		seen.append(f2)
	return seen


func dev() -> String:
	return "gamepad" if pad else "keyboard"


func run() -> void:
	Settings.reset_binds(false)
	for p in [false, true]:
		pad = p
		await _menu()
	for p in [false, true]:
		pad = p
		await _game_screens()
	await _handoff_focus()


func _menu() -> void:
	var m: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	t.sandbox.add_child(m)
	await t.frames(6)
	t.eq(m.current_screen(), "main", "[%s] main menu opens on the main list" % dev())
	m.focus_default()
	await t.frames(1)
	var want: Array = m.buttons.values().filter(func(b): return b.visible and not b.disabled)
	var seen := await walk("ui_down", want.size() + 2)
	var all := true
	for b in want:
		if not seen.has(b):
			all = false
			t.fail("[%s] menu button %s not reachable with ui_down" % [dev(), b.name])
	t.check(all, "[%s] every main menu button reachable (%d)" % [dev(), want.size()])
	for pair in [["Settings", "settings"], ["History", "history"], ["Credits", "credits"]]:
		m.buttons[pair[0]].grab_focus()
		await fire("ui_accept")
		await t.frames(3)
		t.eq(m.current_screen(), pair[1], "[%s] %s opens with accept" % [dev(), pair[0]])
		t.check(focused() != null and m.is_ancestor_of(focused()), "[%s] %s has focus on open" % [dev(), pair[0]])
		if pair[1] == "settings":
			await _settings_nav(m._settings, m)
		await fire("ui_cancel")
		await t.frames(3)
		t.eq(m.current_screen(), "main", "[%s] %s escapes back to the menu" % [dev(), pair[0]])
		t.check(focused() == m.buttons[pair[0]], "[%s] focus returns to %s" % [dev(), pair[0]])
	# brightness calibration from settings, and back
	m.open_settings()
	await t.frames(3)
	m._settings.calibrate.call()
	await t.frames(3)
	t.eq(m.current_screen(), "brightness", "[%s] brightness calibration opens from settings" % dev())
	await fire("ui_right")
	await fire("ui_cancel")
	await t.frames(3)
	t.eq(m.current_screen(), "settings", "[%s] calibration escapes back to settings" % dev())
	await fire("ui_cancel")
	await t.frames(3)
	t.eq(m.current_screen(), "main", "[%s] and back to the menu" % dev())
	m.queue_free()
	await t.frames(3)


func _settings_nav(s: SettingsMenu, _owner: Node) -> void:
	for tab in 4:
		t.eq(s.tab, tab, "[%s] settings on tab %d" % [dev(), tab])
		s.focus_first()
		await t.frames(1)
		var want: Array = s.focusables()
		var seen := await walk("ui_down", want.size() + 3)
		var missing := want.filter(func(c): return not seen.has(c))
		if not missing.is_empty():
			# grid rows (key | pad): the second column is one step right, then down
			s.focus_first()
			await t.frames(1)
			var guard := 0
			while not focused().name.begins_with("Bind_") and guard < 20:
				await fire("ui_down")
				guard += 1
			await fire("ui_right")
			seen.append_array(await walk("ui_down", want.size() + 3))
			missing = want.filter(func(c): return not seen.has(c))
		t.check(missing.is_empty(), "[%s] tab %d: all %d controls reachable with down%s" % [dev(), tab, want.size(), "" if missing.is_empty() else " (missing %s)" % str(missing.map(func(c): return c.name))])
		if tab < 3:
			await fire("ui_tab_next")
			await t.frames(2)
	await fire("ui_tab_prev")
	await t.frames(2)
	t.eq(s.tab, 2, "[%s] previous tab" % dev())
	s.set_tab(0, false)


func _game_screens() -> void:
	GameState.new_expedition(77)
	GameState.threat_enabled = false
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(8)
	var pm: Node = g.get_node("PauseMenu")
	await fire("pause")
	await t.frames(3)
	t.check(pm.is_open(), "[%s] pause opens" % dev())
	t.check(focused() != null and pm.is_ancestor_of(focused()), "[%s] pause has focus" % dev())
	var want: Array = pm.buttons.values().filter(func(b): return b.visible)
	var seen := await walk("ui_down", want.size() + 2)
	t.check(want.all(func(b): return seen.has(b)), "[%s] every pause button reachable" % dev())
	pm.buttons["Settings"].grab_focus()
	await fire("ui_accept")
	await t.frames(3)
	t.eq(pm.current_screen(), "settings", "[%s] pause > settings" % dev())
	await fire("ui_cancel")
	await t.frames(3)
	t.eq(pm.current_screen(), "main", "[%s] settings escapes to pause" % dev())
	await fire("ui_cancel")
	await t.frames(3)
	t.check(not pm.is_open() and not t.sandbox.get_tree().paused, "[%s] pause escapes back to play" % dev())
	# inventory
	GameState.inventory.add("battery", 1)
	GameState.inventory.add("medkit", 1)
	await fire("inventory")
	await t.frames(3)
	t.check(g.hud.inventory_panel.visible, "[%s] inventory opens" % dev())
	t.check(focused() != null and g.hud.inventory_panel.is_ancestor_of(focused()), "[%s] inventory slot focused" % dev())
	var f0 := focused()
	await fire("ui_right")
	t.check(focused() != f0, "[%s] inventory slots navigable" % dev())
	await fire("ui_cancel")
	await t.frames(3)
	t.check(not g.hud.inventory_panel.visible and not Events.modal_open, "[%s] inventory escapes" % dev())
	# note reader
	g.hud.open_note("TEST", "body")
	await t.frames(2)
	await fire("ui_cancel")
	await t.frames(2)
	t.check(not g.hud.note_panel.visible, "[%s] note reader escapes" % dev())
	g.queue_free()
	await t.frames(4)
	t.sandbox.get_tree().paused = false
	Events.set_modal(false)


func _handoff_focus() -> void:
	pad = true
	GameState.new_expedition(91)
	GameState.threat_enabled = false
	var g: Node = load("res://scenes/game.tscn").instantiate()
	t.sandbox.add_child(g)
	await t.physics(6)
	GameState.inventory.add("battery", 1)
	GameState.inventory.add("fuse", 1)
	g.hud.show_handoff()
	var hs: HandoffScreen = null
	for i in 300:
		await t.frames(1)
		if g.hud.handoff != null and g.hud.handoff.visible:
			hs = g.hud.handoff
			break
	if not t.check(hs != null, "handoff screen shows after a death"):
		g.queue_free()
		return
	await t.frames(3)
	t.check(focused() != null and hs.is_ancestor_of(focused()), "handoff screen has gamepad focus")
	# the explicit neighbour graph reaches every control from Leave
	var reach := {}
	var todo: Array = [focused()]
	while not todo.is_empty():
		var c: Control = todo.pop_back()
		if reach.has(c):
			continue
		reach[c] = true
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var np := c.get_focus_neighbor(side)
			if np != NodePath():
				var n := c.get_node_or_null(np) as Control
				if n and n.visible:
					todo.append(n)
	var fl: Array = hs.focusables()
	var miss := fl.filter(func(c): return not reach.has(c))
	t.check(miss.is_empty(), "every handoff control reachable by d-pad (%d)%s" % [fl.size(), "" if miss.is_empty() else " missing " + str(miss.map(func(c): return c.name))])
	var before := focused()
	await fire("ui_up")
	t.check(focused() != before, "d-pad moves focus on the handoff screen")
	g.queue_free()
	await t.frames(4)
	t.sandbox.get_tree().paused = false
	Events.set_modal(false)
